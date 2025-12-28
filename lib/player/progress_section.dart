import 'package:flutter/material.dart';

class ProgressSection extends StatefulWidget {
  const ProgressSection({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.volumeSection,
  });

  final Duration position, duration;
  final Future<void> Function(Duration) onSeek;
  final Widget volumeSection;

  @override
  State<ProgressSection> createState() => _ProgressSectionState();
}

class _ProgressSectionState extends State<ProgressSection> {
  bool sliding = false;
  double progress = 0;

  @override
  Widget build(BuildContext context) {
    final currentDuration =
        '${sliding ? formatDuration(widget.duration * progress) : formatDuration(widget.position)}'
        ' / ${formatDuration(widget.duration)}';

    final sliderValue = sliding
        ? progress
        : widget.position.inMilliseconds / widget.duration.inMilliseconds;

    return Column(
      crossAxisAlignment: .start,
      spacing: 16,
      children: [
        Row(
          spacing: 8,
          mainAxisAlignment: .spaceBetween,
          children: [
            Text(currentDuration, style: TextStyle(fontSize: 16)),
            widget.volumeSection,
          ],
        ),
        Slider(
          padding: EdgeInsets.zero,
          value: sliderValue.clamp(0, 1),
          onChangeStart: (percentage) => setState(() {
            progress = percentage;
            sliding = true;
          }),
          onChanged: (percentage) => setState(() => progress = percentage),
          onChangeEnd: (percentage) async {
            await widget.onSeek(widget.duration * percentage);
            setState(() {
              progress = percentage;
              sliding = false;
            });
          },
        ),
      ],
    );
  }

  String formatDuration(Duration duration) {
    // Use .abs() to handle negative durations if necessary
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    // We use remainder(60) to get only the minutes/seconds within the hour/minute
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
}
