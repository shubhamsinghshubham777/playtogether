import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Runs a Cloudflare Turnstile challenge in a webview and returns the
/// captcha token (null on cancel/failure). The page claims `localhost` as
/// its origin — that hostname must stay in the Turnstile widget allow-list.
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
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                data: _html,
                // Turnstile only issues tokens to allow-listed hostnames;
                // `localhost` is the one registered for this widget.
                baseUrl: WebUri('http://localhost/'),
              ),
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
