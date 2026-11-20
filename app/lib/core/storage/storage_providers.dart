import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_providers.dart';
import 'prefs.dart';
import 'token_store.dart';

/// `main()` içinde gerçek örnekle geçersiz kılınır (override).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider override edilmeli'),
);

final appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(ref.watch(sharedPreferencesProvider)),
);

/// DEMO modunda gerçek jetonlar karışmaz: mobilde bellek içi; web'de F5 sonrası oturum sürsün diye
/// demo jetonu localStorage'da (`PrefsTokenStore`). Gerçek modda güvenli depo.
final tokenStoreProvider = Provider<TokenStore>((ref) {
  if (!ref.watch(appConfigProvider).demo) return SecureTokenStore();
  return kIsWeb
      ? PrefsTokenStore(ref.watch(sharedPreferencesProvider))
      : MemoryTokenStore();
});
