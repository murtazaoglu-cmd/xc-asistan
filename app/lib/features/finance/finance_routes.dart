// Para rotaları (app_router.dart tarafından Para dalına eklenir). Form ekranları kök gezginde
// (kabuğun üstünde, alt çubuksuz) tam ekran açılır: başka modüller (jobs proje ekranı) herhangi
// bir sekmeden güvenle çağırabilir. Çağrı yardımcıları için bkz. finance_nav.dart.
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart' show rootNavigatorKey;
import 'finance_route_defs.dart';

export 'finance_nav.dart';

final List<RouteBase> financeRoutes = buildFinanceRoutes(
  parentKey: rootNavigatorKey,
);
