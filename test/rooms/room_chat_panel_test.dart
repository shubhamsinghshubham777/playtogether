import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synctogether/rooms/widgets/room_chat_panel.dart';
import 'package:synctogether/sync/sync_service.dart';

import '../sync/fakes.dart';

const _me = 'me';
const _other = 'other';

SyncService _sync({String role = 'host'}) => SyncService(
  FakeSyncPlayer(),
  room: testRoom(),
  profile: testProfile(_me),
  role: role,
  backend: FakeSyncBackend(),
);

ChatMessage _shared(String content) => ChatMessage(
  senderId: _other,
  displayName: 'Riya',
  content: content,
  sentAt: DateTime.utc(2026, 7, 31, 16),
);

Future<void> _pump(
  WidgetTester tester, {
  required SyncService sync,
  required List<ChatMessage> messages,
  void Function(String videoId, String sharedBy)? onPlaySharedVideo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 330,
          height: 460,
          child: RoomChatPanel(
            sync: sync,
            messages: messages,
            typingNames: const [],
            watchingCount: 2,
            onClose: () {},
            onSend: (_) {},
            onCopied: () {},
            onPlaySharedVideo: onPlaySharedVideo,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const withLink =
      "hey! check out this video. let's play it: https://www.youtube.com/watch?v=J-95Mhipb98";

  testWidgets('a host tapping the link in a message is asked about that video', (tester) async {
    final sync = _sync();
    final asked = <(String, String)>[];
    await _pump(
      tester,
      sync: sync,
      messages: [_shared(withLink)],
      onPlaySharedVideo: (videoId, sharedBy) => asked.add((videoId, sharedBy)),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText().contains('youtube.com'),
      ),
    );
    final linkOffset = paragraph.getOffsetForCaret(
      TextPosition(offset: withLink.indexOf('https://') + 8),
      Rect.zero,
    );
    await tester.tapAt(paragraph.localToGlobal(linkOffset + const Offset(0, 6)));
    await tester.pump();

    expect(asked, [('J-95Mhipb98', 'Riya')]);
    sync.dispose();
  });

  testWidgets('the host also gets a button under a message that shares one video', (tester) async {
    final sync = _sync();
    final asked = <String>[];
    await _pump(
      tester,
      sync: sync,
      messages: [_shared(withLink)],
      onPlaySharedVideo: (videoId, _) => asked.add(videoId),
    );

    expect(find.text('Play for everyone'), findsOneWidget);
    await tester.tap(find.text('Play for everyone'));
    await tester.pump();
    expect(asked, ['J-95Mhipb98']);
    sync.dispose();
  });

  testWidgets('the button label stays out of the chat selection', (tester) async {
    final sync = _sync();
    await _pump(tester, sync: sync, messages: [_shared(withLink)], onPlaySharedVideo: (_, _) {});

    final container = tester.widget<SelectionContainer>(
      find
          .ancestor(of: find.text('Play for everyone'), matching: find.byType(SelectionContainer))
          .first,
    );
    expect(container.delegate, isNull);
    sync.dispose();
  });

  testWidgets('the prose around the link survives untouched', (tester) async {
    final sync = _sync();
    await _pump(tester, sync: sync, messages: [_shared(withLink)], onPlaySharedVideo: (_, _) {});

    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText().contains('youtube.com'),
      ),
    );
    expect(rich.text.toPlainText(), withLink);
    sync.dispose();
  });

  testWidgets('a member gets no button and no tap target', (tester) async {
    final sync = _sync(role: 'member');
    await _pump(tester, sync: sync, messages: [_shared(withLink)]);

    expect(find.text('Play for everyone'), findsNothing);
    final rich = tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText().contains('youtube.com'),
      ),
    );
    final recognizers = <GestureRecognizer>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) recognizers.add(span.recognizer!);
      return true;
    });
    expect(recognizers, isEmpty);
    sync.dispose();
  });

  testWidgets('a message sharing two videos keeps the links but drops the button', (tester) async {
    final sync = _sync();
    await _pump(
      tester,
      sync: sync,
      messages: [
        _shared('this https://youtu.be/J-95Mhipb98 or this youtube.com/watch?v=dQw4w9WgXcQ ?'),
      ],
      onPlaySharedVideo: (_, _) {},
    );

    expect(find.text('Play for everyone'), findsNothing);
    sync.dispose();
  });

  testWidgets('a message with no link stays a plain paragraph', (tester) async {
    final sync = _sync();
    await _pump(
      tester,
      sync: sync,
      messages: [_shared('are we starting soon?')],
      onPlaySharedVideo: (_, _) {},
    );

    expect(find.text('are we starting soon?'), findsOneWidget);
    expect(find.text('Play for everyone'), findsNothing);
    sync.dispose();
  });

  testWidgets('can scroll up in chatbox without being forced back to the bottom', (tester) async {
    final sync = _sync();
    final messages = List.generate(
      30,
      (i) => ChatMessage(
        senderId: i.isEven ? _me : _other,
        displayName: 'User $i',
        content: 'Message $i',
        sentAt: DateTime.utc(2026, 7, 31, 16, i),
      ),
    );

    await _pump(tester, sync: sync, messages: messages);

    // Initial state: scrolled to bottom. Message 29 should be visible.
    expect(find.text('Message 29'), findsOneWidget);

    final listFinder = find.byType(ListView);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: listFinder, matching: find.byType(Scrollable)),
    );
    final initialOffset = scrollable.position.pixels;
    expect(initialOffset, greaterThan(0));

    // Try scrolling up using mouse wheel events
    await tester.sendEventToBinding(
      PointerScrollEvent(position: tester.getCenter(listFinder), scrollDelta: const Offset(0, -40)),
    );
    await tester.pumpAndSettle();

    final scrolledOffset = scrollable.position.pixels;
    expect(scrolledOffset, lessThan(initialOffset));
    sync.dispose();
  });

  testWidgets('loading history after initial empty mount scrolls to bottom', (tester) async {
    final sync = _sync();
    final messages = <ChatMessage>[];

    await _pump(tester, sync: sync, messages: messages);

    // Now history loads
    messages.addAll(
      List.generate(
        30,
        (i) => ChatMessage(
          senderId: i.isEven ? _me : _other,
          displayName: 'User $i',
          content: 'Message $i',
          sentAt: DateTime.utc(2026, 7, 31, 16, i),
        ),
      ),
    );

    // Re-pump with the loaded messages
    await _pump(tester, sync: sync, messages: messages);

    expect(find.text('Message 29'), findsOneWidget);
    sync.dispose();
  });
}
