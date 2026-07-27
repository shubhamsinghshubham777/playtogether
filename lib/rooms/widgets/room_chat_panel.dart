import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_theme.dart';

class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.sync,
    required this.messages,
    required this.typingNames,
    required this.watchingCount,
    required this.onClose,
    required this.onSend,
    this.embedded = false,
    this.autofocus = false,
  });

  final SyncService sync;
  final List<ChatMessage> messages;
  final List<String> typingNames;
  final int watchingCount;
  final VoidCallback onClose;
  final ValueChanged<String> onSend;

  /// Embedded (mobile portrait) skips its own glass shell + close button.
  final bool embedded;

  /// Focus the input as soon as the panel mounts (desktop only — never on
  /// touch layouts, where it pops the soft keyboard on room entry).
  final bool autofocus;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocus = FocusNode();
  Timer? _typingDebounce;
  bool _sentTyping = false;

  // What the list was last laid out with. Snapshotted here rather than diffed
  // against `oldWidget`, because the room owns one mutable list and appends to
  // it in place — `widget.messages` and `oldWidget.messages` are the same object.
  int _seenCount = 0;
  DateTime? _seenLast;
  bool _seenTyping = false;

  @override
  void initState() {
    super.initState();
    _snapshot();
    // The panel mounts with history already loaded (and remounts every time it
    // is reopened), so land on the newest message instead of the top.
    _scrollToBottom(animate: false);
  }

  @override
  void didUpdateWidget(covariant RoomChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Count alone misses a history reload that swaps rows in place, and the
    // typing row counts towards the list's extent too.
    final last = widget.messages.lastOrNull;
    if (widget.messages.length == _seenCount &&
        last?.sentAt == _seenLast &&
        widget.typingNames.isNotEmpty == _seenTyping) {
      return;
    }
    // Read the offset *before* the new row lays out — someone who scrolled up to
    // read history keeps their place; our own outgoing message always wins.
    final follow = _nearBottom || last?.senderId == widget.sync.userId;
    _snapshot();
    if (follow) _scrollToBottom();
  }

  void _snapshot() {
    _seenCount = widget.messages.length;
    _seenLast = widget.messages.lastOrNull?.sentAt;
    _seenTyping = widget.typingNames.isNotEmpty;
  }

  /// Within a bubble or so of the end. True before the list has been laid out
  /// (nothing to scroll yet) so the first messages of a room still stick.
  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= 80;
  }

  /// Runs after the frame that lays the new row out — `maxScrollExtent` is only
  /// correct once the list has measured it.
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: Durations.short4,
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (text.isNotEmpty && !_sentTyping) {
      _sentTyping = true;
      widget.sync.broadcastTyping(true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _sentTyping = false;
      widget.sync.broadcastTyping(false);
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _typingDebounce?.cancel();
    if (_sentTyping) {
      _sentTyping = false;
      widget.sync.broadcastTyping(false);
    }
    widget.onSend(text);
    // Keep the caret in the field for the next line — Enter would otherwise hand
    // focus back to the player shortcuts (so the next Space toggles playback),
    // and tapping the send button never had it to begin with.
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(18, widget.embedded ? 12 : 16, 18, 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: PTColors.white(0.08))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text('Party chat', style: PTText.panelHeading),
                    Text(
                      '${widget.watchingCount} watching',
                      style: PTText.finePrint.copyWith(color: PTColors.white(0.5)),
                    ),
                  ],
                ),
              ),
              if (!widget.embedded)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(Icons.close_rounded, size: 19, color: PTColors.white(0.6)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            itemCount: widget.messages.length + (widget.typingNames.isNotEmpty ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              if (index == widget.messages.length) {
                return _typingRow();
              }
              final message = widget.messages[index];
              final own = message.senderId == widget.sync.userId;
              return own ? _ownBubble(message) : _otherBubble(message);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: PTColors.white(0.08))),
          ),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: PTColors.white(0.07),
                    border: Border.all(color: PTColors.white(0.1)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _inputFocus,
                    autofocus: widget.autofocus,
                    textInputAction: .send,
                    onChanged: _onTextChanged,
                    // The default `onEditingComplete` unfocuses on submit; `_send`
                    // owns focus instead. `onSubmitted` still fires after it.
                    onEditingComplete: () {},
                    onSubmitted: (_) => _send(),
                    maxLength: 500,
                    style: PTText.body.copyWith(fontSize: 13.5),
                    cursorColor: PTColors.textAccent,
                    decoration: InputDecoration(
                      hintText: 'Say something…',
                      hintStyle: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.45)),
                      border: InputBorder.none,
                      counterText: '',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: PTColors.buttonGradient,
                      shape: .circle,
                      boxShadow: [
                        BoxShadow(
                          color: PTColors.primary.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Symbols.send_rounded, size: 19, fill: 1, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return content;

    return GlassPanel(
      radius: 22,
      opacity: 0.6,
      blur: 32,
      baseColor: const Color(0xFF141022),
      child: content,
    );
  }

  Widget _typingRow() {
    final names = widget.typingNames;
    final label = names.length == 1
        ? '${names.first} is typing'
        : names.length == 2
        ? '${names[0]}, ${names[1]} are typing'
        : 'Several people are typing';
    return Row(
      spacing: 8,
      children: [
        Text(
          label,
          style: PTText.finePrint.copyWith(fontStyle: .italic, color: PTColors.white(0.5)),
        ),
        const TypingDots(),
      ],
    );
  }

  Widget _otherBubble(ChatMessage message) {
    return Row(
      crossAxisAlignment: .end,
      spacing: 10,
      children: [
        PTAvatar(userId: message.senderId, displayName: message.displayName, size: 28),
        Flexible(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 3,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  message.displayName,
                  style: TextStyle(
                    fontFamily: PTFonts.body,
                    fontSize: 11,
                    fontWeight: .w600,
                    color: PTColors.textAccent,
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 220),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: PTColors.white(0.08),
                  border: Border.all(color: PTColors.white(0.08)),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                    bottomLeft: Radius.circular(4),
                  ),
                ),
                child: Text(message.content, style: PTText.body.copyWith(fontSize: 13.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ownBubble(ChatMessage message) {
    return Align(
      alignment: .centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: PTColors.primary.withValues(alpha: 0.4),
          border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: 0.35)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(message.content, style: PTText.body.copyWith(fontSize: 13.5)),
      ),
    );
  }
}
