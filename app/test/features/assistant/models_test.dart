import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/features/assistant/data/briefing_models.dart';
import 'package:xc_asistan/features/assistant/data/closure_models.dart';
import 'package:xc_asistan/features/assistant/data/command_models.dart';
import 'package:xc_asistan/features/assistant/data/import_models.dart';
import 'package:xc_asistan/features/assistant/data/inbox_models.dart';
import 'package:xc_asistan/features/assistant/data/insight_models.dart';
import 'package:xc_asistan/features/assistant/data/model_utils.dart';

void main() {
  group('komut yanıtları', () {
    test('answer: metin, veri ve öneri çipleri', () {
      final r = AssistantReply.fromJson({
        'kind': 'answer',
        'intent': 'query.agenda',
        'text': 'Bugün 3 randevu var.',
        'data': {'count': 3},
        'chips': ['Bu ay ne kadar tahsilat?'],
      });
      expect(r.kind, ReplyKind.answer);
      expect(r.text, 'Bugün 3 randevu var.');
      expect(r.chips, ['Bu ay ne kadar tahsilat?']);
      expect(r.isUnknown, isFalse);
    });

    test('anlaşılmayan komut: intent unknown', () {
      final r = AssistantReply.fromJson({
        'kind': 'answer',
        'intent': 'unknown',
        'text': 'Anlayamadım',
      });
      expect(r.isUnknown, isTrue);
    });

    test('action_card: alanlar ve durum', () {
      final r = AssistantReply.fromJson({
        'kind': 'action_card',
        'action': {
          'id': 'c1',
          'intent': 'payment.add',
          'status': 'onerildi',
          'summary': 'Ödeme: Ahmet · ₺5.000,00',
          'fields': [
            {
              'key': 'amount',
              'label': 'Tutar',
              'type': 'money',
              'value': 5000,
              'display': '₺5.000,00',
              'editable': true,
            },
          ],
        },
      });
      expect(r.kind, ReplyKind.actionCard);
      final c = r.card!;
      expect(c.id, 'c1');
      expect(c.isPending, isTrue);
      expect(c.hasEditable, isTrue);
      expect(c.status, CardStatus.onerildi);
    });

    test('clarify: sorular ve seçenekler', () {
      final r = AssistantReply.fromJson({
        'kind': 'clarify',
        'message': 'Hangisi?',
        'questions': [
          {
            'field': 'customer_key',
            'type': 'choice',
            'label': 'Müşteri',
            'options': [
              {'value': 'a', 'label': 'Ahmet Yılmaz'},
              {'value': 'b', 'label': 'Ahmet Kaya'},
            ],
          },
        ],
      });
      expect(r.kind, ReplyKind.clarify);
      expect(r.questions.single.options.map((o) => o.label), [
        'Ahmet Yılmaz',
        'Ahmet Kaya',
      ]);
    });

    test('bilinmeyen kart durumu çökmez', () {
      expect(CardStatus.fromApi('uzaylı'), isNotNull);
      expect(CardStatus.fromApi(null), isNotNull);
      expect(CardStatus.uygulandi.isFinal, isTrue);
      expect(CardStatus.onerildi.isFinal, isFalse);
    });

    test('eksik alanlarla boş yanıt', () {
      final r = AssistantReply.fromJson(const {});
      expect(r.text, isA<String>());
      expect(r.chips, isEmpty);
    });
  });

  group('yardımcılar', () {
    test('müşteri anahtarı son 10 hane', () {
      expect(assistantCustomerKey('+90 532 111 00 00'), '5321110000');
      expect(assistantCustomerKey('905321110000'), '5321110000');
      expect(assistantCustomerKey('5321110000'), '5321110000');
    });

    test('/api öneki atılır', () {
      expect(relativeApiPath('/api/customers/5'), '/customers/5');
      expect(relativeApiPath('/customers/5'), '/customers/5');
    });

    test('yer tutucu algılanır', () {
      expect(hasPlaceholder('/x/<id>'), isTrue);
      expect(hasPlaceholder('/x/1'), isFalse);
    });
  });

  group('brifing', () {
    final json = {
      'id': 'b1',
      'kind': 'morning',
      'title': 'Günaydın',
      'text': 'Özet',
      'date': '2026-11-20',
      'data': {
        'stats': {'appointments': 3, 'overdue_collections': 1},
        'blocks': [
          {'type': 'appointments', 'title': 'Randevular', 'items': []},
          {'type': 'money', 'title': 'Para', 'text': 'x'},
          {'type': 'zaman_makinesi', 'title': '?'},
        ],
      },
    };
    test('bilinmeyen blok türü yok sayılır', () {
      final b = Briefing.fromJson(json);
      expect(b.kind, BriefingKind.morning);
      expect(b.stats.appointments, 3);
      expect(b.blocks.map((x) => x.type), ['appointments', 'money']);
    });
    test('boş veri çökmez', () {
      final b = Briefing.fromJson(const {'id': 'x'});
      expect(b.blocks, isEmpty);
      expect(b.title, isA<String>());
    });
  });

  group('müdür', () {
    final j = {
      'id': 'i1',
      'rule_key': 'tahsilat_gecikmesi',
      'severity': 'warn',
      'title': 'Tahsilat gecikmesi',
      'status': 'acik',
      'evidence': {
        'metrics': [
          {
            'key': 'balance',
            'label': 'Kalan bakiye',
            'value': 1245055,
            'unit': 'kurus',
            'display': '₺12.450,55',
          },
        ],
      },
      'actions': [
        {'type': 'call', 'label': 'Ara', 'phone': '5321110000'},
        {'type': 'zaman_makinesi', 'label': 'Bilinmeyen'},
      ],
    };
    test('kanıt, etiket ve bilinmeyen eylem', () {
      final i = Insight.fromJson(j);
      expect(i.evidence.metrics.single.display, '₺12.450,55');
      expect(i.actions.length, 1);
      expect(i.tag, InsightTag.warning);
    });
    test('geri bildirim kopyası', () {
      final i = Insight.fromJson(j).withFeedback('yararli');
      expect(i.id, 'i1');
    });
    test('bağımlı kural gizlenir', () {
      final cfg = InsightRulesConfig.fromJson({
        'rules': [
          {
            'rule_key': 'a',
            'title': 'A',
            'status': 'aktif',
            'enabled': true,
            'params': {'gun': 7},
          },
          {
            'rule_key': 'b',
            'title': 'B',
            'status': 'bagimli',
            'enabled': false,
            'params': {},
          },
        ],
      });
      expect(cfg.rules.length, 2);
      expect(cfg.visible.map((r) => r.key), ['a']);
    });
  });

  group('kapanış', () {
    test('tutar gerektiren seçim', () {
      final q = ClosureQuestion.fromJson({
        'id': 'money',
        'kind': 'money',
        'text': 'Tahsilat?',
        'options': [
          {'value': 'yok', 'label': 'Yok'},
          {'value': 'tahsilat', 'label': '+ Tahsilat'},
        ],
      });
      expect(q.needsAmount('tahsilat'), isTrue);
      expect(q.needsAmount('yok'), isFalse);
    });
  });

  group('tercihler ve gelen kutusu', () {
    test('saat biçimi', () {
      expect(AssistantPrefs.parseTime('08:30'), (hour: 8, minute: 30));
      expect(AssistantPrefs.formatTime(7, 5), '07:05');
    });
    test('sessiz saat gece yarısını aşar', () {
      final p = AssistantPrefs.fromJson({
        'quiet_start': '22:00',
        'quiet_end': '07:00',
      });
      expect(p.isQuiet(23, 0), isTrue);
      expect(p.isQuiet(3, 0), isTrue);
      expect(p.isQuiet(12, 0), isFalse);
    });
    test('boş gelen kutusu', () {
      final p = InboxPage.fromJson(const {});
      expect(p.items, isEmpty);
      expect(p.unreadCount, 0);
    });
  });

  group('yazışma içe aktarma', () {
    test('öneri türleri', () {
      expect(SuggestionKind.fromApi('randevu'), SuggestionKind.appointment);
      expect(SuggestionKind.fromApi('hatirlatma'), SuggestionKind.reminder);
      expect(SuggestionKind.fromApi('x'), SuggestionKind.unknown);
    });
    test('öneri kaynak mesajı', () {
      final s = Suggestion.fromJson({
        'id': 's1',
        'kind': 'not',
        'status': 'beklemede',
        'text': 'Balkon 3,2 m',
        'fields': {'text': 'Balkon 3,2 m'},
        'source': {'sender': 'Ahmet', 'text': 'balkon 3,2 olacak'},
      });
      expect(s.isPending, isTrue);
      expect(s.sourceText, 'balkon 3,2 olacak');
      expect(s.fields['text'], 'Balkon 3,2 m');
    });
    test('randevu kabulü kart döndürür', () {
      final d = SuggestionDecision.fromJson({
        'suggestion': {
          'id': 's3',
          'kind': 'randevu',
          'status': 'kabul',
          'text': 'x',
        },
        'action': {
          'id': 'c9',
          'status': 'onerildi',
          'summary': 'Randevu',
          'fields': [],
        },
      });
      expect(d.card?.id, 'c9');
      expect(d.suggestion?.status, 'kabul');
    });
  });
}
