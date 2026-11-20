import 'package:go_router/go_router.dart';

import '../../core/router/routes.dart';
import 'presentation/more_screen.dart';

final List<RouteBase> moreRoutes = <RouteBase>[
  GoRoute(path: Routes.more, builder: (context, state) => const MoreScreen()),
];
