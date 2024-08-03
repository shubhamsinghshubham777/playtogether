import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/view/dashboard_screen.dart';
import 'package:playtogether/utils.dart';
import 'package:window_manager/window_manager.dart';

class AuthScreen extends ConsumerWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userNotifier = ref.watch(currentUserIdProvider.notifier);

    ref.listen(currentUserIdProvider, (_, newState) {
      if (newState.valueOrNull != null) {
        if (isDesktop) windowManager.show();
        context.pushReplacement(const DashboardScreen());
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: context.width,
                height: context.mqViewPadding.top + 24,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'PlayTogether',
                  style: context.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Text(
                  'Enjoy media with your friends and family',
                  style: context.titleSmall?.copyWith(letterSpacing: 1),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child:
                    Image.asset(Assets.imageAppLogo, width: context.width * 0.6)
                        .animate(delay: Durations.long2)
                        .rotate(
                          duration: _logoAnimationDuration,
                          curve: _logoAnimationCurve,
                        )
                        .scale(
                          duration: _logoAnimationDuration,
                          curve: _logoAnimationCurve,
                        )
                        .fade(
                          duration: _logoAnimationDuration,
                          curve: _logoAnimationCurve,
                        ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Please authenticate to enjoy the app',
                  style: context.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('Login with', style: context.titleSmall),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: IconButton.outlined(
                  onPressed: userNotifier.signInWithGoogle,
                  icon: Image.asset(Assets.iconGoogleLogo, width: 32),
                ),
              ),
              SizedBox(height: context.mqViewPadding.bottom + 24),
            ],
          ),
        ),
      ),
    );
  }
}

const _logoAnimationDuration = Duration(seconds: 3);
const _logoAnimationCurve = Curves.elasticOut;
