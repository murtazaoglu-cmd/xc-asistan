import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/assistant/application/access.dart';
import 'package:xc_asistan/features/assistant/application/assistant_providers.dart';
import 'package:xc_asistan/features/assistant/application/closure_flow.dart';
import 'package:xc_asistan/features/assistant/application/import_flow.dart';
import 'package:xc_asistan/features/assistant/application/notification_scheduler.dart';
import 'package:xc_asistan/features/assistant/data/briefing_models.dart';
import 'package:xc_asistan/features/assistant/data/closure_models.dart';
import 'package:xc_asistan/features/assistant/data/import_models.dart';
import 'package:xc_asistan/features/assistant/data/inbox_models.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

ClosureState _closure() => ClosureState.fromJson({
  'date': '2026-11-20',
  'status': 'pending',
  'questions': [
    {
      'id': 'appt1',
      'kind': 'appointment',
      'text': 'Ahmet nasıl geçti?',
      'options': [
        {'value': 'yapildi', 'label': 'Yapıldı'},
        {'value': 'iptal', 'label': 'İptal'},
      ],
    },
    {
      'id': 'money',
      'kind': 'money',
      'text': 'Tahsilat ya da gider?',
      'options': [
        {'value': 'yok', 'label': 'Yok'},
        {'value': 'tahsilat', 'label': '+ Tahsilat'},
      ],
    },
  ],
});

