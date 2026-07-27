import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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

class _TurnstileBodyState extends State<_TurnstileBody> {
  bool _failed = false;
  HttpServer? _server;
  Uri? _pageUrl;

  @override
  void initState() {
    super.initState();
    _serve();
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
        request.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        request.response.close();
      });
      // `localhost` rather than 127.0.0.1: Turnstile matches on hostname, and
      // the literal IP is not what the widget is registered for. Webviews
      // resolve it dual-stack and fall back to the IPv4 loopback we bound.
      setState(() => _pageUrl = Uri.parse('http://localhost:${server.port}/'));
    } catch (e, s) {
      reportNonFatal(e, s, during: 'starting the Turnstile loopback server');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 14,
      children: [
        Text('Quick check', style: PTText.cardHeading),
        Text(
          _failed
              ? "Hmm, the check didn't load. Close this and try again."
              : "Just making sure you're human — takes a second.",
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.6)),
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
                    onWebViewCreated: (controller) {
                      controller.addJavaScriptHandler(
                        handlerName: 'turnstileToken',
                        callback: (args) {
                          final token = args.isNotEmpty ? args.first as String : null;
                          if (mounted && token != null) Navigator.of(context).pop(token);
                        },
                      );
                      controller.addJavaScriptHandler(
                        handlerName: 'turnstileError',
                        callback: (_) {
                          if (mounted) setState(() => _failed = true);
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
