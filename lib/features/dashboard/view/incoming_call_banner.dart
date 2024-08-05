import 'package:awesome_extensions/awesome_extensions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/assets.dart';
import 'package:playtogether/features/auth/model/pt_user.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/call/view/call_screen.dart';
import 'package:playtogether/features/dashboard/view/friends/friends_screen.dart';

class IncomingCallBanner extends ConsumerWidget {
  const IncomingCallBanner({
    super.key,
    required this.user,
    required this.data,
  });

  final PTUser user;
  final DocumentSnapshot<Object?>? data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: context.theme.colorScheme.primaryContainer,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              if (user.photoURL != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: FadeInImage.assetNetwork(
                      placeholder: Assets.imageTransparent,
                      image: user.photoURL!,
                      imageErrorBuilder: (_, __, ___) {
                        return networkImageErrorIcon;
                      },
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Call from ${user.name}',
                  style: context.bodyLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton.filled(
                onPressed: () async {
                  final currentUserId = await ref.read(
                    currentUserIdProvider.future,
                  );
                  if (currentUserId != null) {
                    CallScreen.deleteCallRelatedData(currentUserId);
                  }
                },
                icon: const Icon(Icons.call_end),
                style: IconButton.styleFrom(
                  backgroundColor: context.theme.colorScheme.errorContainer,
                  foregroundColor: context.theme.colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: () async {
                  final currentUserId = await ref.read(
                    currentUserIdProvider.future,
                  );
                  if (currentUserId != null && context.mounted) {
                    context.push(
                      CallScreen(
                        callerUid: user.uid,
                        calleeUid: currentUserId,
                        offer: data?['offer'],
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.call),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
