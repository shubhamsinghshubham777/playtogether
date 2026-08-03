import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:playtogether/auth/webview_runtime.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Runs a Cloudflare Turnstile challenge in a webview and returns the
/// captcha token (null on cancel/failure). The page is served from a throwaway
/// loopback server so its origin really is `localhost` — that hostname must
/// stay in the Turnstile widget allow-list.
Future<String?> showTurnstileDialog(BuildContext context) {
  return showGlassDialog<String>(
    context: context,
    width: 380,
    builder: (_) => const _TurnstileBody(),
  );
}

class _TurnstileBody extends StatefulWidget {
  const _TurnstileBody();

  @override
  State<_TurnstileBody> createState() => _TurnstileBodyState();
}

/// How long the challenge gets before we call it stuck. Turnstile normally
/// resolves in well under a second; this only has to be longer than a slow
/// cold WebView2 start.
const _kChallengeTimeout = Duration(seconds: 20);

class _TurnstileBodyState extends State<_TurnstileBody> {
  bool _failed = false;
  String? _errorCode;
  HttpServer? _server;
  Uri? _pageUrl;
  Timer? _timeout;
  bool _pageRequested = false;
  bool _webViewCreated = false;

  @override
  void initState() {
    super.initState();
    // Known before anything is drawn, and no amount of waiting or retrying
    // changes it — so say so immediately instead of after the full deadline.
    if (PTWebView.runtimeMissing) {
      _failed = true;
      _errorCode = 'webview2-missing';
      return;
    }
    _serve();
  }

  /// The silent-failure case, and the reason this timer exists: if the webview
  /// never renders at all, nothing throws and no error-callback fires, so the
  /// dialog just sits there looking patient. Without an explicit deadline that
  /// state produces no telemetry whatsoever — which is exactly the hole we
  /// fell into on Windows.
  void _armTimeout() {
    _timeout?.cancel();
    _timeout = Timer(_kChallengeTimeout, () {
      if (!mounted || _errorCode != null) return;
      reportNonFatal(
        StateError(
          'Turnstile produced neither a token nor an error in '
          '${_kChallengeTimeout.inSeconds}s '
          '(webview created: $_webViewCreated, page requested: $_pageRequested)',
        ),
        StackTrace.current,
        during: 'running the Turnstile challenge',
      );
      setState(() {
        _failed = true;
        // Three distinct causes, and the first two were previously
        // indistinguishable: a webview the platform refused to build at all,
        // one that built but never navigated, and one that loaded the page and
        // then heard nothing back from Cloudflare.
        _errorCode = !_webViewCreated
            ? 'webview-not-created'
            : _pageRequested
            ? 'no-response'
            : 'page-never-requested';
      });
    });
  }

  /// Hands the challenge page a real `http://localhost:<port>` origin.
  ///
  /// Loading it as inline data instead would be simpler, but Windows drops
  /// `InAppWebViewInitialData.baseUrl` on the floor — the WebView2 backend maps
  /// initial data straight onto `NavigateToString`, which has no baseUrl
  /// parameter and always yields an opaque origin. Turnstile then sees a
  /// hostname that is not on its allow-list, refuses to issue a token, and
  /// guest sign-in is impossible on Windows. A loopback server is the one form
  /// of origin every platform's webview agrees on.
  Future<void> _serve() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (!mounted) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen((request) {
        // Distinguishes "the webview never reached us" from "it loaded the page
        // and Turnstile then failed" — the two have completely different causes
        // and look identical from the outside.
        _pageRequested = true;
        trace('challenge page requested', category: 'turnstile', data: {'path': request.uri.path});
        request.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        request.response.close();
      });
      // `localhost` rather than 127.0.0.1: Turnstile matches on hostname, and
      // the literal IP is not what the widget is registered for. Webviews
      // resolve it dual-stack and fall back to the IPv4 loopback we bound.
      final url = Uri.parse('http://localhost:${server.port}/');
      trace('serving challenge', category: 'turnstile', data: {'url': '$url'});
      _armTimeout();
      setState(() => _pageUrl = url);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the Turnstile loopback server');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _server?.close(force: true);
    super.dispose();
  }

  String get _html =>
      '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?onload=onloadTurnstile" async defer></script>
