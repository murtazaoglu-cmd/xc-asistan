// DEMO uçları: /users (A, O), şifre uçları. Kullanıcılar bellekte tutulur (uygulama kapanınca sıfırlanır).
// Kurallar sunucuyla aynıdır: ortak yalnız kendi oluşturduğunu görür/siler ve yalnız saha/personel açar;
// kendini silemezsin (400); aynı e-posta 409; geçersiz e-posta/zayıf şifre 400.
// PATCH /users/:id (rol/aktif) sunucuda HENÜZ YOK; DEMO'da arayüzü denemek için sağlanır.
import '../../../core/auth/auth_models.dart';
import '../../../core/demo/demo_db.dart';
import '../../../core/demo/demo_router.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/json.dart';

const _weak = {'123456', 'password', 'qwerty', '12345678', '111111'};
final _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

DemoResponse _forbidden() =>
    DemoResponse.error(403, 'Bu işlem için yetkiniz yok.');
DemoResponse _invalid([String m = 'Geçersiz veya eksik değer girildi.']) =>
    DemoResponse.error(400, m);

List<DemoRoute> settingsDemoRoutes(DemoDb db) {
  JsonMap u(
    String id,
    String name,
    String email,
    UserRole role, {
    String? by,
  }) => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.api,
    'created_at': db.iso(Ist.now().subtract(const Duration(days: 90))),
    'created_by': by,
  };
  final users = <JsonMap>[
    u('u-admin', 'Yönetici', 'admin@demo.com', UserRole.admin),
    u(
      'u-muhasebe',
      'Muhasebe',
      'muhasebe@demo.com',
      UserRole.muhasebe,
      by: 'u-admin',
    ),
    u(
      'u-ortak',
      'Ortak Firma',
      'ortak@demo.com',
      UserRole.ortak,
      by: 'u-admin',
    ),
    u(
      'u-personel',
      'Personel',
      'personel@demo.com',
      UserRole.personel,
      by: 'u-admin',
    ),
    u('u-saha', 'Saha Ekibi', 'saha@demo.com', UserRole.saha, by: 'u-admin'),
    u(
      'u-ortak-p1',
      'Ortak Personeli',
      'ortak.personel@demo.com',
      UserRole.personel,
      by: 'u-ortak',
    ),
  ];

  String? selfId(DemoRequest r) => r.role == null ? null : 'u-${r.role!.api}';
  bool manage(DemoRequest r) =>
      r.role == UserRole.admin || r.role == UserRole.ortak;
  JsonMap? find(String? id) => users.where((e) => e['id'] == id).firstOrNull;
  // ortak yalnız kendi oluşturdukları üzerinde işlem yapar.
  bool inScope(DemoRequest r, JsonMap target) =>
      r.role == UserRole.admin || target['created_by'] == selfId(r);
  JsonMap pub(JsonMap e) => {...e};

  return [
    DemoRoute('GET', '/users', (req) {
      if (!manage(req)) return _forbidden();
      final rows = req.role == UserRole.admin
          ? users
          : users.where((e) => e['created_by'] == selfId(req));
      return DemoResponse.json([for (final e in rows) pub(e)]);
    }),
    DemoRoute('POST', '/users', (req) {
      if (!manage(req)) return _forbidden();
      final b = req.bodyMap;
      final name = (b['name'] is String ? b['name'] as String : '').trim();
      final email = (b['email'] is String ? b['email'] as String : '')
          .trim()
          .toLowerCase();
      final password = b['password'] is String ? b['password'] as String : '';
      final role = UserRole.fromApi(
        b['role'] is String ? b['role'] as String : null,
      );
      if (name.isEmpty || name.length > 100) return _invalid();
      if (!_emailRe.hasMatch(email))
        return _invalid('Geçerli bir e-posta girin.');
      if (password.length < 6 || _weak.contains(password.toLowerCase())) {
        return _invalid(
          'Şifre en az 6 karakter olmalı ve çok yaygın olmamalı.',
        );
      }
      if (role == null) return _invalid();
      if (req.role == UserRole.ortak &&
          role != UserRole.saha &&
          role != UserRole.personel) {
        return _forbidden();
      }
      if (users.any((e) => e['email'] == email)) {
        return DemoResponse.error(
          409,
          'Bu e-posta ile kayıtlı bir kullanıcı var.',
        );
      }
      var by = selfId(req);
      final leader = b['leader_id'];
      if (req.role == UserRole.admin &&
          leader is String &&
          (role == UserRole.personel || role == UserRole.saha) &&
          find(leader)?['role'] == 'ortak') {
        by = leader; // ortak firmaya bağla
      }
      final row = u(db.nextId('u'), name, email, role, by: by);
      users.add(row);
      return DemoResponse.json(pub(row), status: 201);
    }),
    // "me" önce: /users/:id/password kalıbıyla çakışmasın.
    DemoRoute('PATCH', '/users/me/password', (req) {
      final b = req.bodyMap;
      final cur = b['current_password'] is String
          ? b['current_password'] as String
          : '';
      final next = b['new_password'] is String
          ? b['new_password'] as String
          : '';
      if (cur.isEmpty || cur == 'yanlis') {
        return _invalid('Mevcut şifre hatalı.');
      }
      if (next.length < 6 || _weak.contains(next.toLowerCase())) {
        return _invalid(
          'Yeni şifre en az 6 karakter olmalı ve çok yaygın olmamalı.',
        );
      }
      final role = req.role ?? UserRole.admin;
      return DemoResponse.json({
        'message': 'Şifre değiştirildi.',
        'token': 'demo-token-${role.api}',
        'tokenType': 'Bearer',
        'expiresAt': Ist.now().add(const Duration(days: 30)).toIso8601String(),
        'expiresIn': 2592000,
        'user': db.userFor(role),
      });
    }),
    DemoRoute('PATCH', '/users/:id/password', (req) {
      if (!manage(req)) return _forbidden();
      final t = find(req.params['id']);
      if (t == null) return DemoResponse.error(404, 'Kullanıcı bulunamadı.');
      if (!inScope(req, t)) return _forbidden();
      final next = req.bodyMap['new_password'];
      if (next is! String ||
          next.length < 6 ||
          _weak.contains(next.toLowerCase())) {
        return _invalid(
          'Şifre en az 6 karakter olmalı ve çok yaygın olmamalı.',
        );
      }
      return DemoResponse.json({'message': 'Şifre sıfırlandı.'});
    }),
    DemoRoute('PATCH', '/users/:id', (req) {
      if (req.role != UserRole.admin) return _forbidden();
      final t = find(req.params['id']);
      if (t == null) return DemoResponse.error(404, 'Kullanıcı bulunamadı.');
      final b = req.bodyMap;
      if (b['role'] is String) {
        final r = UserRole.fromApi(b['role'] as String);
        if (r == null) return _invalid();
        t['role'] = r.api;
      }
      if (b['active'] is bool) t['active'] = b['active'];
      if (b['name'] is String && (b['name'] as String).trim().isNotEmpty) {
        t['name'] = (b['name'] as String).trim();
      }
      return DemoResponse.json(pub(t));
    }),
    DemoRoute('DELETE', '/users/:id', (req) {
      if (!manage(req)) return _forbidden();
      final t = find(req.params['id']);
      if (t == null) return DemoResponse.error(404, 'Kullanıcı bulunamadı.');
      if (t['id'] == selfId(req)) {
        return _invalid('Kendi hesabınızı silemezsiniz.');
      }
      if (!inScope(req, t)) return _forbidden();
      users.remove(t);
      return DemoResponse.json({'message': 'Kullanıcı silindi.'});
    }),
  ];
}
