// DEMO: kimlik doğrulama ve sağlık uçları (sözleşme §1, §13, /health).
import '../auth/auth_models.dart';
import '../util/dates.dart';
import 'demo_db.dart';
import 'demo_router.dart';

List<DemoRoute> demoCoreRoutes(DemoDb db) => [
  DemoRoute(
    'GET',
    '/health',
    (req) => DemoResponse.json({
      'status': 'ok',
      'time': Ist.now().toIso8601String(),
    }),
    public: true,
  ),
  DemoRoute('POST', '/auth/login', (req) {
    final email = req.bodyMap.strOrEmpty('email').toLowerCase().trim();
    final password = req.bodyMap.strOrEmpty('password');
    if (email.isEmpty || password.isEmpty) {
      return DemoResponse.error(400, 'Geçersiz veya eksik değer girildi.');
    }
    // Demo kuralı: "yanlis" şifresi hatayı denemek içindir.
    if (password == 'yanlis')
      return DemoResponse.error(401, 'E-posta veya şifre hatalı.');
    final role = db.roleForEmail(email);
    final expires = Ist.now().add(const Duration(days: 30));
    return DemoResponse.json({
      'token': 'demo-token-${role.api}',
      'tokenType': 'Bearer',
      'expiresAt': expires.toIso8601String(),
      'expiresIn': 2592000,
      'user': db.userFor(role, email: email),
    });
  }, public: true),
  DemoRoute('GET', '/auth/me', (req) {
    final role = req.role ?? UserRole.admin;
    final caps = AppCapabilities.forRole(role);
    return DemoResponse.json({
      'user': db.userFor(role),
      'leader': role == UserRole.admin
          ? null
          : {'id': 'u-admin', 'name': 'Yönetici', 'role': 'admin'},
      'team': db.team(role),
      'capabilities': caps.toJson(),
      'session': {
        'client': 'mobile',
        'expiresAt': Ist.now().add(const Duration(days: 30)).toIso8601String(),
      },
    });
  }),
  DemoRoute('POST', '/auth/refresh', (req) {
    final role = req.role ?? UserRole.admin;
    return DemoResponse.json({
      'token': 'demo-token-${role.api}',
      'tokenType': 'Bearer',
      'expiresAt': Ist.now().add(const Duration(days: 30)).toIso8601String(),
      'expiresIn': 2592000,
      'user': db.userFor(role),
    });
  }),
  DemoRoute(
    'POST',
    '/auth/logout-all',
    (req) => DemoResponse.json({'message': 'Tüm oturumlar kapatıldı.'}),
  ),
  DemoRoute(
    'POST',
    '/push/device',
    (req) => DemoResponse.json({
      'id': 'dev-1',
      'platform': req.bodyMap.strOrEmpty('platform'),
      'app_version': req.bodyMap['app_version'],
      'created_at': Ist.now().toIso8601String(),
      'updated_at': Ist.now().toIso8601String(),
    }, status: 201),
  ),
  DemoRoute(
    'DELETE',
    '/push/device',
    (req) => DemoResponse.json({'message': 'Cihaz silindi.', 'removed': 1}),
  ),
];

extension DemoBodyX on Map<String, dynamic> {
  String strOrEmpty(String k) => this[k]?.toString() ?? '';
}