void main() {
  group('gün sonu sihirbazı (ClosureDraft)', () {
    test('tek dokunuşla ilerler, geri gider, atlar', () {
      var d = ClosureDraft.from(_closure());
      expect(d.total, 2);
      expect(d.current!.id, 'appt1');
      d = d.answer('yapildi');
      expect(d.current!.id, 'money');
      expect(d.canGoBack, isTrue);
      d = d.back();
      expect(d.current!.id, 'appt1');
      d = d.answer('yapildi').skip();
      expect(d.atNoteStep, isTrue);
      expect(d.payload.length, 2);
      expect(d.payload.last.toJson()['skipped'], true);
    });

    test('para sorusunda tutar zorunlu ve pozitif olmalı', () {
      var d = ClosureDraft.from(_closure()).answer('yapildi');
      expect(() => d.answer('tahsilat'), throwsArgumentError);
      expect(
        () => d.answer('tahsilat', amount: Money.fromKurus(0)),
        throwsArgumentError,
      );
      d = d.answer('tahsilat', amount: Money.fromKurus(250000));
      expect(d.payload.last.toJson()['amount_kurus'], 250000);
    });

    test('yok cevabı tutar istemez', () {
      final d = ClosureDraft.from(_closure()).answer('yapildi').answer('yok');
      expect(d.payload.last.toJson().containsKey('amount_kurus'), isFalse);
    });
  });

  group('gün sonu akışı (sunucu ile)', () {
    test('gönder → öneriler → uygula/geç', () async {
      final c = containerFor(await assistantOverrides());
      c.listen(closureFlowProvider, (_, _) {});
      c.listen(closureProvider, (_, _) {});
      final state = await c.read(closureProvider.future);
      final n = c.read(closureFlowProvider.notifier);
      n.start(state);
      while (c.read(closureFlowProvider).draft!.current != null) {
        final q = c.read(closureFlowProvider).draft!.current!;
        if (q.isMoney) {
          n.answer('yok');
        } else {
          n.answer(q.options.first.value);
        }
      }
      n.freeNote('Yarın erken çıkış');
      final ok = await n.submit();
      expect(ok, isTrue);
      final f = c.read(closureFlowProvider);
      expect(f.submitted, isTrue);
      expect(f.error, isNull);
      if (f.result!.proposals.isNotEmpty) {
        n.skipProposal(0);
        expect(
          c.read(closureFlowProvider).proposalStatus[0],
          ProposalStatus.skipped,
        );
      }
    });
  });

  group('rol görünürlüğü', () {
    Briefing full() => Briefing.fromJson({
      'id': 'b',
      'kind': 'morning',
      'data': {
        'blocks': [
          {'type': 'appointments', 'title': 'Randevu'},
          {'type': 'money', 'title': 'Para'},
          {'type': 'collections', 'title': 'Tahsilat'},
          {'type': 'new_requests', 'title': 'Talep'},
          {'type': 'low_stock', 'title': 'Stok'},
          {'type': 'question', 'title': 'Soru'},
          {'type': 'reminders', 'title': 'Hatırlatma'},
        ],
      },
    });

    List<String> types(UserRole r) =>
        visibleBlocks(full(), AssistantAccess(r)).map((b) => b.type).toList();

    test('saha: para, tahsilat, teklif, stok ve soru YOK', () {
      expect(types(UserRole.saha), ['appointments', 'reminders']);
    });
    test('personel: para ve tahsilat YOK', () {
      final t = types(UserRole.personel);
      expect(t, isNot(contains('money')));
      expect(t, isNot(contains('collections')));
      expect(t, contains('appointments'));
    });
    test('admin: hepsi', () {
      expect(types(UserRole.admin).length, 7);
    });
    test('yetki matrisi', () {
      expect(const AssistantAccess(UserRole.saha).showManager, isFalse);
      expect(const AssistantAccess(UserRole.personel).showManager, isFalse);
      expect(const AssistantAccess(UserRole.muhasebe).showManager, isTrue);
      expect(const AssistantAccess(UserRole.ortak).showFinance, isTrue);
      expect(const AssistantAccess(UserRole.admin).canEditRules, isTrue);
      expect(const AssistantAccess(UserRole.muhasebe).canEditRules, isFalse);
      expect(const AssistantAccess(UserRole.saha).canImport, isFalse);
    });
  });

  group('yazışma içe aktarma akışı', () {
    test('paylaşım → rıza → önizleme → onay → öneriler', () async {
      final c = containerFor(await assistantOverrides());
      final n = c.read(importFlowProvider.notifier);
      await n.begin(
        const ImportSource(text: '[12.11.2026 10:00] Ahmet: Merhaba'),
      );
      var f = c.read(importFlowProvider);
      expect(f.phase, ImportPhase.consent);
      expect(f.notice, isNotNull);

      // Rıza olmadan yüklenmez.
      expect(await n.upload(), isFalse);
      n.toggleConsent(true);
      expect(await n.upload(), isTrue);
      f = c.read(importFlowProvider);
      expect(f.phase, ImportPhase.preview);
      expect(f.preview!.messageCount, greaterThan(0));
      expect(f.preview!.participants, isNotEmpty);

      n.setOwner(f.preview!.participants.last);
      if (f.needsCustomerMatch) n.noCustomer();
      expect(await n.confirm(), isTrue);
      f = c.read(importFlowProvider);
      expect(f.phase, ImportPhase.done);
      expect(f.result!.suggestionsCreated, greaterThan(0));

      final sq = (conversationId: f.result!.conversationId, customerKey: null);
      c.listen(suggestionsProvider(sq), (_, _) {});
      final items = await c.read(suggestionsProvider(sq).future);
      expect(items, isNotEmpty);
      expect(items.every((s) => s.isPending), isTrue);
      expect(
        items.any((s) => s.sourceText != null && s.sourceText!.isNotEmpty),
        isTrue,
      );
    });

    test(
      'randevu önerisi kabulü onay kartı döndürür; öneri listeden çıkar',
      () async {
        final c = containerFor(await assistantOverrides());
        const q = (conversationId: null, customerKey: null);
        c.listen(suggestionsProvider(q), (_, _) {});
        final items = await c.read(suggestionsProvider(q).future);
        final appt = items.firstWhere(
          (s) => s.kind == SuggestionKind.appointment,
        );
        final d = await c
            .read(suggestionsProvider(q).notifier)
            .decide(appt.id, 'kabul');
        expect(d.card, isNotNull);
        expect(
          (await c.read(suggestionsProvider(q).future))
              .any((s) => s.id == appt.id),
          isFalse,
        );
      },
    );

    test('vazgeç: akış sıfırlanır', () async {
      final c = containerFor(await assistantOverrides());
      final n = c.read(importFlowProvider.notifier);
      await n.begin(const ImportSource(text: 'x'));
      n.reset();
      expect(c.read(importFlowProvider).phase, ImportPhase.idle);
    });
  });

  group('bildirim planlayıcı', () {
    final now = Ist.fromWall(2026, 11, 20, 12, 0); // Cuma 12:00

    test('varsayılan: Pzt–Cmt, pazar yok; geçmiş anlar yok', () {
      final fires = NotificationPlanner.oneOffs(const AssistantPrefs(), now);
      expect(fires.every((f) => f.when.isAfter(now)), isTrue);
      expect(
        fires.any((f) => Ist.wall(f.when).weekday == DateTime.sunday),
        isFalse,
      );
      // Bugünkü sabah 07:30 geçti; bugünkü akşam 18:30 var.
      expect(fires.first.morning, isFalse);
    });

    test('kapalıysa hiçbir şey planlanmaz', () {
      expect(
        NotificationPlanner.oneOffs(const AssistantPrefs(enabled: false), now),
        isEmpty,
      );
    });

    test('sessiz saate düşen zaman atlanır', () {
      const p = AssistantPrefs(
        morningTime: '06:30',
        quietStart: '21:30',
        quietEnd: '07:00',
      );
      final fires = NotificationPlanner.oneOffs(p, now);
      expect(fires.where((f) => f.morning), isEmpty);
    });

    test('tüm hafta açıksa günlük tekrar yeterli', () {
      expect(
        NotificationPlanner.coversWholeWeek(
          const AssistantPrefs(weekdays: [1, 2, 3, 4, 5, 6, 7]),
        ),
        isTrue,
      );
      expect(
        NotificationPlanner.coversWholeWeek(const AssistantPrefs()),
        isFalse,
      );
    });
  });

  group('bildirim metinleri', () {
    final b = Briefing.fromJson({
      'id': 'b',
      'kind': 'morning',
      'title': 'Günaydın',
      'data': {
        'stats': {
          'appointments': 3,
          'late_collections': 2,
          'tomorrow_appointments': 1,
        },
        'blocks': [],
      },
    });

    test('veri yoksa genel metin', () {
      final t = AssistantNotificationTexts.morning(
        null,
        fireToday: true,
        access: const AssistantAccess(UserRole.admin),
      );
      expect(t.title, AssistantNotificationTexts.genericMorning.title);
      expect(
        AssistantNotificationTexts.evening(null).title,
        AssistantNotificationTexts.genericEvening.title,
      );
    });

    test('bugün: randevu sayısı; finans yalnız yetkiliye', () {
      final admin = AssistantNotificationTexts.morning(
        b,
        fireToday: true,
        access: const AssistantAccess(UserRole.admin),
      );
      expect(admin.body, contains('3 randevu'));
      expect(admin.body, contains('geciken tahsilat'));
      final saha = AssistantNotificationTexts.morning(
        b,
        fireToday: true,
        access: const AssistantAccess(UserRole.saha),
      );
      expect(saha.body, contains('3 randevu'));
      expect(saha.body, isNot(contains('tahsilat')));
    });

    test('yarına kurulan bildirimde bayat sayı yok', () {
      final t = AssistantNotificationTexts.morning(
        b,
        fireToday: false,
        access: const AssistantAccess(UserRole.admin),
      );
      expect(t.body, contains('1 randevunuz'));
      expect(t.body, isNot(contains('3 randevu')));
    });
  });

  test(
    'zamanlayıcı: tüm hafta açıkken günlük sabah ve akşam kurulur',
    () async {
      final gw = FakeNotificationsGateway();
      final c = containerFor(await assistantOverrides(gateway: gw));
      await c
          .read(assistantNotificationSchedulerProvider)
          .apply(now: Ist.fromWall(2026, 11, 20, 12, 0));
      expect(gw.log, isNotEmpty);
    },
  );
}
