import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/room_models.dart';
import 'package:synctogether/rooms/widgets/room_overflow_menu.dart';
import 'package:synctogether/sync/sync_service.dart';

void main() {
  group('RoomOverflowMenu', () {
    testWidgets('displays Extend room duration for host and invokes callback on tap', (
      tester,
    ) async {
      var extendTapped = false;
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-host',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-host',
              displayName: 'Host User',
              role: 'host',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-host',
          selfIsHost: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onExtendRoom: () => extendTapped = true,
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Extend room duration'), findsOneWidget);

      await tester.tap(find.text('Extend room duration'));
      await tester.pumpAndSettle();

      expect(extendTapped, isTrue);
    });

    testWidgets('does not display Extend room duration for non-host members', (tester) async {
      final data = ValueNotifier<RoomMenuData?>(
        RoomMenuData(
          members: [
            RoomMember(
              roomId: 'room-1',
              userId: 'user-watcher',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          present: [
            PresentMember(
              userId: 'user-watcher',
              displayName: 'Watcher User',
              role: 'member',
              joinedAt: DateTime(2026, 1, 1),
            ),
          ],
          media: RoomMedia.none,
          transportLock: false,
          selfId: 'user-watcher',
          selfIsHost: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRoomOverflowMenu(
                  context: context,
                  data: data,
                  onCopyInvite: () {},
                  onLeave: () {},
                  onEndRoom: () {},
                  onExtendRoom: () {},
                  onTransportLockChanged: (_) {},
                  onKick: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Extend room duration'), findsNothing);
    });
  });
}
