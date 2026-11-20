import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/health_service.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/auth/session.dart';
import 'package:xc_asistan/core/router/redirect.dart';
import 'package:xc_asistan/core/router/routes.dart';

SessionAuthenticated authed(UserRole r) => SessionAuthenticated(
  MeResponse.fromUser(AuthUser(id: '1', name: 'n', email: 'e@x.com', role: r)),
);

String? r(
  SessionState s,
  String loc, {
  UpdateRequirement u = UpdateRequirement.none,
}) => computeRedirect(session: s, uri: Uri.parse(loc), update: u);

void main() {
  test(
    'açılışta her yol /splash\'a gider (derin bağlantı from ile korunur)',
    () {
      expect(r(const SessionBooting(), '/today'), '/splash');
      expect(
        r(const SessionBooting(), '/jobs/offers/5'),
        '/splash?from=${Uri.encodeComponent('/jobs/offers/5')}',
      );
      expect(r(const SessionBooting(), '/splash'), isNull);
      expect(r(const SessionBootFailed('x'), '/login'), '/splash');
    },
  );

  test('splash\'taki from girişe taşınır', () {
    final splash = '/splash?from=${Uri.encodeComponent('/jobs/offers/5')}';
    expect(
      r(const SessionUnauthenticated(), splash),
      '/login?from=${Uri.encodeComponent('/jobs/offers/5')}',
    );
    expect(r(authed(UserRole.admin), splash), '/jobs/offers/5');
  });

  test('girişsiz → /login (from ile)', () {
    expect(r(const SessionUnauthenticated(), '/today'), '/login');
    expect(
      r(const SessionUnauthenticated(), '/customers/0532'),
      '/login?from=${Uri.encodeComponent('/customers/0532')}',
    );
    expect(r(const SessionUnauthenticated(), '/login'), isNull);
  });

  test('oturum açık: /login ve /splash → from ya da /today', () {
    final a = authed(UserRole.admin);
    expect(r(a, '/login'), '/today');
    expect(r(a, '/splash'), '/today');
    expect(
      r(a, '/login?from=${Uri.encodeComponent('/jobs/offers/5')}'),
      '/jobs/offers/5',
    );
    // güvensiz from yok sayılır
    expect(r(a, '/login?from=${Uri.encodeComponent('//evil.com')}'), '/today');
    expect(
      r(a, '/login?from=${Uri.encodeComponent('https://evil.com')}'),
      '/today',
    );
    expect(r(a, '/login?from=${Uri.encodeComponent('/login')}'), '/today');
    expect(r(a, '/jobs'), isNull);
  });

  test('rol korumaları: saha finans/müşteri/işler/asistan/stok/rapor yollarına giremez', () {
    final s = authed(UserRole.saha);
    for (final p in [
      '/jobs',
      '/jobs/offers/1',
      '/customers',
      '/finance',
      '/assistant',
      '/assistant/share',
      '/stock',
      '/reports',
      '/invoices-vat',
    ]) {
      expect(r(s, p), Routes.today, reason: p);
    }
    for (final p in [
      '/today',
      '/appointments',
      '/appointments/7',
      '/settings',
      '/more',
    ]) {
      expect(r(s, p), isNull, reason: p);
    }
  });

  test('personel: müşteri ve fatura yok; finans var', () {
    final s = authed(UserRole.personel);
    expect(r(s, '/customers'), Routes.today);
    expect(r(s, '/invoices-vat'), Routes.today);
    expect(r(s, '/finance'), isNull);
    expect(r(s, '/jobs/projects/3'), isNull);
  });

  test('admin her yere girebilir', () {
    final s = authed(UserRole.admin);
    for (final p in [
      '/jobs',
      '/customers',
      '/finance',
      '/stock',
      '/reports',
      '/invoices-vat',
      '/assistant/share',
    ]) {
      expect(r(s, p), isNull, reason: p);
    }
  });

  test('zorunlu güncelleme kancası', () {
    final s = authed(UserRole.admin);
    const need = UpdateRequirement(isRequired: true, minVersion: '2.0.0');
    expect(r(s, '/today', u: need), Routes.updateRequired);
    expect(r(s, '/update-required', u: need), isNull);
    expect(r(s, '/update-required'), Routes.today);
    // pasif iken (varsayılan) hiçbir etkisi yok
    expect(r(s, '/today'), isNull);
  });

  test('sürüm karşılaştırma', () {
    expect(compareVersions('0.1.0', '0.2.0') < 0, isTrue);
    expect(compareVersions('1.10.0', '1.9.9') > 0, isTrue);
    expect(compareVersions('1.0.0+5', '1.0.0'), 0);
    expect(compareVersions('1.0', '1.0.1') < 0, isTrue);
  });
}
