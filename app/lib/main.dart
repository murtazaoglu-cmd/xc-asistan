import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_wiring.dart';
import 'core/notifications/notification_service.dart';
import 'core/storage/storage_providers.dart';

Future<void> main() async {
  // Web: '#' yerine temiz yollar (/customers/123). Mobilde etkisizdir.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  Intl.defaultLocale = 'tr_TR';
  NotificationService.initTimezone(); // Europe/Istanbul
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      retry: noProviderRetry,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...featureWiring,
      ],
      child: const XcApp(),
    ),
  );
}
