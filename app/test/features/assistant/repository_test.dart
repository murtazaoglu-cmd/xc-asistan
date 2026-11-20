import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/assistant/data/assistant_repository.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/assistant/data/closure_models.dart';
import 'package:xc_asistan/features/assistant/data/command_models.dart';

import '../../helpers/fakes.dart';
import 'harness.dart' as h;

HttpAssistantRepository _scripted(ScriptedAdapter a) =>
    HttpAssistantRepository(h.apiWith(a));

void main() {
  group('komutlar', () {
    test('sendCommand: metin ve seçimler gövdede', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {'kind': 'answer', 'text': 'Tamam'}),
      );
      final r = await _scripted(
        a,
      ).sendCommand('Bugün ne var?', choices: {'customer_key': '5321110000'});
      expect(r.text, 'Tamam');
      expect(a.requests.single.method, 'POST');
      expect(a.requests.single.path, '/assistant/commands');
      expect(a.requests.single.data, {
        'text': 'Bugün ne var?',
        'choices': {'customer_key': '5321110000'},
      });
    });

    test('boş seçim gövdeye eklenmez', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {'kind': 'answer'}),
      );
      await _scripted(a).sendCommand('x');
      expect(a.requests.single.data, {'text': 'x'});
    });

    test('onay: Idempotency-Key başlığı gider', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {
          'id': 'c1',
          'status': 'uygulandi',
          'summary': 'x',
          'fields': [],
        }),
      );
      final c = await _scripted(a).confirmAction('c1');
      expect(c.status, CardStatus.uygulandi);
      expect(a.requests.single.path, '/assistant/actions/c1/confirm');
      expect(a.requests.single.headers['Idempotency-Key'], 'act-confirm-c1');
    });
  });

  group('hata eşleme', () {
    for (final t in [
      (409, AppErrorCode.conflict),
      (403, AppErrorCode.forbidden),
      (400, AppErrorCode.validation),
    ]) {
      test('${t.$1} → ${t.$2.name}', () async {
        final a = ScriptedAdapter(
          (i, o) => ScriptedResponse(t.$1, {'error': 'Mesaj ${t.$1}'}),
        );
        await expectLater(
          _scripted(a).confirmAction('c1'),
          throwsA(
            isA<AppException>()
                .having((e) => e.code, 'code', t.$2)
                .having((e) => e.message, 'message', 'Mesaj ${t.$1}'),
          ),
        );
      });
    }

    test('ağ hatası', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse.error(DioExceptionType.connectionError, o),
      );
      await expectLater(
        _scripted(a).briefingToday(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.network,
          ),
        ),
      );
    });
  });

  group('demo uçları sözleşme biçiminde', () {
    test('brifing bugün', () async {
      final b = await h.demoRepo().briefingToday();
      expect(b.blocks, isNotEmpty);
      expect(b.stats.appointments, greaterThan(0));
    });

    test('müdür önerileri: bilinmeyen eylem atılır, kanıt var', () async {
      final list = await h.demoRepo().insights();
      expect(list, isNotEmpty);
      expect(list.any((i) => i.evidence.metrics.isNotEmpty), isTrue);
    });

    test('müdür uçları saha için 403', () async {
      await expectLater(
        h.demoRepo(role: UserRole.saha).insights(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });

    test('kurallar yalnız admin', () async {
      await expectLater(
        h.demoRepo(role: UserRole.muhasebe).insightRules(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
      final cfg = await h.demoRepo().insightRules();
      expect(cfg.rules, isNotEmpty);
    });

    test('kapanış: tutarsız tahsilat yanıtı 400', () async {
      final repo = h.demoRepo();
      await expectLater(
        repo.submitClosure(
          date: '2026-11-20',
          answers: const [
            ClosureAnswer(questionId: 'money', choice: 'tahsilat'),
          ],
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.validation,
          ),
        ),
      );
      final ok = await repo.submitClosure(
        date: '2026-11-20',
        answers: [
          ClosureAnswer(
            questionId: 'money',
            choice: 'tahsilat',
            amount: Money.fromKurus(500000),
          ),
        ],
        finish: true,
      );
      expect(ok.applied, isNotEmpty);
    });

    test('tercih saat biçimi geçersizse 400', () async {
      final repo = h.demoRepo();
      await repo.prefs();
      await expectLater(
        repo.updatePrefs({'morning_time': '25:99'}),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.validation,
          ),
        ),
      );
    });

    test('gelen kutusu okunmamış sayısı', () async {
      final repo = h.demoRepo();
      final before = await repo.inboxUnreadCount();
      expect(before, greaterThan(0));
      await repo.markAllInboxRead();
      expect(await repo.inboxUnreadCount(), 0);
    });
  });
}
