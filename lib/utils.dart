import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.linux;

void postFrameCallBack(VoidCallback callback) {
  WidgetsBinding.instance.addPostFrameCallback((_) => callback());
}

T callback<T>(T Function() callback) => callback();

List<Widget> verticalSpace(double space, List<Widget> children) {
  final widgets = <Widget>[];
  for (var i = 0; i < children.length; i++) {
    widgets.add(
      Padding(
        padding: EdgeInsets.only(bottom: i != children.length ? space : 0),
        child: children[i],
      ),
    );
  }
  return widgets;
}
