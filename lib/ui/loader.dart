import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';

import 'pt_theme.dart';

class PTLoader extends StatelessWidget {
  const PTLoader({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CupertinoActivityIndicator(radius: size / 2, color: color ?? PTColors.primary),
    );
  }
}
