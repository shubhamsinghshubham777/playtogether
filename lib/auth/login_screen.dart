import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/auth/auth_service.dart';
import 'package:playtogether/auth/turnstile_dialog.dart';
import 'package:playtogether/env.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleLoading = false;
  bool _guestLoading = false;

  Future<void> _run(Future<void> Function() action, void Function(bool) setLoading) async {
    setLoading(true);
    try {
      await action();
      // Navigation happens via the router's auth redirect.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't sign you in — give it another try.")),
        );
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  void _signInWithGoogle() =>
      _run(AuthService.instance.signInWithGoogle, (v) => setState(() => _googleLoading = v));

  Future<void> _continueAsGuest() async {
    String? captchaToken;
    if ((Env.turnstileSiteKey ?? '').isNotEmpty) {
      captchaToken = await showTurnstileDialog(context);
      if (captchaToken == null) return; // cancelled or challenge failed
    }
    await _run(
      () => AuthService.instance.signInAsGuest(captchaToken: captchaToken),
      (v) => setState(() => _guestLoading = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: PTResponsive(
          desktop: (_) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: GlassPanel(
                radius: 28,
                opacity: 0.5,
                blur: 32,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    const _Brand(),
                    const SizedBox(height: 34),
                    _actions(),
                    const SizedBox(height: 26),
                    const _TermsNote(),
                  ],
                ),
              ),
            ),
          ),
          landscape: (_) => SafeArea(
            child: Row(
              children: [
                const Expanded(child: Center(child: _Brand())),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          _actions(),
                          const SizedBox(height: 14),
                          const _TermsNote(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          portrait: (_) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  const _Brand(large: true),
                  const Spacer(),
                  _actions(buttonHeight: 54),
                  const SizedBox(height: 16),
                  const _TermsNote(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions({double buttonHeight = 52}) {
    return Column(
      mainAxisSize: .min,
      children: [
        GoogleButton(
          label: 'Continue with Google',
          loading: _googleLoading,
          onPressed: _googleLoading || _guestLoading ? null : _signInWithGoogle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            spacing: 14,
            children: [
              Expanded(child: Container(height: 1, color: PTColors.white(0.12))),
              Text('or', style: PTText.finePrint),
              Expanded(child: Container(height: 1, color: PTColors.white(0.12))),
            ],
          ),
        ),
        PTButton(
          label: 'Continue as guest',
          icon: Symbols.person_rounded,
          variant: .secondary,
          height: buttonHeight,
          loading: _guestLoading,
          onPressed: _googleLoading || _guestLoading ? null : _continueAsGuest,
        ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.large = false});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final logoSize = large ? 84.0 : 72.0;
    return Column(
      mainAxisSize: .min,
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            gradient: PTColors.brandGradient,
            borderRadius: BorderRadius.circular(logoSize * 0.3),
            boxShadow: [
              BoxShadow(
                color: PTColors.primary.withValues(alpha: 0.45),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(Icons.play_arrow_rounded, size: logoSize * 0.53, color: Colors.white),
        ),
        SizedBox(height: large ? 26 : 22),
        Text(
          'PlayTogether',
          style: PTText.display.copyWith(fontSize: large ? 32 : 30),
        ),
        const SizedBox(height: 8),
        Text(
          'Movie nights with your people,\nperfectly in sync.',
          textAlign: .center,
          style: PTText.body.copyWith(color: PTColors.white(0.6)),
        ),
      ],
    );
  }
}

class _TermsNote extends StatelessWidget {
  const _TermsNote();

  @override
  Widget build(BuildContext context) {
    final linkStyle = PTText.finePrint.copyWith(color: const Color(0xFFB79CFF));
    return Text.rich(
      TextSpan(
        text: 'By continuing you agree to our ',
        style: PTText.finePrint,
        children: [
          TextSpan(text: 'Terms', style: linkStyle, recognizer: TapGestureRecognizer()),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy policy', style: linkStyle, recognizer: TapGestureRecognizer()),
        ],
      ),
      textAlign: .center,
    );
  }
}
