import 'package:flutter/widgets.dart';

class ScrollFadeEdge extends StatefulWidget {
  const ScrollFadeEdge({super.key, required this.child, this.height = 72});

  final Widget child;
  final double height;

  @override
  State<ScrollFadeEdge> createState() => _ScrollFadeEdgeState();
}

class _ScrollFadeEdgeState extends State<ScrollFadeEdge> {
  final ValueNotifier<double> _reveal = ValueNotifier(0);

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) return false;
    _reveal.value = (notification.metrics.extentBefore / widget.height).clamp(0.0, 1.0);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        fit: .expand,
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.height,
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: _reveal,
                builder: (context, reveal, child) => Opacity(opacity: reveal, child: child),
                child: const DecoratedBox(decoration: BoxDecoration(gradient: _veil)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _veil = LinearGradient(
  begin: .topCenter,
  end: .bottomCenter,
  colors: [Color(0x990B0A14), Color(0x5E0B0A14), Color(0x260B0A14), Color(0x000B0A14)],
  stops: [0, 0.34, 0.64, 1],
);