<style>
  body { margin: 0; background: transparent; display: flex; justify-content: center; }
</style>
</head>
<body>
<div id="cf"></div>
<script>
function onloadTurnstile() {
  turnstile.render('#cf', {
    sitekey: '${Env.turnstileSiteKey}',
    theme: 'dark',
    callback: function (token) {
      window.flutter_inappwebview.callHandler('turnstileToken', token);
    },
    'error-callback': function (e) {
      window.flutter_inappwebview.callHandler('turnstileError', String(e));
      return true;
    },
  });
}
</script>
</body>
</html>
''';

  /// "Try again" is the right advice for a challenge that timed out, and the
  /// wrong advice for a PC that is missing the component this renders in —
  /// retrying that forever is precisely what people did.
  String get _failureMessage => _errorCode == 'webview2-missing'
      ? "Your PC is missing a Windows component this check needs. "
            "Reinstalling PlayTogether will add it."
      : "Hmm, the check didn't load. Close this and try again.";

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Text('Quick check', style: PTText.cardHeading),
        Text(
          _failed ? _failureMessage : "Just making sure you're human — takes a second.",
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
        ),
        // Shown only on failure, and deliberately not dressed up as friendly
        // copy: it exists so a bug report can quote it.
        if (_errorCode != null)
          Text(
            'Error $_errorCode',
            style: PTText.mono.copyWith(fontSize: 11.5, color: PTColors.white(0.4)),
          ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 80,
            child: _pageUrl == null
                ? const SizedBox.shrink()
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri.uri(_pageUrl!)),
                    initialSettings: InAppWebViewSettings(transparentBackground: true),
                    // Null off Windows, where the plugin's own default is right.
                    webViewEnvironment: PTWebView.environment,
                    // Turnstile reports its own diagnostics to the JS console
                    // (an unlisted hostname says so there in as many words),
                    // and that output is otherwise invisible in a release build.
                    onConsoleMessage: (_, msg) => trace(
                      msg.message,
                      category: 'turnstile.console',
                      data: {'level': msg.messageLevel.toString()},
                    ),
                    onReceivedError: (_, request, error) => trace(
                      'load error: ${error.description}',
                      category: 'turnstile.webview',
                      data: {'url': '${request.url}', 'type': '${error.type}'},
                    ),
                    onReceivedHttpError: (_, request, response) => trace(
                      'http error: ${response.statusCode}',
                      category: 'turnstile.webview',
                      data: {'url': '${request.url}'},
                    ),
                    onLoadStop: (_, url) => trace(
                      'load finished',
                      category: 'turnstile.webview',
                      data: {'url': '$url'},
                    ),
                    onWebViewCreated: (controller) {
                      // Never fires if the platform could not build the webview
                      // — which is the failure this dialog could not previously
                      // distinguish from Cloudflare never answering.
                      _webViewCreated = true;
                      controller.addJavaScriptHandler(
                        handlerName: 'turnstileToken',
                        callback: (args) {
                          final token = args.isNotEmpty ? args.first as String : null;
                          if (mounted && token != null) {
                            _timeout?.cancel();
                            Navigator.of(context).pop(token);
                          }
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'turnstileError',
                        callback: (args) {
                          // Cloudflare's code is the single most diagnostic
                          // thing available here — 110200 is an unlisted
                          // hostname, 300xxx/600xxx are render-side failures —
                          // so it goes to Sentry *and* on screen, because the
                          // person hitting this is usually not the person
                          // reading the dashboard.
                          final code = args.isNotEmpty ? '${args.first}' : 'unknown';
                          _timeout?.cancel();
                          reportNonFatal(
                            StateError('Turnstile error-callback: $code'),
                            StackTrace.current,
                            during: 'running the Turnstile challenge',
                          );
                          if (mounted) {
                            setState(() {
                              _failed = true;
                              _errorCode = code;
                            });
                          }
                        },
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}
