import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/pt_app.dart';
import 'package:playtogether/utils.dart';

Future<void> main() async {
  final appFlavor = AppFlavor.values.firstWhere(
    (flavor) =>
        flavor.name ==
        String.fromEnvironment(
          'FLAVOR',
          defaultValue: AppFlavor.production.name,
        ),
  );
  await initialiseApp(appFlavor);
  runApp(ProviderScope(child: PTApp(appFlavor)));
}
