import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:playtogether/platform.dart';
import 'package:playtogether/player/youtube/youtube_links.dart';
import 'package:playtogether/sync/sync_service.dart';
import 'package:playtogether/ui/buttons.dart';
import 'package:playtogether/ui/glass.dart';
import 'package:playtogether/ui/identity.dart';
import 'package:playtogether/ui/pt_motion.dart';
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
    required this.onCopied,
    this.onPlaySharedVideo,
    this.embedded = false,
    this.premiumMembers = const {},
  });

  final SyncService sync;
  final List<ChatMessage> messages;
  final List<String> typingNames;
  final int watchingCount;
  final VoidCallback onClose;
  final ValueChanged<String> onSend;
  final VoidCallback onCopied;
  final void Function(String videoId, String sharedBy)? onPlaySharedVideo;
  final Set<String> premiumMembers;

  /// Embedded (mobile portrait) skips its own glass shell + close button.
  final bool embedded;

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

  /// Messages whose entrance has already played. Required, not an optimisation:
  /// `itemBuilder` re-runs every time a row scrolls back into view, so a
  /// one-shot animation keyed only by message identity would replay on every
  /// scroll. Keyed by *value* rather than object identity so the reconnect
  /// history merge — which swaps equivalent rows in place — doesn't re-animate
  /// the entire backlog.
  final _animated = <String>{};

  static String _keyOf(ChatMessage m) =>
      '${m.senderId}|${m.sentAt.microsecondsSinceEpoch}|${m.content}';

  @override
  void initState() {
    super.initState();
    _snapshot();
    // Everything already loaded is history: it renders statically, only
    // messages appended after mount animate in.
    _animated.addAll(widget.messages.map(_keyOf));
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
        _scrollController.animateTo(target, duration: Durations.short4, curve: Curves.easeOut);
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
                  child: PTPressable(
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
          child: SelectionArea(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              // The typing slot is always present so it can collapse rather than
              // pop; its own gap lives inside it, which is why the separator
              // before it is suppressed.
              itemCount: widget.messages.length + 1,
              separatorBuilder: (_, index) => index == widget.messages.length - 1
                  ? const SizedBox.shrink()
                  : const SizedBox(height: 14),
              itemBuilder: (context, index) {
                if (index == widget.messages.length) {
                  return _typingRow();
                }
                final message = widget.messages[index];
                final bubble = _MessageRow(
                  message: message,
                  own: message.senderId == widget.sync.userId,
                  premium: widget.premiumMembers.contains(message.senderId),
                  onCopied: widget.onCopied,
                  onPlaySharedVideo: widget.onPlaySharedVideo,
                );
                final key = _keyOf(message);
                if (!_animated.add(key)) return bubble;
                return PTEntrance(duration: PTMotion.state, offset: 6, child: bubble);
              },
            ),
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
                child: PTPressable(
                  onTap: _send,
                  pressedScale: 0.92,
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
    return AnimatedSize(
      duration: PTMotion.functional(context, PTMotion.state),
      curve: PTMotion.enter,
      alignment: .topLeft,
      child: names.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(
                spacing: 8,
                children: [
                  Text(
                    label,
                    style: PTText.finePrint.copyWith(
                      fontStyle: .italic,
                      color: PTColors.white(0.5),
                    ),
                  ),
                  const TypingDots(),
                ],
              ),
            ),
    );
  }
}

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.own,
    required this.premium,
    required this.onCopied,
    required this.onPlaySharedVideo,
  });

  final ChatMessage message;
  final bool own;
  final bool premium;
  final VoidCallback onCopied;
  final void Function(String videoId, String sharedBy)? onPlaySharedVideo;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  bool _hovered = false;
  late List<MessageSegment> _segments;
  final _linkTaps = <int, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _parseContent();
  }

  @override
  void didUpdateWidget(covariant _MessageRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content) _parseContent();
  }

  @override
  void dispose() {
    _disposeLinkTaps();
    super.dispose();
  }

  void _disposeLinkTaps() {
    for (final recognizer in _linkTaps.values) {
      recognizer.dispose();
    }
    _linkTaps.clear();
  }

  void _parseContent() {
    _disposeLinkTaps();
    _segments = splitYouTubeLinks(widget.message.content);
    for (var i = 0; i < _segments.length; i++) {
      final videoId = _segments[i].videoId;
      if (videoId == null) continue;
      _linkTaps[i] = TapGestureRecognizer()..onTap = () => _play(videoId);
    }
  }

  void _play(String videoId) {
    widget.onPlaySharedVideo?.call(videoId, widget.message.displayName);
  }

  bool get _actionable => widget.onPlaySharedVideo != null && _linkTaps.isNotEmpty;

  String? get _soleVideoId {
    final ids = _segments.map((segment) => segment.videoId).nonNulls.toSet();
    return ids.length == 1 ? ids.single : null;
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.message.content));
    widget.onCopied();
  }

  Widget _text() {
    final base = PTText.body.copyWith(fontSize: 13.5);
    if (_linkTaps.isEmpty) return Text(widget.message.content, style: base);
    final linkColor = widget.own ? Colors.white : PTColors.textAccent;
    final linkStyle = base.copyWith(
      color: linkColor,
      fontWeight: .w500,
      decoration: _actionable ? TextDecoration.underline : null,
      decorationColor: linkColor.withValues(alpha: 0.45),
    );
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < _segments.length; i++)
            if (_segments[i].videoId == null)
              TextSpan(text: _segments[i].text)
            else
              TextSpan(
                text: _segments[i].text,
                style: linkStyle,
                recognizer: _actionable ? _linkTaps[i] : null,
                mouseCursor: _actionable ? SystemMouseCursors.click : null,
              ),
        ],
      ),
      style: base,
    );
  }

  Widget _bubbleBody() {
    final videoId = _actionable ? _soleVideoId : null;
    if (videoId == null) return _text();
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        _text(),
        _PlaySharedVideoButton(own: widget.own, onTap: () => _play(videoId)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final copyButton = AnimatedOpacity(
      duration: PTMotion.functional(context, PTMotion.hover),
      opacity: !isDesktop || _hovered ? 1 : 0,
      child: PTIconButton(
        icon: Symbols.content_copy_rounded,
        onPressed: _copy,
        size: 26,
        iconSize: 15,
        glass: false,
        color: PTColors.white(0.55),
        tooltip: 'Copy message',
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.own ? _own(copyButton) : _other(copyButton),
    );
  }

  Widget _other(Widget copyButton) {
    final message = widget.message;
    return Row(
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        PTAvatar(
          userId: message.senderId,
          displayName: message.displayName,
          size: 28,
          premium: widget.premium,
        ),
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
                child: _bubbleBody(),
              ),
            ],
          ),
        ),
        copyButton,
      ],
    );
  }

  Widget _own(Widget copyButton) {
    return Row(
      mainAxisAlignment: .end,
      crossAxisAlignment: .end,
      spacing: 8,
      children: [
        copyButton,
        Flexible(
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
            child: _bubbleBody(),
          ),
        ),
      ],
    );
  }
}

class _PlaySharedVideoButton extends StatefulWidget {
  const _PlaySharedVideoButton({required this.own, required this.onTap});

  final bool own;
  final VoidCallback onTap;

  @override
  State<_PlaySharedVideoButton> createState() => _PlaySharedVideoButtonState();
}

class _PlaySharedVideoButtonState extends State<_PlaySharedVideoButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.own ? Colors.white : PTColors.textAccent;
    final fill = widget.own
        ? PTColors.white(_hovered ? 0.22 : 0.14)
        : PTColors.primary.withValues(alpha: _hovered ? 0.38 : 0.24);
    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: PTPressable(
          onTap: widget.onTap,
          pressedScale: 0.97,
          child: AnimatedContainer(
            duration: PTMotion.functional(context, PTMotion.hover),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: tint.withValues(alpha: 0.34)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              spacing: 6,
              children: [
                Icon(Symbols.play_circle_rounded, size: 16, fill: 1, color: tint),
                Flexible(
                  child: Text(
                    'Play for everyone',
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: PTText.caption.copyWith(fontSize: 12, color: tint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
