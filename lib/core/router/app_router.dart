import 'package:go_router/go_router.dart';
import '../../features/permission/presentation/permission_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../features/file_list/presentation/file_list_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/stats/presentation/stats_screen.dart';

class AppRoutes {
  static const permission = '/permission';
  static const home = '/';
  static const fileList = '/files';
  static const fileViewer = '/files/:filePath';
  static const settings = '/settings';
  static const map = '/map';
  static const search = '/search';
  static const stats = '/stats';
}

GoRouter buildAppRouter({bool firstLaunch = false}) => GoRouter(
  initialLocation: firstLaunch ? AppRoutes.permission : AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.permission,
      builder: (context, state) => const PermissionScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const DayMemoScreen(),
    ),
    GoRoute(
      path: AppRoutes.fileList,
      builder: (context, state) => const FileListScreen(),
    ),
    GoRoute(
      path: AppRoutes.fileViewer,
      builder: (context, state) {
        final filePath = Uri.decodeComponent(state.pathParameters['filePath'] ?? '');
        final displayName = state.uri.queryParameters['name'] ?? filePath;
        return DayMemoScreen(filePath: filePath, displayName: displayName);
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.map,
      builder: (context, state) => MapScreen(filePath: state.extra as String?),
    ),
    GoRoute(
      path: AppRoutes.search,
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: AppRoutes.stats,
      builder: (context, state) => const StatsScreen(),
    ),
  ],
);
