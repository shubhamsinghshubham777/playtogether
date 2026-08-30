import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/analytics.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/profile/entitlement_service.dart';
import 'package:playtogether/profile/profile_service.dart';
import 'package:playtogether/ui/banners.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/loader.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';
import 'package:url_launcher/url_launcher.dart';

String get checkoutUrl =>
    kDebugMode ? 'http://localhost:3000/premium' : 'https://playtogether.app/premium';

String get accountUrl =>
    kDebugMode ? 'http://localhost:3000/account' : 'https://playtogether.app/account';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key, this.source, this.desktopOverride});

  final String? source;
  final bool? desktopOverride;

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> with WidgetsBindingObserver {
  bool _awaitingCheckout = false;
  bool _verifying = false;
  bool _celebrating = false;

  bool get _isDesktop => widget.desktopOverride ?? isDesktop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.instance.track('subscription_screen_viewed', {'source': widget.source ?? 'direct'});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingCheckout && !_verifying && !_celebrating) {
      _pollForSubscription();
    }
  }

  Future<void> _openCheckout() async {
    Analytics.instance.track('checkout_opened', {'source': widget.source ?? 'direct'});
    setState(() => _awaitingCheckout = true);
    final uri = Uri.parse(checkoutUrl);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit playtogether.app/premium");
      }
    } catch (e, s) {
      reportNonFatal(e, s, during: 'launching checkout url');
      if (mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit playtogether.app/premium");
      }
    }
  }

  Future<void> _openAccount() async {
    final uri = Uri.parse(accountUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e, s) {
      reportNonFatal(e, s, during: 'launching account url');
      if (mounted) {
        showPTSnack(context, "Couldn't open browser. Please visit playtogether.app/account");
      }
    }
  }

  Future<void> _pollForSubscription() async {
    setState(() => _verifying = true);
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (!mounted) return;
      try {
        final updated = await EntitlementService.instance.refresh();
        if (updated?.isPremium == true) {
          if (mounted) {
            setState(() {
              _verifying = false;
              _awaitingCheckout = false;
              _celebrating = true;
            });
            Analytics.instance.track('purchase_confirmed');
          }
          return;
        }
      } catch (e, s) {
        reportNonFatal(e, s, during: 'polling subscription status');
      }
      if (attempt < 3) {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    if (mounted) {
      setState(() {
        _verifying = false;
        _awaitingCheckout = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([ProfileService.instance, EntitlementService.instance]),
          builder: (context, _) {
            return PTResponsive(
              desktop: (_) => _layout(compact: false),
              portrait: (_) => _layout(compact: true),
              landscape: (_) => _layout(compact: true),
            );
          },
        ),
      ),
    );
  }

  Widget _layout({required bool compact}) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 48, vertical: compact ? 12 : 28),
          child: _backHeader(compact: compact),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: compact ? 16 : 32,
              right: compact ? 16 : 32,
              top: compact ? 10 : 20,
              bottom: 48,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: GlassPanel(
                  radius: compact ? 22 : 28,
                  opacity: 0.5,
                  blur: 32,
                  padding: EdgeInsets.all(compact ? 24 : 40),
                  child: _celebrating ? _celebrationBody() : _mainBody(compact: compact),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _backHeader({required bool compact}) {
    return Row(
      spacing: 14,
      children: [
        PTIconButton(
          icon: Symbols.arrow_back_rounded,
          iconSize: compact ? 18 : 20,
          size: compact ? 38 : 42,
          onPressed: () => context.canPop() ? context.pop() : context.go('/lobby'),
        ),
        Text(
          'PlayTogether Premium',
          style: compact ? PTText.cardHeading.copyWith(fontSize: 18) : PTText.cardHeading,
        ),
      ],
    );
  }

  Widget _celebrationBody() {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .center,
      spacing: 20,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: PTColors.brandGradient,
            shape: .circle,
            boxShadow: [
              BoxShadow(
                color: PTColors.primary.withValues(alpha: 0.5),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Symbols.crown_rounded, size: 36, fill: 1, color: Colors.white),
        ),
        Text('Welcome to Premium! 🎉', style: PTText.screenTitle.copyWith(fontSize: 24)),
        Text(
          'Your account is now upgraded with all premium perks. '
          'Enjoy longer sessions, video facecams, and persistent rooms!',
          textAlign: TextAlign.center,
          style: PTText.body.copyWith(color: PTColors.white(0.7), height: 1.5),
        ),
        const SizedBox(height: 8),
        PTButton(
          label: 'Back to lobby',
          icon: Symbols.home_rounded,
          onPressed: () => context.go('/lobby'),
        ),
      ],
    );
  }

  Widget _mainBody({required bool compact}) {
    final isPrem = EntitlementService.instance.isPremium;

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 24,
      children: [
        _tierBadgeHeader(isPremium: isPrem),
        _featureList(),
        if (_verifying)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PTColors.primary.withValues(alpha: 0.12),
              border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: .center,
              spacing: 12,
              children: [
                const PTLoader(size: 20),
                Text(
                  'Verifying your purchase…',
                  style: PTText.body.copyWith(color: PTColors.textAccent),
                ),
              ],
            ),
          )
        else if (isPrem)
          _premiumStatusActions(compact: compact)
        else
          _purchaseActions(compact: compact),
      ],
    );
  }

  Widget _tierBadgeHeader({required bool isPremium}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isPremium ? PTColors.primary.withValues(alpha: 0.15) : PTColors.white(0.04),
        border: Border.all(
          color: isPremium ? const Color(0xFFA78BFA).withValues(alpha: 0.4) : PTColors.white(0.1),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: isPremium ? PTColors.brandGradient : null,
              color: isPremium ? null : PTColors.white(0.08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isPremium ? Symbols.crown_rounded : Symbols.person_rounded,
              size: 22,
              fill: 1,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  isPremium ? 'Premium Active' : 'Free Plan',
                  style: PTText.cardHeading.copyWith(fontSize: 16),
                ),
                Text(
                  isPremium
                      ? 'All perks unlocked on your account'
                      : 'Upgrade to host larger rooms with video facecams',
                  style: PTText.caption.copyWith(color: PTColors.white(0.55)),
                ),
              ],
            ),
          ),
          if (isPremium) const PremiumBadge(),
        ],
      ),
    );
  }

  Widget _featureList() {
    const perks = [
      ('Up to 20 rooms active at once', Symbols.meeting_room_rounded),
      ('Persistent rooms that stay saved forever', Symbols.save_rounded),
      ('Up to 16 watchers per room', Symbols.groups_rounded),
      ('HD video facecams & crystal-clear voice', Symbols.videocam_rounded),
      ('Extended animated emoji reactions', Symbols.add_reaction_rounded),
      ('Watch party sessions up to 24 hours', Symbols.schedule_rounded),
    ];

    return Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Text(
          'Premium perks',
          style: PTText.caption.copyWith(fontWeight: .w600, letterSpacing: 0.5),
        ),
        for (final perk in perks)
          Row(
            spacing: 12,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: PTColors.primary.withValues(alpha: 0.15),
                  shape: .circle,
                ),
                child: Icon(perk.$2, size: 17, fill: 1, color: PTColors.textAccent),
              ),
              Expanded(
                child: Text(
                  perk.$1,
                  style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.85)),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _purchaseActions({required bool compact}) {
    if (_isDesktop) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          PTButton(
            label: 'Go Premium',
            icon: Symbols.workspace_premium_rounded,
            height: 48,
            onPressed: _openCheckout,
          ),
          Text(
            "You'll be taken to our website to complete your purchase.",
            textAlign: TextAlign.center,
            style: PTText.finePrint.copyWith(color: PTColors.white(0.4)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        spacing: 12,
        children: [
          const Icon(Symbols.info_rounded, size: 20, color: PTColors.textAccent),
          Expanded(
            child: Text(
              'Subscriptions are managed on our website.',
              style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.75)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumStatusActions({required bool compact}) {
    if (_isDesktop) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          PTButton(
            label: 'Manage subscription',
            icon: Symbols.open_in_new_rounded,
            variant: .secondary,
            height: 48,
            onPressed: _openAccount,
          ),
          Text(
            'Opens account settings in your browser.',
            textAlign: TextAlign.center,
            style: PTText.finePrint.copyWith(color: PTColors.white(0.4)),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'Subscriptions are managed on our website.',
        textAlign: TextAlign.center,
        style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.75)),
      ),
    );
  }
}
