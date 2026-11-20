import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_service.dart';

final notificationsGatewayProvider = Provider<LocalNotificationsGateway>(
  (ref) => kIsWeb ? NoopNotificationsGateway() : PluginNotificationsGateway(),
);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final s = NotificationService(ref.watch(notificationsGatewayProvider));
  ref.onDispose(s.dispose);
  return s;
});
