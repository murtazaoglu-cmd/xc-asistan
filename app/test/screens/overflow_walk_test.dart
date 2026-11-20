// DEMO modunda tüm ana ekranları 360x800 (telefon), 1024x768, 1280x800 ve 1440x900 (web paneli) yüzeyde gezer:
// RenderFlex taşması ve başka çizim/yerleşim istisnası OLMAMALI. Her rota için hata ayrı raporlanır.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';

/// Rol → gezilecek rotalar (DEMO kimlikleri: off-1, prj-1, 05321112233, apt-1, mat-1, rec-1).
const _managerRoutes = <String>[
  '/today',
  '/jobs',
  '/jobs/offers/off-1',
  '/jobs/projects/prj-1',
  '/jobs/offers/new',
  '/jobs/projects/new',
  '/assistant',
  '/assistant/briefing',
  '/assistant/briefing/history?type=weekly',
  '/assistant/insights',
  '/assistant/insights/rules',
  '/assistant/closure',
  '/assistant/inbox',
  '/assistant/prefs',
  '/assistant/consents',
  '/assistant/suggestions',
  '/assistant/share',
  '/customers',
  '/customers/new',
  '/customers/05321112233',
  '/finance',
  '/finance/receivables',
  '/finance/payments/new',
  '/finance/expenses/new',
  '/finance/recurring/new',
  '/appointments',
  '/appointments/new',
  '/appointments/apt-1',
  '/stock',
  '/stock/new',
  '/stock/mat-1',
  '/reports',
  '/invoices-vat',
  '/invoices-vat?tab=1',
  '/invoices-vat?tab=2',
  '/invoices-vat?tab=3',
  '/invoices-vat/new',
  '/invoices-vat/plan/new',
  '/settings',
  '/settings/password',
  '/users',
  '/users/new',
  '/more',
];

const _fieldRoutes = <String>[
  '/today',
  '/appointments',
  '/appointments/apt-1',
  '/assistant/briefing',
  '/assistant/closure',
  '/assistant/inbox',
  '/assistant/prefs',
  '/settings',
  '/settings/password',
  '/more',
];

void main() {
  const sizes = {
    'telefon 360x800': Size(360, 800),
    'dizüstü 1024x768 (tek bölme + sol menü)': Size(1024, 768),
    'geniş 1280x800 (ana-ayrıntı)': Size(1280, 800),
    'web 1440x900 (ana-ayrıntı, 3 sütun)': Size(1440, 900),
  };
  const roles = {
    'admin': _managerRoutes,
    'personel': _managerRoutes,
    'muhasebe': _managerRoutes,
    'saha': _fieldRoutes,
  };

  for (final size in sizes.entries) {
    for (final role in roles.entries) {
      testWidgets('${role.key} / ${size.key}: taşma ve istisna yok', (
        tester,
      ) async {
        final h = await pumpXcApp(
          tester,
          role: role.key,
          logicalSize: size.value,
        );
        final problems = <String>[];
        String current = '/today';
        final original = FlutterError.onError;
        FlutterError.onError = (d) {
          final msg = d.exceptionAsString().split('\n').first;
          problems.add('[$current] $msg');
        };
        try {
          for (final route in role.value) {
            current = route;
            await h.go(route);
            await h.settle(8);
          }
        } finally {
          FlutterError.onError = original;
        }
        expect(problems, isEmpty, reason: problems.take(20).join('\n'));
      });
    }
  }
}
