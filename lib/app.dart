import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class App extends ConsumerWidget {
  final bool firstLaunch;
  const App({super.key, this.firstLaunch = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '낚.다',
      theme: AppTheme.dark,
      routerConfig: buildAppRouter(firstLaunch: firstLaunch),
      debugShowCheckedModeBanner: false,
    );
  }
}
