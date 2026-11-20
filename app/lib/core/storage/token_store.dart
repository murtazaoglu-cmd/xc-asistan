// Jeton ve son bilinen /auth/me yanıtı: Keychain/Keystore (flutter_secure_storage).
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class TokenStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);

  /// Çevrimdışı açılış için son /auth/me yanıtının JSON metni.
  Future<String?> readMeCache();
  Future<void> writeMeCache(String json);

  /// Jeton + önbellek silinir (çıkış).
  Future<void> clear();
}

/// WEB: jeton tarayıcı depolamasında AES-GCM (WebCrypto) ile şifreli saklanır. Şifreleme anahtarı
/// aynı tarayıcı deposunda durur (isteğe bağlı `WEB_WRAP_KEY`: yalnız kalıcı depoyu sarar), bu yüzden
/// KORUMA SEVİYESİ "açık metin değil / başka siteler okuyamaz" düzeyindedir; sayfaya betik sokan
/// bir saldırıya (XSS) karşı asıl savunma sıkı CSP'dir (docs/WEB-DEPLOY.md). `--dart-define=
/// WEB_SESSION_ONLY=true` jetonu `sessionStorage`'a yazar: sekme kapanınca oturum biter, F5'te sürer.
const bool kWebSessionOnly = bool.fromEnvironment('WEB_SESSION_ONLY');
const String _kWebWrapKey = String.fromEnvironment('WEB_WRAP_KEY');
const String _kWebWrapIv = String.fromEnvironment('WEB_WRAP_IV');

FlutterSecureStorage _defaultSecureStorage() => FlutterSecureStorage(
  webOptions: WebOptions(
    dbName: 'xc_asistan',
    publicKey: 'xc_asistan_panel',
    wrapKey: _kWebWrapKey,
    wrapKeyIv: _kWebWrapIv,
    useSessionStorage: kWebSessionOnly,
  ),
);

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? _defaultSecureStorage();

  final FlutterSecureStorage _s;
  static const _kToken = 'xc.auth.token';
  static const _kMe = 'xc.auth.me';

  @override
  Future<String?> readToken() async {
    try {
      return await _s.read(key: _kToken);
    } catch (_) {
      return null; // bozuk depo: oturum yok sayılır, giriş istenir
    }
  }

  @override
  Future<void> writeToken(String token) => _s.write(key: _kToken, value: token);

  @override
  Future<String?> readMeCache() async {
    try {
      return await _s.read(key: _kMe);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeMeCache(String json) => _s.write(key: _kMe, value: json);

  @override
  Future<void> clear() async {
    try {
      await _s.delete(key: _kToken);
      await _s.delete(key: _kMe);
    } catch (_) {}
  }
}

/// DEMO web: sayfa yenilenince (F5) oturum sürsün diye `SharedPreferences`'ta (localStorage)
/// tutulur. DEMO jetonu (`demo-token-<rol>`) gizli bilgi değildir; gerçek jeton buraya GİRMEZ.
class PrefsTokenStore implements TokenStore {
  PrefsTokenStore(this._p);
  final SharedPreferences _p;
  static const _kToken = 'xc.demo.token';
  static const _kMe = 'xc.demo.me';

  @override
  Future<String?> readToken() async => _p.getString(_kToken);
  @override
  Future<void> writeToken(String token) => _p.setString(_kToken, token);
  @override
  Future<String?> readMeCache() async => _p.getString(_kMe);
  @override
  Future<void> writeMeCache(String json) => _p.setString(_kMe, json);
  @override
  Future<void> clear() async {
    await _p.remove(_kToken);
    await _p.remove(_kMe);
  }
}

/// Test ve DEMO modu için bellek içi depo.
class MemoryTokenStore implements TokenStore {
  String? token;
  String? me;

  @override
  Future<String?> readToken() async => token;
  @override
  Future<void> writeToken(String t) async => token = t;
  @override
  Future<String?> readMeCache() async => me;
  @override
  Future<void> writeMeCache(String json) async => me = json;
  @override
  Future<void> clear() async {
    token = null;
    me = null;
  }
}
