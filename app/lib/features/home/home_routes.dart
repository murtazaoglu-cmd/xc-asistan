import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/home_screen.dart';

final List<RouteBase> homeRoutes = <RouteBase>[
  GoRoute(path: Routes.today, builder: (context, state) => const HomeScreen()),
];
