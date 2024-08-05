import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/view/friends/friends_screen.dart';
import 'package:playtogether/utils.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserData = ref.watch(currentUserDataProvider).valueOrNull;
    final userNotifier = ref.watch(currentUserIdProvider.notifier);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: verticalSpace(
                  16,
                  [
                    SizedBox(
                      width: double.infinity,
                      child: Text(
                        'ACCOUNT',
                        style: context.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: SizedBox(
                            width: 132,
                            height: 132,
                            child: currentUserData?.photoURL != null
                                ? FadeInImage.assetNetwork(
                                    placeholder: Assets.imageTransparent,
                                    image: currentUserData!.photoURL!,
                                    imageErrorBuilder: (_, __, ___) {
                                      return networkImageErrorIcon;
                                    },
                                    fit: BoxFit.cover,
                                  )
                                : const ColoredBox(color: Colors.green),
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: _FormTitle(
                        title: 'NAME',
                        iconData: Icons.abc_outlined,
                      ),
                    ),
                    Text(
                      currentUserData?.name ?? '',
                      style: context.titleMedium,
                    ),
                    const _FormTitle(
                      title: 'EMAIL',
                      iconData: Icons.email_outlined,
                    ),
                    Text(
                      currentUserData?.email?.toUpperCase() ?? '',
                      style: context.titleMedium,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: FilledButton(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Confirm Sign Out'),
                              content: const Text(
                                'Are you sure you want to sign out?',
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () {
                                    dialogContext.pop<void>();
                                    userNotifier.signOut();
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: dialogContext
                                        .theme.colorScheme.errorContainer,
                                    foregroundColor: dialogContext
                                        .theme.colorScheme.onErrorContainer,
                                  ),
                                  child: const Text('Yes'),
                                ),
                                TextButton(
                                  onPressed: dialogContext.pop<void>,
                                  style: TextButton.styleFrom(
                                    foregroundColor: dialogContext
                                        .theme.colorScheme.onSurface,
                                  ),
                                  child: const Text('No'),
                                ),
                              ],
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                context.theme.colorScheme.errorContainer,
                            foregroundColor:
                                context.theme.colorScheme.onErrorContainer,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text('SIGN OUT'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormTitle extends StatelessWidget {
  const _FormTitle({required this.title, required this.iconData});

  final String title;
  final IconData iconData;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          iconData,
          size: 27,
          color: context.theme.colorScheme.primary,
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: context.titleLarge?.copyWith(
            color: context.theme.colorScheme.primary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
