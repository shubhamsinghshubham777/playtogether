import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/auth/turnstile_dialog.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/env.dart';
import 'package:synctogether/ui/banners.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_motion.dart';
import 'package:synctogether/ui/pt_theme.dart';
import 'package:synctogether/ui/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleLoading = false;
  bool _guestLoading = false;

  Future<void> _run(
    Future<void> Function() action,
    void Function(bool) setLoading, {
    required String during,
  }) async {
    setLoading(true);
    try {
      await action();
      // Navigation happens via the router's auth redirect.
    } catch (e, s) {
      // The user gets one friendly line no matter what went wrong, so without
      // this the actual cause — a rejected captcha token, a 4xx from GoTrue —
      // never leaves the device.
      reportNonFatal(e, s, during: during);
      if (mounted) {
        showPTSnack(context, "Couldn't sign you in — give it another try.", kind: .error);
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  void _signInWithGoogle() => _run(
    AuthService.instance.signInWithGoogle,
    (v) => setState(() => _googleLoading = v),
    during: 'signing in with Google',
  );

  Future<void> _continueAsGuest() async {
    String? captchaToken;
    final captchaRequired = (Env.turnstileSiteKey ?? '').isNotEmpty;
    trace('guest sign-in started', category: 'auth', data: {'captcha': captchaRequired});
    if (captchaRequired) {
      captchaToken = await showTurnstileDialog(context);
      // Cancelled or failed. The dialog has already reported *why*; this only
      // records that we never got as far as the sign-in call, which is what
      // distinguishes a captcha problem from a Supabase one.
      if (captchaToken == null) {
        trace('guest sign-in abandoned: no captcha token', category: 'auth');
        return;
      }
      trace('captcha token acquired', category: 'auth');
    }
    await _run(
      () => AuthService.instance.signInAsGuest(captchaToken: captchaToken),
      (v) => setState(() => _guestLoading = v),
      during: 'signing in as a guest',
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
                    const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
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
                          const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
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
                  const PTEntrance(delay: Duration(milliseconds: 240), child: _TermsNote()),
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
    // Staggered after the brand. The glass card around this is deliberately
    // *not* animated: fading a GlassPanel leaves its BackdropFilter sampling an
    // empty layer, and the route's own fade-through already covers its arrival.
    return PTEntrance(
      delay: const Duration(milliseconds: 180),
      child: Column(
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
      ),
    );
  }
}

class _Brand extends StatefulWidget {
  const _Brand({this.large = false});

  final bool large;

  @override
  State<_Brand> createState() => _BrandState();
}

class _BrandState extends State<_Brand> with SingleTickerProviderStateMixin {
  // The one breathing element on this screen — the lobby's is its greeting.
  // Isolated behind a RepaintBoundary so a looping shadow can't dirty the rest
  // of the card every frame.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reducedMotion(context)) {
      _breath.stop();
      _breath.value = 0;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoSize = widget.large ? 84.0 : 72.0;
    return Column(
      mainAxisSize: .min,
      children: [
        PTEntrance(
          scaleFrom: 0.9,
          offset: 0,
          duration: const Duration(milliseconds: 400),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _breath,
              builder: (context, child) => Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  gradient: PTColors.brandGradient,
                  borderRadius: BorderRadius.circular(logoSize * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: PTColors.primary.withValues(alpha: 0.45 + 0.1 * _breath.value),
                      blurRadius: 32 + 8 * _breath.value,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: child,
              ),
              child: Icon(Icons.play_arrow_rounded, size: logoSize * 0.53, color: Colors.white),
            ),
          ),
        ),
        SizedBox(height: widget.large ? 26 : 22),
        PTEntrance(
          delay: const Duration(milliseconds: 60),
          child: Text(
            'SyncTogether',
            style: PTText.display.copyWith(fontSize: widget.large ? 32 : 30),
          ),
        ),
        const SizedBox(height: 8),
        PTEntrance(
          delay: const Duration(milliseconds: 120),
          child: Text(
            'Movie nights with your people,\nperfectly in sync.',
            textAlign: .center,
            style: PTText.body.copyWith(color: PTColors.white(0.6)),
          ),
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
