import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_theme.dart';

/// Anchored top-right glass menu: member list (presence + Host badge) and
/// room actions. `Room.dc.html` overflow-menu detail.
Future<void> showRoomOverflowMenu({
  required BuildContext context,
  required List<RoomMember> members,
  required Set<String> onlineIds,
  required String selfId,
  required bool selfIsHost,
  required VoidCallback onCopyInvite,
  required VoidCallback onLeave,
  required VoidCallback onEndRoom,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'room menu',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, _, _) {
      return SafeArea(
        child: Align(
          alignment: .topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 76, right: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 520),
              child: Material(
                type: .transparency,
                child: GlassPanel(
                  radius: 20,
                  opacity: 0.68,
                  blur: 32,
                  baseColor: const Color(0xFF141022),
                  borderColor: PTColors.white(0.14),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                          child: Text(
                            'IN THE ROOM · ${members.length} OF 8',
                            style: TextStyle(
                              fontFamily: PTFonts.body,
                              fontSize: 12,
                              fontWeight: .w600,
                              letterSpacing: 0.96,
                              color: PTColors.white(0.45),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              for (final member in members)
                                _MemberRow(
                                  member: member,
                                  online: onlineIds.contains(member.userId),
                                  isSelf: member.userId == selfId,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Container(height: 1, color: PTColors.white(0.09)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Column(
                            children: [
                              _ActionRow(
                                icon: Symbols.link_rounded,
                                iconColor: PTColors.textAccent,
                                label: 'Copy invite link',
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onCopyInvite();
                                },
                              ),
                              _ActionRow(
                                icon: Symbols.logout_rounded,
                                iconColor: PTColors.white(0.7),
                                label: 'Leave room',
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  onLeave();
                                },
                              ),
                              if (selfIsHost)
                                _ActionRow(
                                  icon: Symbols.power_settings_new_rounded,
                                  iconColor: PTColors.danger,
                                  label: 'End room for everyone',
                                  labelColor: PTColors.danger,
                                  onTap: () {
                                    Navigator.of(dialogContext).pop();
                                    onEndRoom();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.online, required this.isSelf});

  final RoomMember member;
  final bool online;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: online ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          spacing: 12,
          children: [
            PTAvatar(
              userId: member.userId,
              displayName: member.displayName,
              avatarUrl: member.profile?.avatarUrl,
              size: 34,
              presence: online,
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: member.displayName,
                  children: [
                    if (isSelf)
                      TextSpan(
                        text: ' (you)',
                        style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                      )
                    else if (!online)
                      TextSpan(
                        text: ' · away',
                        style: TextStyle(fontWeight: .w400, color: PTColors.white(0.45)),
                      ),
                  ],
                ),
                overflow: .ellipsis,
                style: PTText.body.copyWith(fontSize: 14, fontWeight: .w500),
              ),
            ),
            if (member.isHost) const HostBadge(),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: _hovered
                ? (widget.labelColor == PTColors.danger
                      ? PTColors.dangerBorder.withValues(alpha: 0.1)
                      : PTColors.white(0.06))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            spacing: 12,
            children: [
              Icon(widget.icon, size: 19, fill: 1, color: widget.iconColor),
              Text(
                widget.label,
                style: PTText.body.copyWith(fontSize: 14, color: widget.labelColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
