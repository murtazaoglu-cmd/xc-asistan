import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/login_screen.dart';
import 'presentation/splash_screen.dart';
import 'presentation/update_required_screen.dart';

/// Kabuk dışı rotalar: açılış, giriş, zorunlu güncelleme.
final List<RouteBase> authRoutes = <RouteBase>[
  GoRoute(
    path: Routes.splash,
    builder: (context, state) => const SplashScreen(),
  ),
  GoRoute(path: Routes.login, builder: (context, state) => const LoginScreen()),
  GoRoute(
    path: Routes.updateRequired,
    builder: (context, state) => const UpdateRequiredScreen(),
  ),
];
