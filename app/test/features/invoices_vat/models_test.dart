import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_models.dart';

void main() {
  tearDown(() => Ist.clock = DateTime.now);

  group('Invoice', () {
    test('kuruş alanları birebir okunur; ham UUID başlıkta görünmez', () {
      final i = Invoice.fromJson({
        'id': 'a1b2c3d4-0000-0000-0000-000000000001',
        'direction': 'giden',
        'issue_date': '2026-11-19',
        'invoice_type': 'e-arsiv',
        'invoice_type_label': 'e-Arşiv Fatura',
        'invoice_no': 'FT-024',
        'counterparty': 'Zeynep Arslan',
        'matrah_kurus': 5333333,
        'kdv_oran': 20,
        'kdv_kurus': 1066667,
        'tevkifat_kurus': 426667,
        'tevkifat_oran': '4/10',
        'tutar_kurus': 6400000,
        'odenecek_kurus': 5973333,
        'status': 'gonderildi',
        'overdue': true,
        'files': [
          {
            'id': 'f1',
            'file_name': 'fatura.pdf',
            'file_url': 'https://x/uploads/a.pdf?exp=1&sig=2',
          },
        ],
        'warnings': [
          {'code': 'x', 'message': 'Uyarı metni'},
        ],
      });
      expect(i.matrah, Money.fromKurus(5333333));
      expect(i.kdv.kurus, 1066667);
      expect(i.tevkifat.kurus, 426667);
      expect(i.tutar.kurus, 6400000);
      expect(i.odenecek.kurus, 5973333);
      expect(i.withholding, const Withholding(4, 10));
      expect(i.status, InvoiceStatus.gonderildi);
      expect(i.title, 'FT-024 · Zeynep Arslan');
      expect(i.title.contains('a1b2'), isFalse);
      expect(i.files.single.isPdf, isTrue);
      expect(i.warnings.single.message, 'Uyarı metni');
      expect(i.canMarkPaid, isTrue);
      expect(i.issueDate, Ist.fromWall(2026, 11, 19));
    });

    test('eksik/bozuk alan çökertmez; toplam türetilir', () {
      final i = Invoice.fromJson({
        'id': 'x',
        'matrah_kurus': '1000',
        'kdv_kurus': 200.0,
      });
      expect(i.tutar.kurus, 1200);
      expect(i.odenecek.kurus, 1200);
      expect(i.direction, isNull);
      expect(i.status, isNull);
      expect(i.title, 'Belge');
      expect(i.confirmation.needed, isFalse);
    });

    test('teyit bayrağı: iç içe ve düz biçim, verified=false', () {
      expect(
        Invoice.fromJson({
          'id': '1',
          'confirmation': {
            'needed': true,
            'reasons': ['Oran doğrulanmadı'],
          },
        }).confirmation.reasons,
        ['Oran doğrulanmadı'],
      );
      final flat = Confirmation.fromJson({
        'needs_confirmation': true,
        'confirmation_reasons': ['Tarih'],
      });
      expect(flat.needed, isTrue);
      expect(flat.reasons, ['Tarih']);
      expect(Confirmation.fromJson({'verified': false}).needed, isTrue);
      expect(Confirmation.fromJson({'verified': true}).needed, isFalse);
      expect(Confirmation.fromJson({}).needed, isFalse);
    });

    test('Withholding: dize ve harita çözümlenir', () {
      expect(Withholding.parse('4/10'), const Withholding(4, 10));
      expect(
        Withholding.parse({'pay': 7, 'payda': 10}),
        const Withholding(7, 10),
      );
      expect(Withholding.parse('abc'), isNull);
      expect(const Withholding(11, 10).valid, isFalse);
    });

    test('silinebilirlik: yalnız taslak/iptal', () {
      expect(InvoiceStatus.taslak.deletable, isTrue);
      expect(InvoiceStatus.iptal.deletable, isTrue);
      expect(InvoiceStatus.odendi.deletable, isFalse);
    });
  });

  group('VatRates / VatPeriod', () {
    test('oranlar sunucudan; varsayılan ve teyit bayrağı', () {
      final r = VatRates.fromJson({
        'rates': [
          {'id': 'a', 'rate': 10, 'verified': false},
          {
            'id': 'b',
            'rate': 20,
            'is_default': true,
            'verified': true,
            'label': 'Genel',
          },
        ],
        'withholding_types': [
          {
            'id': 'w',
            'label': 'Yapım 4/10',
            'pay': 4,
            'payda': 10,
            'needs_confirmation': true,
          },
        ],
        'disclaimer': 'Not',
      });
      expect(r.defaultRate!.percent, 20);
      expect(r.byPercent(10)!.confirmation.needed, isTrue);
      expect(r.byPercent(20)!.confirmation.needed, isFalse);
      expect(r.rates.first.percentLabel, '%10');
      expect(r.withholdingTypes.single.ratio, const Withholding(4, 10));
      expect(r.withholdingTypes.single.confirmation.needed, isTrue);
    });

    test('dönem alanları ve oran kırılımı (liste ve harita biçimi)', () {
      final p = VatPeriod.fromJson({
        'period': '2026-11',
        'hesaplanan_kurus': 6400000,
        'indirilecek_kurus': 2850000,
        'onceki_devreden_kurus': 100000,
        'net_kurus': 3450000,
        'odenecek_kurus': 3450000,
        'devreden_kurus': 0,
        'due_date': '2026-12-28',
        'status': 'kilitli',
        'tahmini': true,
        'needs_confirmation': true,
        'confirmation_reasons': ['Tahmini'],
        'belge_sayisi': 7,
        'oran_kirilimi': [
          {'oran': 20, 'matrah_kurus': 100, 'kdv_kurus': 20},
        ],
      });
      expect(p.locked, isTrue);
      expect(p.hesaplanan.kurus, 6400000);
      expect(p.odenecek, Money.fromKurus(3450000));
      expect(p.breakdown.single.kdv.kurus, 20);
      expect(p.documentCount, 7);
      expect(p.confirmation.needed, isTrue);
      expect(p.isQuarterly, isFalse);
      final q = VatPeriod.fromJson({
        'period': '2026-Q4',
        'oran_kirilimi': {
          '10': {'matrah_kurus': 500, 'kdv_kurus': 50},
        },
      });
      expect(q.isQuarterly, isTrue);
      expect(q.breakdown.single.percent, 10);
      expect(q.estimated, isTrue);
    });
  });

  group('TaxItem', () {
    test('gün sayacı metni', () {
      expect(countdownText(8), '8 gün kaldı');
      expect(countdownText(0), 'Bugün son gün');
      expect(countdownText(-2), '2 gün geçti');
      expect(countdownText(null), '');
    });

    test('Ist saatine göre gün sayısı; kendi hatırlatma tespiti', () {
      Ist.clock = () => DateTime.utc(2026, 11, 20, 9);
      final it = TaxItem.fromJson({
        'key': 'kdv1',
        'title': 'KDV',
        'due_date': '2026-11-28',
        'days_until': 99,
        'kind': 'kdv',
        'needs_confirmation': true,
        'confirmation_reasons': ['x'],
      });
      expect(it.effectiveDays(), 8);
      expect(it.countdownLabel(), '8 gün kaldı');
      expect(it.custom, isFalse);
      expect(it.confirmation.needed, isTrue);
      expect(it.doneKey, 'kdv1|2026-11-28');
      expect(
        TaxItem.fromJson({'key': 'k', 'title': 't', 'kind': 'ozel'}).custom,
        isTrue,
      );
      expect(
        TaxItem.fromJson({'key': 'k', 'title': 't', 'source': 'kullanici'})
            .custom,
        isTrue,
      );
    });
  });

  group('ScheduleItem / yaşlandırma', () {
    test('gecikme: vade bugünden önce ve bekliyor', () {
      Ist.clock = () => DateTime.utc(2026, 11, 20, 9);
      final late = ScheduleItem.fromJson({
        'id': '1',
        'amount_kurus': 500000,
        'due_date': '2026-11-10',
        'status': 'bekliyor',
      });
      expect(late.isOverdue(), isTrue);
      expect(late.overdueDays(), 10);
      final today = ScheduleItem.fromJson({
        'id': '2',
        'amount_kurus': 1,
        'due_date': '2026-11-20',
      });
      expect(today.isOverdue(), isFalse);
      final paid = ScheduleItem.fromJson({
        'id': '3',
        'amount_kurus': 1,
        'due_date': '2026-01-01',
        'status': 'odendi',
      });
      expect(paid.isOverdue(), isFalse);
      final eff = ScheduleItem.fromJson({
        'id': '4',
        'amount_kurus': 1,
        'effective_status': 'gecikti',
      });
      expect(eff.isOverdue(), isTrue);
      expect(late.kind, ScheduleKind.taksit);
      expect(ScheduleMethod.fromApi('Çek')!.isInstrument, isTrue);
      expect(ScheduleMethod.fromApi('Havale')!.isInstrument, isFalse);
    });

    test('AgingReport kovaları', () {
      final r = AgingReport.fromJson({
        'buckets': {
          'notDue': {'count': 1, 'totalKurus': 100, 'items': <Object>[]},
          '0-30': {
            'count': 2,
            'totalKurus': 300,
            'items': [
              {
                'schedule_id': 's1',
                'amount_kurus': 200,
                'customer_name': 'A',
                'days_overdue': 5,
              },
              {'source': 'invoice', 'id': 'i1', 'amount_kurus': 100},
            ],
          },
          '90+': {'count': 0, 'totalKurus': 0, 'items': <Object>[]},
        },
        'totalKurus': 400,
        'overdueKurus': 300,
        'overdueCount': 2,
      });
      expect(r.bucket('0-30').total.kurus, 300);
      expect(r.bucket('0-30').items.first.scheduleId, 's1');
      expect(r.bucket('0-30').items.last.invoiceId, 'i1');
      expect(r.bucket('31-60').count, 0);
      expect(r.overdue.kurus, 300);
      expect(agingBucketLabel('90+'), '90+ gün');
    });
  });

  group('Mesaj şablonu', () {
    test('ton önerisi gecikmeye göre', () {
      expect(ReminderTone.forDaysOverdue(0), ReminderTone.nazik);
      expect(ReminderTone.forDaysOverdue(7), ReminderTone.nazik);
      expect(ReminderTone.forDaysOverdue(8), ReminderTone.orta);
      expect(ReminderTone.forDaysOverdue(31), ReminderTone.kesin);
      expect(ReminderTone.kesin.templateKey, 'odeme_kesin');
    });

    test('render yanıtı', () {
      final m = RenderedMessage.fromJson({
        'text': 'Merhaba',
        'whatsappUrl': 'https://wa.me/905321112233?text=Merhaba',
        'missing': ['telefon'],
        'complete': false,
        'urlTooLong': true,
        'warnings': [
          {'message': 'Uzun'},
          'Düz uyarı',
        ],
      });
      expect(m.complete, isFalse);
      expect(m.urlTooLong, isTrue);
      expect(m.missing, ['telefon']);
      expect(m.warnings, ['Uzun', 'Düz uyarı']);
    });
  });

  test('dayKey ve parseDay İstanbul gününe göre', () {
    expect(
      dayKey(DateTime.utc(2026, 11, 20, 22)),
      '2026-11-21',
    ); // 01:00 İstanbul
    expect(parseDay('2026-11-20'), Ist.fromWall(2026, 11, 20));
    expect(parseDay('bozuk'), isNull);
    expect(parseDay(null), isNull);
  });
}
