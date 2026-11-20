// İşler listesi: kart içi aşama ilerletme / geri alma / hata / yetki / onay / sayaçlar / taşma.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/api/api_client.dart' show Paged;
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/core/util/domain_enums.dart';
import 'package:xc_asistan/features/jobs/data/jobs_access.dart';
import 'package:xc_asistan/features/jobs/data/jobs_project_models.dart';
import 'package:xc_asistan/features/jobs/data/jobs_repository.dart';
import 'package:xc_asistan/features/jobs/presentation/jobs_screen.dart';

import '../../helpers/app_harness.dart';

class _Repo implements JobsRepository {
  _Repo(this.projects_);
  final List<Project> projects_;
  final calls = <(String, ProjectStage)>[];
  bool fail = false;

  @override
  Future<Paged<Project>> projects({
    String? q,
    int limit = 30,
    int offset = 0,
  }) async => Paged(projects_, projects_.length);

  @override
  Future<void> setStage(String id, ProjectStage stage) async {
    calls.add((id, stage));
    if (fail) {
      throw const AppException(AppErrorCode.server, 'Sunucu hatası oldu.');
    }
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoStageAccess extends JobsAccess {
  const _NoStageAccess(super.caps);
  @override
  bool get canChangeStage => false;
}

Project _p(String id, String stage, {String? name}) => Project(
  id: id,
  code: 'PRJ-$id',
  customerName: name ?? 'Müşteri $id',
  service: 'Çelik kapı',
  stage: stage,
);

Future<_Repo> _pump(
  WidgetTester t, {
  UserRole role = UserRole.admin,
  bool stageAllowed = true,
  Size size = const Size(1500, 2400),
  double textScale = 1.0,
  List<Project>? items,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final repo = _Repo(
    items ??
        [
          _p('1', 'Malzeme Temini'),
          _p('2', 'Üretim'),
          _p(
            '3',
            'Üretim',
            name: 'Çok uzun bir müşteri adı soyadı limited şirketi',
          ),
          _p('4', 'Teslim'),
          _p('5', 'Tamamlandı'),
        ],
  );
  final caps = AppCapabilities.forRole(role);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        jobsRepositoryProvider.overrideWithValue(repo),
        jobsAccessProvider.overrideWithValue(
          stageAllowed ? JobsAccess(caps) : _NoStageAccess(caps),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: w!,
        ),
        home: const Scaffold(body: ProjectsTab()),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  return repo;
}

Finder _next(String label) =>
    find.widgetWithText(FilledButton, 'Sonraki aşama: $label');
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'ilerlet: anında güncellenir, Aşama: X + Geri al, sayaçlar değişir',
    (t) async {
      final repo = await _pump(t);
      expect(find.text('Malzeme Temini (1)'), findsOneWidget);
      expect(find.text('Üretim (2)'), findsOneWidget);
      expect(find.text('Tamamlandı (1)'), findsOneWidget);
      expect(find.text('Tümü (5)'), findsOneWidget);
      // Tamamlandı kartında "Sonraki aşama" yok: 4 düğme.
      expect(find.textContaining('Sonraki aşama'), findsNWidgets(4));

      await t.tap(_next('Üretim'));
      await _settle(t);
      expect(repo.calls, [('1', ProjectStage.uretim)]);
      expect(find.text('Aşama: Üretim'), findsOneWidget);
      expect(find.text('Malzeme Temini (0)'), findsOneWidget);
      expect(find.text('Üretim (3)'), findsOneWidget);
      expect(_next('Montaj'), findsNWidgets(3));

      await t.tap(find.text('Geri al'));
      await _settle(t);
      expect(repo.calls.last, ('1', ProjectStage.malzemeTemini));
      expect(find.text('Malzeme Temini (1)'), findsOneWidget);
      expect(find.text('Üretim (2)'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('hata: eski değere döner ve mesaj gösterir', (t) async {
    final repo = await _pump(t)
      ..fail = true;
    await t.tap(_next('Üretim'));
    await _settle(t);
    expect(find.text('Sunucu hatası oldu.'), findsOneWidget);
    expect(find.text('Malzeme Temini (1)'), findsOneWidget);
    expect(find.text('Üretim (2)'), findsOneWidget);
    expect(find.text('Geri al'), findsNothing);
    expect(repo.calls.length, 1);
  });

  testWidgets('çip → alt sayfa: herhangi bir aşamaya geçiş (geri alma dahil)', (
    t,
  ) async {
    final repo = await _pump(t);
    // 4 numaralı kart (Teslim): çip dokun → sayfa → Malzeme Temini'ne geri.
    await t.tap(
      find.descendant(
        of: find.byType(Card).at(3),
        matching: find.byIcon(Icons.arrow_drop_down),
      ),
    );
    await _settle(t);
    expect(find.text('Aşamayı değiştir'), findsOneWidget);
    for (final s in ProjectStage.values) {
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text(s.label),
        ),
        findsOneWidget,
      );
    }
    await t.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Malzeme Temini'),
      ),
    );
    await _settle(t);
    expect(repo.calls, [('4', ProjectStage.malzemeTemini)]);
    expect(find.text('Malzeme Temini (2)'), findsOneWidget);
    expect(find.text('Teslim (0)'), findsOneWidget);
  });

  testWidgets('Tamamlandı\'ya geçerken onay sorulur; vazgeçince değişmez', (
    t,
  ) async {
    final repo = await _pump(t);
    await t.tap(_next('Tamamlandı'));
    await _settle(t);
    expect(find.text('İş tamamlandı mı?'), findsOneWidget);
    await t.tap(find.text('Vazgeç'));
    await _settle(t);
    expect(repo.calls, isEmpty);
    expect(find.text('Teslim (1)'), findsOneWidget);

    await t.tap(_next('Tamamlandı'));
    await _settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Tamamlandı'));
    await _settle(t);
    expect(repo.calls, [('4', ProjectStage.tamamlandi)]);
    expect(find.text('Tamamlandı (2)'), findsOneWidget);
  });

  testWidgets(
    'saha: detaydaki gibi aşama değiştirebilir; yetki yoksa düğme/çip yok',
    (t) async {
      expect(
        JobsAccess(AppCapabilities.forRole(UserRole.saha)).canChangeStage,
        true,
      );
      await _pump(t, role: UserRole.saha);
      expect(find.textContaining('Sonraki aşama'), findsNWidgets(4));

      await _pump(t, stageAllowed: false);
      expect(find.textContaining('Sonraki aşama'), findsNothing);
      expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
    },
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('360dp, yazı x$scale: taşma yok, dokunma hedefi >=48dp', (
      t,
    ) async {
      await _pump(t, textScale: scale, size: const Size(360, 2400));
      expect(t.takeException(), isNull);
      for (final f in [_next('Üretim'), _next('Montaj')]) {
        final s = t.getSize(f.first);
        expect(s.height >= 48, true, reason: '${s.height}');
      }
      final inkTap = find
          .ancestor(
            of: find.byIcon(Icons.arrow_drop_down).first,
            matching: find.byType(InkWell),
          )
          .first;
      expect(t.getSize(inkTap).height >= 48, true);
      // Alt sayfa da taşmaz.
      await t.tap(find.byIcon(Icons.arrow_drop_down).first);
      await _settle(t);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'DEMO: /projects/:id/stage çalışır (listeden ilerlet → Aşama: X + Geri al)',
    (t) async {
      final h = await pumpXcApp(t, role: 'admin', initialLocation: '/jobs');
      await t.tap(find.textContaining('İşler ('));
      await h.settle(20);
      expect(find.textContaining('Sonraki aşama'), findsWidgets);
      await t.ensureVisible(find.textContaining('Sonraki aşama').first);
      final before = find.textContaining('Sonraki aşama: ').evaluate().length;
      await t.tap(find.textContaining('Sonraki aşama').first);
      await h.settle(20);
      expect(find.textContaining('Aşama: '), findsOneWidget);
      expect(find.text('Geri al'), findsOneWidget);
      expect(before, greaterThan(0));
      expect(t.takeException(), isNull);
    },
  );
}
