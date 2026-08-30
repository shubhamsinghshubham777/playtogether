import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:synctogether/player/youtube/youtube_links.dart';
import 'package:synctogether/ui/buttons.dart';
import 'package:synctogether/ui/loader.dart';
import 'package:synctogether/ui/pt_theme.dart';

class PlaySharedVideoDialog extends StatelessWidget {
  const PlaySharedVideoDialog({super.key, required this.videoId, required this.sharedBy});

  final String videoId;
  final String sharedBy;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(color: PTColors.white(0.06)),
              child: Image.network(
                youtubeThumbnailUrl(videoId),
                fit: .cover,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : const Center(child: PTLoader(size: 22)),
                errorBuilder: (context, _, _) => Center(
                  child: Icon(
                    Symbols.smart_display_rounded,
                    size: 34,
                    fill: 1,
                    color: PTColors.white(0.3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Play this video?',
          textAlign: .center,
          style: PTText.screenTitle.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          '$sharedBy shared it in chat. Everyone in the room switches over to it.',
          textAlign: .center,
          style: PTText.body.copyWith(fontSize: 13.5, color: PTColors.white(0.55)),
        ),
        const SizedBox(height: 20),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: PTButton(
                label: 'Not now',
                variant: .secondary,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
            Expanded(
              child: PTButton(
                label: 'Play it',
                icon: Symbols.play_arrow_rounded,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
