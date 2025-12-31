import 'dart:async';

import 'package:flutter/material.dart';
import 'package:playtogether/sync/sync_events.dart';
import 'package:playtogether/sync/sync_service.dart';

class ChatBox extends StatefulWidget {
  const ChatBox({super.key, required this.syncService, required this.onClose});

  final SyncService syncService;
  final VoidCallback onClose;

  @override
  State<ChatBox> createState() => _ChatBoxState();
}

class _ChatBoxState extends State<ChatBox> {
  late final List<ChatEvent> _messages;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  StreamSubscription<ChatEvent>? _subscription;
  StreamSubscription<TypingEvent>? _typingSubscription;
  String? _peerTypingUsername;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    // Load existing chat history
    _messages = List.from(widget.syncService.chatHistory);
    _subscription = widget.syncService.chatMessages.listen(_onMessage);
    _typingSubscription = widget.syncService.typingStream.listen(_onTypingEvent);
    _controller.addListener(_onTextChanged);
    _scrollToBottom();
  }

  void _onTypingEvent(TypingEvent event) {
    setState(() {
      _peerTypingUsername = event.isTyping ? event.username : null;
    });
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _isTyping) {
      _isTyping = hasText;
      widget.syncService.broadcastTyping(hasText);
    }
  }

  void _onMessage(ChatEvent event) {
    setState(() => _messages.add(event));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    _focusNode.requestFocus();
    // Broadcast that we stopped typing
    if (_isTyping) {
      _isTyping = false;
      widget.syncService.broadcastTyping(false);
    }
    final event = await widget.syncService.broadcastChat(text);

    // Add own message to the list immediately (already stored in service history)
    setState(() {
      _messages.add(event);
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _typingSubscription?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(left: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: .spaceBetween,
              children: [
                Expanded(
                  child: const Row(
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 20),
                      SizedBox(width: 8),
                      Text('Chat', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close)),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8) + MediaQuery.viewPaddingOf(context),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg.username == widget.syncService.username;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg.username,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isMe ? colors.primaryContainer : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg.message, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Typing indicator
          if (_peerTypingUsername != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '$_peerTypingUsername is typing',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 20,
                    height: 12,
                    child: _TypingDots(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),

          // Input
          Container(
            margin: EdgeInsetsGeometry.only(bottom: MediaQuery.of(context).viewPadding.bottom),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send_rounded),
                  iconSize: 20,
                  style: IconButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});

  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (index) {
            final delay = index * 0.2;
            final t = (_controller.value + delay) % 1.0;
            final opacity = (1 - (t - 0.5).abs() * 2).clamp(0.3, 1.0);
            return Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
