import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/auth/auth_service.dart';
import 'package:synctogether/diagnostics.dart';
import 'package:synctogether/profile/entitlement_service.dart';
import 'package:synctogether/profile/profile_models.dart';
import 'package:synctogether/profile/profile_service.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/glass.dart';
import 'package:synctogether/ui/pt_theme.dart';

Future<void> showMediaQuotaDialog(BuildContext context) async {
  await showGlassDialog(
    context: context,
    width: 440,
    builder: (dialogContext) => const MediaQuotaDialogBody(),
  );
}

class MediaQuotaDialogBody extends StatelessWidget {
  const MediaQuotaDialogBody({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = ProfileService.instance.profile;
    final limits = EntitlementService.instance.limitsOrFallback;
    final isPrem = EntitlementService.instance.isPremium;
    final isGuest = profile?.isGuest ?? true;

    final weeklyLimit = limits.mediaSharingWeeklyBytes;
    final usedBytes = profile?.r2UploadBytes7d ?? 0;
    final remainingBytes = profile?.remainingWeeklyBytes(weeklyLimit) ?? weeklyLimit;
    final fractionUsed = weeklyLimit > 0 ? (usedBytes / weeklyLimit).clamp(0.0, 1.0) : 0.0;
    final resetDuration = profile?.timeUntilQuotaReset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        // Header
        Row(
          spacing: 12,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isPrem ? PTColors.primary.withValues(alpha: 0.25) : PTColors.white(0.08),
                border: Border.all(
                  color: isPrem
                      ? const Color(0xFFA78BFA).withValues(alpha: 0.5)
                      : PTColors.white(0.12),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isPrem ? Symbols.crown_rounded : Symbols.cloud_queue_rounded,
                size: 24,
                fill: 1,
                color: isPrem ? PTColors.textAccent : Colors.white,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Media Sharing Quota', style: PTText.cardHeading),
                  Text(
                    isPrem
                        ? 'Unlimited with Premium'
                        : isGuest
                        ? 'Sign in to unlock weekly quota'
                        : '${Profile.formatBytes(remainingBytes)} of ${Profile.formatBytes(weeklyLimit)} remaining',
                    style: PTText.caption.copyWith(
                      fontSize: 12,
                      color: isPrem
                          ? PTColors.textAccent
                          : remainingBytes < 1024 * 1024 * 1024 && !isGuest
                          ? PTColors.warning
                          : PTColors.white(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Live Meter Card
        if (isPrem)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  PTColors.primary.withValues(alpha: 0.15),
                  PTColors.gradientEnd.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PTColors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              spacing: 10,
              children: [
                const Icon(Symbols.verified_rounded, color: PTColors.textAccent, size: 20),
                Expanded(
                  child: Text(
                    'No upload limits! Share videos up to 10.0 GB each with high-speed priority.',
                    style: PTText.body.copyWith(fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else if (!isGuest)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PTColors.glass(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PTColors.white(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('7-Day Rolling Usage', style: PTText.caption.copyWith(fontSize: 12)),
                    Text(
                      '${Profile.formatBytes(usedBytes)} / ${Profile.formatBytes(weeklyLimit)}',
                      style: PTText.mono.copyWith(fontSize: 12, color: PTColors.textAccent),
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
                    minHeight: 6,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${Profile.formatBytes(remainingBytes)} available',
                      style: PTText.caption.copyWith(
                        fontSize: 11,
                        color: PTColors.online,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (resetDuration != null && resetDuration.inHours > 0)
                      Text(
                        'Recharges in ${_formatReset(resetDuration)}',
                        style: PTText.caption.copyWith(fontSize: 11, color: PTColors.white(0.5)),
                      ),
                  ],
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PTColors.glass(0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PTColors.white(0.08)),
            ),
            child: Text(
              'Sign in to get a free 2.5 GB rolling weekly quota to stream any video file with your room.',
              style: PTText.body.copyWith(fontSize: 12, color: PTColors.white(0.75)),
            ),
          ),

        // Tier Breakdown / Comparison
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: PTColors.glass(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PTColors.white(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(
                'How Quotas Work',
                style: PTText.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              _FeatureRow(
                icon: Symbols.schedule_rounded,
                title: 'Rolling 7-Day Window',
                description:
                    'Uploaded bytes automatically clear 7 days after the upload completed.',
              ),
              _FeatureRow(
                icon: Symbols.person_rounded,
                title: 'Free Plan (\$0/mo)',
                description:
                    '2.5 GB weekly quota • Up to 2.0 GB single file • Room duration up to 4 hrs.',
              ),
              _FeatureRow(
                icon: Symbols.workspace_premium_rounded,
                title: 'Premium Plan',
                description:
                    'Unlimited weekly uploads • Up to 10.0 GB single file • 24h rooms & facecams.',
                highlight: true,
              ),
            ],
          ),
        ),

        // Action Buttons
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: isGuest
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 10,
                  children: [
                    GoogleButton(
                      label: 'Sign in with Google (Free 2.5 GB)',
                      onPressed: () async {
                        Navigator.of(context).pop();
                        try {
                          await AuthService.instance.linkGoogleIdentity();
                        } catch (e, s) {
                          reportNonFatal(e, s, during: 'linking Google identity from media quota dialog');
                        }
                      },
                    ),
                    Row(
                      spacing: 10,
                      children: [
                        Expanded(
                          child: PTButton(
                            label: 'Go Premium (Unlimited)',
                            icon: Symbols.crown_rounded,
                            variant: .secondary,
                            onPressed: () {
                              Navigator.of(context).pop();
                              context.push('/lobby/subscribe?source=quota_dialog');
                            },
                          ),
                        ),
                        PTButton(
                          label: 'Got it',
                          variant: .secondary,
                          expand: false,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  spacing: 10,
                  children: [
                    if (!isPrem) ...[
                      Expanded(
                        child: PTButton(
                          label: 'Get Unlimited with Premium',
                          icon: Symbols.crown_rounded,
                          onPressed: () {
                            Navigator.of(context).pop();
                            context.push('/lobby/subscribe?source=quota_dialog');
                          },
                        ),
                      ),
                      PTButton(
                        label: 'Got it',
                        variant: .secondary,
                        expand: false,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ] else
                      Expanded(
                        child: PTButton(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static String _formatReset(Duration d) {
    if (d.inDays > 0) {
      final days = d.inDays;
      final hours = d.inHours % 24;
      return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    }
    if (d.inHours > 0) {
      return '${d.inHours}h';
    }
    return '${d.inMinutes}m';
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Icon(icon, size: 16, color: highlight ? PTColors.textAccent : PTColors.white(0.5)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: PTText.caption.copyWith(fontSize: 11, color: PTColors.white(0.7)),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: highlight ? PTColors.textAccent : Colors.white,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
