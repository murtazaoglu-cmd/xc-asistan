import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/change_password_screen.dart';
import 'presentation/settings_screen.dart';
import 'presentation/user_form_screen.dart';
import 'presentation/users_screen.dart';

/// Ayarlar + Kullanıcılar rotaları (yetki: `RouteGuard` /users → yalnız admin/ortak).
final List<RouteBase> settingsRoutes = <RouteBase>[
  GoRoute(
    path: Routes.settings,
    builder: (context, state) => const SettingsScreen(),
    routes: <RouteBase>[
      GoRoute(
        path: 'password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
    ],
  ),
  GoRoute(
    path: Routes.users,
    builder: (context, state) => const UsersScreen(),
    routes: <RouteBase>[
      GoRoute(path: 'new', builder: (context, state) => const UserFormScreen()),
    ],
  ),
];
