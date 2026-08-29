import 'dart:io';

import 'package:fast_file_picker/fast_file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/analytics_consent.dart';
import 'package:playtogether/auth/auth_service.dart';
import 'package:playtogether/diagnostics.dart';
import 'package:playtogether/profile/entitlement_service.dart';
import 'package:playtogether/profile/media_quota_dialog.dart';
import 'package:playtogether/profile/profile_models.dart';
import 'package:playtogether/profile/profile_service.dart';
import 'package:playtogether/ui/banners.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/inputs.dart';
import 'package:playtogether/ui/loader.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';
import 'package:playtogether/ui/responsive.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    if (ProfileService.instance.profile == null) {
      ProfileService.instance.load();
    }
    EntitlementService.instance.load();
  }

  Future<void> _pickAvatar() async {
    const imageTypes = XTypeGroup(label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']);
    final picked = await FastFilePicker.pickFile(acceptedTypeGroups: [imageTypes]);
    final path = picked?.path;
    if (path == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      await ProfileService.instance.uploadAvatar(await File(path).readAsBytes());
    } catch (e, s) {
      // "Try a different image" is a guess. Storage quota, a bucket policy or a
      // dead connection all land here, and only the log can tell them apart.
      reportNonFatal(e, s, during: 'uploading an avatar');
      if (mounted) _snack("Couldn't update your photo — try a different image.");
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editDisplayName(Profile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final saved = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 16,
        children: [
          Text('Pick a display name', style: PTText.cardHeading),
          PTTextField(
            controller: controller,
            hint: 'Your name',
            autofocus: true,
            maxLength: 40,
            onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: 11,
            children: [
              PTButton(
                label: 'Cancel',
                variant: .secondary,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PTButton(
                label: 'Save',
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    if (saved == true && name.isNotEmpty && name != profile.displayName) {
      try {
        await ProfileService.instance.updateDisplayName(name);
      } catch (e, s) {
        reportNonFatal(e, s, during: 'saving the display name');
        if (mounted) _snack("Couldn't save that name — give it another try.");
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      width: 400,
      builder: (dialogContext) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: 14,
        children: [
          Text('Delete your account?', style: PTText.cardHeading),
          Text(
            'This wipes your profile, room memberships and chat for good. '
            'There is no undo.',
            style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.5),
          ),
          Row(
            mainAxisAlignment: .end,
            spacing: 11,
            children: [
              PTButton(
                label: 'Keep account',
                variant: .secondary,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              PTButton(
                label: 'Delete forever',
                variant: .destructive,
                icon: Symbols.delete_rounded,
                height: 46,
                expand: false,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await AuthService.instance.deleteAccount();
      } catch (e, s) {
        // Account deletion has known server-side failure modes (a hosted room
        // still referencing the user), so the cause is worth keeping.
        reportNonFatal(e, s, during: 'deleting the account');
        if (mounted) _snack("Couldn't delete the account right now — try again in a bit.");
      }
    }
  }

  void _snack(String message, {PTSnackKind kind = PTSnackKind.error}) =>
      showPTSnack(context, message, kind: kind);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: ListenableBuilder(
          listenable: Listenable.merge([ProfileService.instance, EntitlementService.instance]),
          builder: (context, _) {
            final profile = ProfileService.instance.profile;
            if (profile == null) {
              return const Center(child: PTLoader(size: 32));
            }
            return PTResponsive(
              desktop: (_) => _desktop(profile),
              portrait: (_) => _portrait(profile),
              landscape: (_) => _landscape(profile),
            );
          },
        ),
      ),
    );
  }

  Widget _desktop(Profile profile) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
          child: _backHeader(size: 42),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 36, bottom: 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: GlassPanel(
                  radius: 28,
                  opacity: 0.5,
                  blur: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 44),
                  child: profile.isGuest
                      ? _guestBody(profile)
                      : _accountBody(profile, header: .row),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _portrait(Profile profile) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: _backHeader(titleSize: 18),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 40),
              child: profile.isGuest ? _guestBody(profile) : _accountBody(profile, header: .column),
            ),
          ),
        ],
      ),
    );
  }

  Widget _landscape(Profile profile) {
    return SafeArea(
      minimum: const EdgeInsets.symmetric(horizontal: 44),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _backHeader(iconSize: 19, size: 38, titleSize: 17),
          ),
          Expanded(
            child: profile.isGuest
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    child: _guestBody(profile),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                    child: Row(
                      spacing: 36,
                      children: [
                        SizedBox(width: 240, child: _identityHeader(profile, vertical: true)),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: .center,
                              spacing: 12,
                              children: [
                                _nameField(profile),
                                _emailField(profile),
                                _subscriptionSection(),
                                _mediaQuotaSection(),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    spacing: 11,
                                    children: [
                                      Expanded(
                                        child: PTButton(
                                          label: 'Log out',
                                          icon: Symbols.logout_rounded,
                                          variant: .secondary,
                                          height: 46,
                                          onPressed: AuthService.instance.signOut,
                                        ),
                                      ),
                                      Expanded(
                                        child: PTButton(
                                          label: 'Delete account',
                                          icon: Symbols.delete_rounded,
                                          variant: .destructive,
                                          height: 46,
                                          onPressed: _confirmDeleteAccount,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionSection() {
    final isPrem = EntitlementService.instance.isPremium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isPrem ? PTColors.primary.withValues(alpha: 0.12) : PTColors.white(0.04),
        border: Border.all(
          color: isPrem
              ? const Color(0xFFA78BFA).withValues(alpha: 0.35)
              : PTColors.white(0.08),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: isPrem ? PTColors.brandGradient : null,
              color: isPrem ? null : PTColors.white(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPrem ? Symbols.crown_rounded : Symbols.workspace_premium_rounded,
              size: 20,
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
                  isPrem ? 'Premium Plan' : 'Free Tier',
                  style: PTText.body.copyWith(fontWeight: .w600, color: Colors.white),
                ),
                Text(
                  isPrem
                      ? 'Video facecams, 24h rooms & more'
                      : 'Upgrade for video facecams & persistent rooms',
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.55)),
                ),
              ],
            ),
          ),
          PTButton(
            label: isPrem ? 'Manage' : 'Go Premium',
            variant: isPrem ? .secondary : .primary,
            icon: isPrem ? Symbols.arrow_forward_rounded : Symbols.crown_rounded,
            height: 38,
            expand: false,
            onPressed: () => context.go('/lobby/subscribe?source=profile'),
          ),
        ],
      ),
    );
  }

  Widget _privacySection() {
    return ListenableBuilder(
      listenable: AnalyticsConsent.instance,
      builder: (context, _) => PTToggleRow(
        icon: Symbols.insights_rounded,
        title: 'Share usage data',
        subtitle:
            'Anonymous counts of things like rooms created and features used, so we know '
            'what to build next. Never your chats, file names or links.',
        value: !AnalyticsConsent.instance.optedOut,
        onChanged: (shareData) => AnalyticsConsent.instance.setOptedOut(!shareData),
      ),
    );
  }

  Widget _backHeader({double iconSize = 20, double size = 44, double? titleSize}) {
    return Row(
      spacing: 14,
      children: [
        PTIconButton(
          icon: Symbols.arrow_back_rounded,
          iconSize: iconSize,
          size: size,
          onPressed: () => context.go('/lobby'),
        ),
        Text(
          'Profile',
          style: titleSize == null
              ? PTText.cardHeading
              : PTText.cardHeading.copyWith(fontSize: titleSize),
        ),
      ],
    );
  }

  Widget _mediaQuotaSection() {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;

    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final usedBytes = profile?.r2UploadBytes7d ?? 0;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final fractionUsed = weeklyLimit > 0 ? (usedBytes / weeklyLimit).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: PTColors.white(0.04),
        border: Border.all(color: PTColors.white(0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            children: [
              const Icon(Symbols.cloud_queue_rounded, size: 20, color: PTColors.textAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Media Sharing Bandwidth',
                  style: PTText.body.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              GestureDetector(
                onTap: () => showMediaQuotaDialog(context),
                child: Text(
                  'Details',
                  style: PTText.caption.copyWith(
                    color: PTColors.textAccent,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (isPrem)
            Text(
              'Unlimited weekly uploads active with your Premium subscription.',
              style: PTText.finePrint.copyWith(color: PTColors.white(0.6)),
            )
          else if (!isGuest) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Profile.formatBytes(remainingBytes)} available of ${Profile.formatBytes(weeklyLimit)}',
                  style: PTText.finePrint.copyWith(color: PTColors.white(0.6)),
                ),
                Text(
                  '${Profile.formatBytes(usedBytes)} used',
                  style: PTText.mono.copyWith(color: PTColors.textAccent, fontSize: 11),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fractionUsed,
                backgroundColor: PTColors.white(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  fractionUsed > 0.85 ? PTColors.warning : PTColors.textAccent,
                ),
                minHeight: 4,
              ),
            ),
          ] else
            Text(
              'Sign in for a free 2.5 GB weekly streaming quota.',
              style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
            ),
        ],
      ),
    );
  }

  Widget _accountBody(Profile profile, {required _HeaderStyle header}) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 24,
      children: [
        _identityHeader(profile, vertical: header == .column),
        _subscriptionSection(),
        _mediaQuotaSection(),
        _nameField(profile),
        _emailField(profile),
        const Divider(),
        _privacySection(),
        const Divider(),
        Column(
          spacing: 12,
          children: [
            PTButton(
              label: 'Log out',
              icon: Symbols.logout_rounded,
              variant: .secondary,
              onPressed: AuthService.instance.signOut,
            ),
            PTButton(
              label: 'Delete account',
              icon: Symbols.delete_rounded,
              variant: .destructive,
              onPressed: _confirmDeleteAccount,
            ),
          ],
        ),
      ],
    );
  }

  Widget _guestBody(Profile profile) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 22,
      children: [
        Column(
          spacing: 14,
          children: [
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: PTColors.white(0.08),
                shape: .circle,
                border: Border.all(
                  color: PTColors.white(0.2),
                  width: 2,
                  strokeAlign: BorderSide.strokeAlignOutside,
                ),
              ),
              child: Icon(Symbols.person_rounded, size: 44, fill: 1, color: PTColors.white(0.4)),
            ),
            Column(
              spacing: 8,
              children: [
                Text(profile.displayName, style: PTText.screenTitle.copyWith(fontSize: 23)),
                const GuestBadge(),
              ],
            ),
          ],
        ),
        Opacity(
          opacity: 0.45,
          child: IgnorePointer(
            child: PTTextField(
              controller: TextEditingController(text: profile.displayName),
              label: 'Display name',
              enabled: false,
              suffixIcon: Icon(Symbols.lock_rounded, size: 17, fill: 1, color: PTColors.white(0.6)),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: PTColors.primary.withValues(alpha: 0.12),
            border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: .start,
            spacing: 14,
            children: [
              Row(
                spacing: 12,
                children: [
                  const Icon(
                    Symbols.auto_awesome_rounded,
                    size: 24,
                    fill: 1,
                    color: PTColors.textAccent,
                  ),
                  Text('Keep your identity', style: PTText.cardHeading.copyWith(fontSize: 16)),
                ],
              ),
              Text(
                'Sign in with Google to pick a name and photo, and keep them across '
                'devices. Your current session carries over.',
                style: PTText.body.copyWith(
                  fontSize: 13.5,
                  color: PTColors.white(0.65),
                  height: 1.5,
                ),
              ),
              GoogleButton(
                label: 'Sign in with Google',
                onPressed: () async {
                  try {
                    await AuthService.instance.linkGoogleIdentity();
                  } catch (e, s) {
                    reportNonFatal(e, s, during: 'linking a Google identity to a guest');
                    if (mounted) _snack("Couldn't start Google sign-in — try again.");
                  }
                },
              ),
            ],
          ),
        ),
        _subscriptionSection(),
        _mediaQuotaSection(),
        const Divider(),
        _privacySection(),
        PTButton(
          label: 'End guest session',
          icon: Symbols.logout_rounded,
          variant: .secondary,
          onPressed: AuthService.instance.signOut,
        ),
      ],
    );
  }

  Widget _identityHeader(Profile profile, {required bool vertical}) {
    final since = profile.createdAt;
    final sinceLabel = since != null
        ? 'Watching together since ${_monthName(since.month)} ${since.year}'
        : 'Watching together';

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        // A fresh photo scale-pulses itself in — confirmation the user is
        // already looking at, so no snackbar is needed for the happy path.
        PTEntrance(
          key: ValueKey(profile.avatarUrl),
          offset: 0,
          scaleFrom: 0.9,
          fade: false,
          duration: PTMotion.state,
          child: PTAvatar(
            userId: profile.id,
            displayName: profile.displayName,
            avatarUrl: profile.avatarUrl,
            size: 96,
            ringColor: PTColors.white(0.15),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _uploadingAvatar ? 1 : 0,
              duration: PTMotion.functional(context, PTMotion.state),
              child: const DecoratedBox(
                decoration: BoxDecoration(color: Color(0x99080710), shape: .circle),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: PTPressable(
              onTap: _uploadingAvatar ? null : _pickAvatar,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xF21E1834),
                  shape: .circle,
                  border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.5)),
                ),
                child: AnimatedSwitcher(
                  duration: PTMotion.functional(context, PTMotion.state),
                  switchInCurve: PTMotion.enter,
                  switchOutCurve: PTMotion.exit,
                  child: _uploadingAvatar
                      ? const PTLoader(
                          key: ValueKey('uploading'),
                          size: 18,
                          color: PTColors.textAccent,
                        )
                      : const Icon(
                          Symbols.photo_camera_rounded,
                          key: ValueKey('idle'),
                          size: 17,
                          fill: 1,
                          color: PTColors.textAccent,
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final text = Column(
      crossAxisAlignment: vertical ? .center : .start,
      spacing: 4,
      children: [
        Row(
          mainAxisSize: .min,
          mainAxisAlignment: vertical ? .center : .start,
          spacing: 10,
          children: [
            Flexible(
              child: AnimatedSwitcher(
                duration: PTMotion.functional(context, PTMotion.state),
                switchInCurve: PTMotion.enter,
                switchOutCurve: PTMotion.exit,
                child: Text(
                  profile.displayName,
                  key: ValueKey(profile.displayName),
                  overflow: .ellipsis,
                  style: PTText.screenTitle,
                ),
              ),
            ),
            if (EntitlementService.instance.isPremium) const PremiumBadge(),
          ],
        ),
        Text(sinceLabel, style: PTText.caption.copyWith(fontWeight: .w400)),
      ],
    );

    if (vertical) {
      return Center(child: Column(spacing: 14, children: [avatar, text]));
    }
    return Row(
      spacing: 24,
      children: [
        avatar,
        Expanded(child: text),
      ],
    );
  }

  Widget _nameField(Profile profile) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: .opaque,
        onTap: () => _editDisplayName(profile),
        child: IgnorePointer(
          child: PTTextField(
            key: ValueKey('name-${profile.displayName}'),
            controller: TextEditingController(text: profile.displayName),
            label: 'Display name',
            enabled: false,
            suffixIcon: Icon(Symbols.edit_rounded, size: 18, color: PTColors.white(0.4)),
          ),
        ),
      ),
    );
  }

  Widget _emailField(Profile profile) {
    return Column(
      crossAxisAlignment: .start,
      spacing: 8,
      children: [
        Text('Email', style: PTText.caption),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: PTColors.white(0.03),
            border: Border.all(color: PTColors.white(0.07)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  profile.email ?? '—',
                  style: PTText.body.copyWith(color: PTColors.white(0.5)),
                ),
              ),
              Icon(Symbols.lock_rounded, size: 17, fill: 1, color: PTColors.white(0.35)),
            ],
          ),
        ),
        Text(
          "Linked to your Google account — can't be changed.",
          style: PTText.finePrint.copyWith(color: PTColors.white(0.35)),
        ),
      ],
    );
  }

  String _monthName(int month) => const [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][month - 1];
}

enum _HeaderStyle { row, column }
