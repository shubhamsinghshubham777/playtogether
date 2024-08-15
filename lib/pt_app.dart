import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:playtogether/features/auth/provider/auth_providers.dart';
import 'package:playtogether/features/dashboard/view/dashboard_screen.dart';
import 'package:playtogether/features/auth/view/auth_screen.dart';
import 'package:playtogether/utils.dart';
import 'package:window_manager/window_manager.dart';

class PTApp extends ConsumerStatefulWidget {
  const PTApp(this.flavor, {super.key});

  final AppFlavor flavor;

  @override
  ConsumerState<PTApp> createState() => _PTAppState();
}

class _PTAppState extends ConsumerState<PTApp> {
  bool? isLoggedIn;

  @override
  void initState() {
    postFrameCallBack(() async {
      final userId = await ref.read(currentUserIdProvider.future);
      setState(() => isLoggedIn = userId != null);
      // This is a workaround for distortion of window on start up
      // Ref: https://github.com/leanflutter/window_manager/issues/464#issuecomment-2254384071
      if (isDesktop) {
        final size = await windowManager.getSize();
        // Increase window size
        await windowManager.setSize(Size(size.width + 1, size.height + 1));
        // Wait for a while and decrease the window size while also bringing
        // it to foreground in order to refresh its content and avoid screen
        // distortion
        await Future.delayed(const Duration(milliseconds: 300), () async {
          await windowManager.setSize(Size(size.width, size.height));
          await windowManager.show();
        });
      }
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: ThemeMode.dark,
      darkTheme: FlexThemeData.dark(
        scheme: FlexScheme.greenM3,
        useMaterial3: true,
        useMaterial3ErrorColors: true,
      ),
      debugShowCheckedModeBanner: widget.flavor == AppFlavor.development,
      home: isLoggedIn != null
          ? Scaffold(
              body: isLoggedIn == true
                  ? const DashboardScreen()
                  : const AuthScreen(),
            )
          : null,
    );
  }
}
