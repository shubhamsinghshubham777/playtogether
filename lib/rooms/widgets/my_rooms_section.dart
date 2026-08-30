import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/rooms/room_models.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/loader.dart';
import 'package:playtogether/ui/pt_motion.dart';
import 'package:playtogether/ui/pt_theme.dart';

class MyRoomsSection extends StatelessWidget {
  const MyRoomsSection({
    super.key,
    required this.rooms,
    required this.serverNow,
    required this.onOpen,
    required this.onDelete,
    required this.busyRoomId,
    this.compact = false,
  });

  final List<MyRoom> rooms;
  final DateTime serverNow;
  final ValueChanged<MyRoom> onOpen;
  final ValueChanged<MyRoom> onDelete;
  final String? busyRoomId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: compact ? 24 : 26,
      opacity: compact ? 0.55 : 0.5,
      blur: compact ? 28 : 32,
      padding: EdgeInsets.all(compact ? 20 : 28),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        spacing: compact ? 14 : 18,
        children: [
          Row(
            spacing: 12,
            children: [
              Icon(
                Symbols.meeting_room_rounded,
                size: compact ? 20 : 22,
                fill: 1,
                color: PTColors.textAccent,
              ),
              Text(
                'Your rooms',
                style: compact
                    ? PTText.cardHeading.copyWith(fontSize: 16)
                    : PTText.cardHeading.copyWith(fontSize: 18),
              ),
              const Spacer(),
              Text(
                '${rooms.length}',
                style: PTText.mono.copyWith(fontSize: 12, color: PTColors.white(0.4)),
              ),
            ],
          ),
          Column(
            mainAxisSize: .min,
            spacing: 10,
            children: [
              for (final entry in rooms.asMap().entries)
                PTEntrance(
                  key: ValueKey(entry.value.room.id),
                  delay: Duration(milliseconds: 40 * entry.key),
                  duration: PTMotion.state,
                  offset: 8,
                  fade: false,
                  child: _RoomRow(
                    entry: entry.value,
                    serverNow: serverNow,
                    compact: compact,
                    busy: busyRoomId == entry.value.room.id,
                    onOpen: () => onOpen(entry.value),
                    onDelete: () => onDelete(entry.value),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomRow extends StatefulWidget {
  const _RoomRow({
    required this.entry,
    required this.serverNow,
    required this.compact,
    required this.busy,
    required this.onOpen,
    required this.onDelete,
  });

  final MyRoom entry;
  final DateTime serverNow;
  final bool compact;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  State<_RoomRow> createState() => _RoomRowState();
}

class _RoomRowState extends State<_RoomRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final room = entry.room;
    final live = entry.isLive;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: .opaque,
        onTap: widget.busy ? null : widget.onOpen,
        child: AnimatedContainer(
          duration: PTMotion.functional(context, PTMotion.hover),
          curve: PTMotion.enter,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 16, vertical: 13),
          decoration: BoxDecoration(
            color: PTColors.white(_hovered ? 0.09 : 0.05),
            border: Border.all(color: PTColors.white(_hovered ? 0.16 : 0.09)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            spacing: 12,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: live ? PTColors.primary.withValues(alpha: 0.2) : PTColors.white(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  live ? Symbols.play_circle_rounded : Symbols.bedtime_rounded,
                  size: 20,
                  fill: 1,
                  color: live ? PTColors.textAccent : PTColors.white(0.45),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 3,
                  children: [
                    Row(
                      spacing: 8,
                      children: [
                        Flexible(
                          child: Text(
                            room.name,
                            overflow: .ellipsis,
                            style: PTText.body.copyWith(fontSize: 14, fontWeight: .w600),
                          ),
                        ),
                        if (entry.isHost)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: PTColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Host',
                              style: PTText.mono.copyWith(fontSize: 9, color: PTColors.textAccent),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      _subtitle(entry, widget.serverNow),
                      overflow: .ellipsis,
                      style: PTText.mono.copyWith(fontSize: 11, color: PTColors.white(0.45)),
                    ),
                  ],
                ),
              ),
              if (widget.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: PTLoader(size: 18),
                )
              else ...[
                PTIconButton(
                  icon: Symbols.delete_rounded,
                  size: 34,
                  iconSize: 17,
                  glass: false,
                  tooltip: entry.isOwner
                      ? 'Delete room'
                      : 'Only the person who made this room can delete it',
                  onPressed: entry.isOwner ? widget.onDelete : null,
                ),
                Icon(
                  Symbols.chevron_right_rounded,
                  size: 20,
                  color: PTColors.white(_hovered ? 0.7 : 0.35),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(MyRoom entry, DateTime serverNow) {
    final room = entry.room;
    final people = '${entry.memberCount} ${entry.memberCount == 1 ? 'watcher' : 'watchers'}';
    if (entry.isLive) {
      return '$people · ${_left(room.expiresAt.difference(serverNow))} left';
    }
    if (room.persistent) return '$people · saved';
    final until = room.resumableUntil;
    if (until == null) return '$people · napping';
    return '$people · napping, gone in ${_left(until.difference(serverNow))}';
  }

  static String _left(Duration d) {
    if (d.isNegative) return 'moments';
    if (d.inHours >= 24) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes.clamp(1, 59)}m';
  }
}

class DeleteRoomDialog extends StatelessWidget {
  const DeleteRoomDialog({super.key, required this.roomName, required this.dormant});

  final String roomName;
  final bool dormant;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        Row(
          spacing: 13,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: PTColors.dangerBorder.withValues(alpha: 0.12),
                border: Border.all(color: PTColors.dangerBorder.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Symbols.delete_forever_rounded,
                size: 24,
                fill: 1,
                color: PTColors.danger,
              ),
            ),
            Expanded(child: Text('Delete this room?', style: PTText.cardHeading)),
          ],
        ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: roomName,
                style: TextStyle(color: PTColors.white(0.85)),
              ),
              TextSpan(
                text: dormant
                    ? " goes for good, along with everyone's place in it. There's no undo."
                    : ' goes for good. Anyone still watching gets sent back to their '
                          "lobby right away. There's no undo.",
              ),
            ],
          ),
          style: PTText.body.copyWith(fontSize: 14, color: PTColors.white(0.6), height: 1.55),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            spacing: 11,
            children: [
              Expanded(
                child: PTButton(
                  label: 'Keep it',
                  variant: .secondary,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              Expanded(
                child: PTButton(
                  label: 'Delete',
                  variant: .destructive,
                  height: 48,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
