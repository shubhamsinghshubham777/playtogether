import 'package:flutter/material.dart';
import 'package:playtogether/ui/pt_theme.dart';

class PTLogoMark extends StatelessWidget {
  const PTLogoMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: PTColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: PTColors.primary.withValues(alpha: 0.4),
            blurRadius: size * 0.55,
            offset: Offset(0, size * 0.2),
          ),
        ],
      ),
      child: Icon(Icons.play_arrow_rounded, size: size * 0.55, color: Colors.white),
    );
  }
}
