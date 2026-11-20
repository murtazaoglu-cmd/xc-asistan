import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/core/util/domain_enums.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/jobs/data/jobs_input.dart';
import 'package:xc_asistan/features/jobs/data/jobs_logic.dart';
import 'package:xc_asistan/features/jobs/data/jobs_models.dart';
import 'package:xc_asistan/features/jobs/data/jobs_project_models.dart';

QuoteItem item(num qty, String price, {bool vat = false}) => QuoteItem(
  desc: 'x',
  qty: qty,
  price: Money.parseUserInput(price)!,
  vatIncluded: vat,
);

void main() {
  group('QuoteMath (backend computeTotals ile birebir)', () {
    test('basit: KDV hariç ve KDV dahil aynı sonucu verir', () {
      final a = QuoteMath.compute([item(1, '1000')]);
      final b = QuoteMath.compute([item(1, '1200', vat: true)]);
      expect(a.subtotal, Money.fromKurus(100000));
      expect(a.tax, Money.fromKurus(20000));
      expect(a.total, Money.fromKurus(120000));
      expect(b, a);
    });

    test('kalem bazlı vatIncluded karışık liste (JS ile doğrulanmış)', () {
      final t = QuoteMath.compute([
        item(3, '33,33', vat: true),
        item(2.5, '19,99'),
      ]);
      expect(t.subtotal.toApiString(), '133.30');
      expect(t.tax.toApiString(), '26.65');
      expect(t.total.toApiString(), '159.95');
      final u = QuoteMath.compute([
        item(7, '0,99', vat: true),
        item(1, '0,01'),
        item(13, '4,55', vat: true),
      ]);
      expect(u.total.toApiString(), '66.09');
      expect(u.tax.toApiString(), '11.01');
    });

    test('total = subtotal + tax her zaman', () {
      final t = QuoteMath.compute([
        item(100, '0,07', vat: true),
        item(100, '0,07'),
      ]);
      expect(t.total, t.subtotal + t.tax);
      expect(t.total.toApiString(), '15.40');
    });

    test('300 rastgele vaka: backend computeTotals çıktısıyla aynı', () {
      final cases = jsonDecode(
        File('test/features/jobs/quote_totals_golden.json').readAsStringSync(),
      ) as List;
      expect(cases.length, 300);
      for (final c in cases) {
        final items = (c['items'] as List)
            .map((e) => QuoteItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        final exp = c['expected'] as Map;
        final t = QuoteMath.compute(items);
        expect(
          t.subtotal,
          Money.fromJson(exp['subtotal']),
          reason: '${c['items']}',
        );
        expect(t.tax, Money.fromJson(exp['tax']), reason: '${c['items']}');
        expect(t.total, Money.fromJson(exp['total']), reason: '${c['items']}');
      }
    });

    test('doğrulama: boş, açıklamasız, adet 0, negatif fiyat, 200+ kalem', () {
      expect(QuoteMath.validate(const []), isNotNull);
      expect(QuoteMath.validate([item(1, '5').copyWith(desc: ' ')]), isNotNull);
      expect(QuoteMath.validate([item(0, '5')]), isNotNull);
      expect(
        QuoteMath.validate([item(1, '5').copyWith(price: Money.fromKurus(-1))]),
        isNotNull,
      );
      expect(
        QuoteMath.validate([for (var i = 0; i < 201; i++) item(1, '1')]),
        isNotNull,
      );
      expect(QuoteMath.validate([item(1, '5')]), isNull);
      // Fiyat sıfır geçerli (price ≥ 0)
      expect(QuoteMath.validate([item(1, '0')]), isNull);
    });

    test('kalem JSON gidiş-dönüş: fiyat noktalı metin, virgül yok', () {
      final it = item(2, '1.250,50', vat: true);
      final j = it.toJson();
      expect(j['price'], '1250.50');
      expect(j['vatIncluded'], true);
      expect(QuoteItem.fromJson(j), it);
    });
  });

  group('QuoteRowInput (form girdisi)', () {
    test('Türkçe sayı biçimleri', () {
      final r = QuoteRowInput(
        desc: 'Kapı',
        qty: '1,5',
        price: '12.500,50',
        vatIncluded: true,
      );
      final it = r.toItem()!;
      expect(it.qty, 1.5);
      expect(it.price, Money.fromKurus(1250050));
      expect(it.vatIncluded, true);
    });

    test('geçersizler', () {
      expect(QuoteRowInput.validateDesc(' '), isNotNull);
      expect(QuoteRowInput.validateQty('0'), isNotNull);
      expect(QuoteRowInput.validateQty('abc'), isNotNull);
      expect(QuoteRowInput.validateQty(''), isNotNull);
      expect(QuoteRowInput.validatePrice(''), isNotNull);
      expect(QuoteRowInput.validatePrice('-5'), isNotNull);
      expect(
        const QuoteRowInput(desc: 'a', qty: '1', price: '').toItem(),
        isNull,
      );
    });

    test('QuoteDraft toplam: geçersiz satırlar hesaba girmez', () {
      final d = QuoteDraft([
        const QuoteRowInput(desc: 'a', qty: '2', price: '100'),
        const QuoteRowInput(desc: '', qty: '1', price: '50'),
      ]);
      expect(d.allValid, false);
      expect(d.totals.total, Money.fromKurus(24000));
    });

    test('formatQty / fromItem gidiş-dönüş', () {
      final r = QuoteRowInput.fromItem(item(1.5, '1000'));
      expect(r.qty, '1,5');
      expect(r.price, '1.000');
      expect(r.toItem()!.price, Money.fromKurus(100000));
    });
  });

  group('Offer modeli', () {
    final json = {
      'id': 'o1',
      'code': 'OFR-1001',
      'tracking_code': 'XCY-4F2A9',
      'name': 'Ayşe Yılmaz',
      'phone': '0532 111 22 33',
      'email': null,
      'service': 'Pergola',
      'region': 'Bodrum',
      'photo_urls': ['https://x/a.jpg'],
      'status': 'Teklif Verildi',
      'created_at': '2026-11-10T08:00:00.000Z',
      'updated_at': '2026-11-12T08:00:00.000Z',
      'quote': {
        'items': [
          {'desc': 'Pergola', 'qty': 1, 'price': 1000, 'vatIncluded': false},
        ],
        'subtotal': 1000,
        'tax': 200,
        'total': 1200,
        'created_at': '2026-11-11T08:00:00.000Z',
        'last_send_status': 'kismen',
        'last_send_at': '2026-11-12T09:00:00.000Z',
        'last_send_error': 'WhatsApp: x',
      },
    };

    test('alanlar ve tutar', () {
      final o = Offer.fromJson(json);
      expect(o.statusEnum, OfferStatus.teklifVerildi);
      expect(o.amount, Money.fromKurus(120000));
      expect(o.quote!.sendStatus, SendStatus.kismen);
      expect(o.quote!.computed.total, o.quote!.total);
      expect(o.photoUrls, ['https://x/a.jpg']);
    });

    test('eksik / bilinmeyen alanlar çökertmez', () {
      final o = Offer.fromJson({'id': 'x', 'status': 'Garip'});
      expect(o.statusEnum, isNull);
      expect(o.amount, isNull);
      expect(o.name, '');
      expect(o.waitingSince, isNull);
    });

    test('items JSON metin olarak gelirse de çözülür', () {
      final q = OfferQuote.fromJson({
        'items': '[{"desc":"A","qty":2,"price":"10.50","vatIncluded":true}]',
        'total': 25.2,
      });
      expect(q.items.single.price, Money.fromKurus(1050));
      expect(q.items.single.vatIncluded, true);
    });

    test('quote_total listeden tutar verir', () {
      final o = Offer.fromJson({
        'id': 'x',
        'status': 'Yeni',
        'quote_total': 3000,
      });
      expect(o.amount, Money.fromKurus(300000));
    });

    test('bekleme yaşı: açık durumlarda gün, kapalıda null', () {
      final now = DateTime.utc(2026, 11, 20, 9);
      final yeni = Offer.fromJson({
        'id': 'a',
        'status': 'Yeni',
        'created_at': '2026-11-17T08:00:00.000Z',
      });
      expect(yeni.waitingDays(now), 3);
      expect(waitingLabel(yeni, now), '3 gündür bekliyor');
      expect(isWaitingStale(yeni, now), true);
      final bugun = Offer.fromJson({
        'id': 'b',
        'status': 'Yeni',
        'created_at': '2026-11-20T06:00:00.000Z',
      });
      expect(waitingLabel(bugun, now), 'Bugün geldi');
      expect(isWaitingStale(bugun, now), false);
      final verildi = Offer.fromJson({
        ...json,
        'created_at': '2026-11-01T08:00:00.000Z',
      });
      expect(
        waitingLabel(verildi, now),
        '8 gün yanıt bekliyor',
      ); // son gönderim 12 Kas
      expect(isWaitingStale(verildi, now), true);
      final kabul = Offer.fromJson({...json, 'status': 'Kabul Edildi'});
      expect(waitingLabel(kabul, now), isNull);
    });

    test('PATCH yanıtı teklifi (quote) silmez', () {
      final o = Offer.fromJson(json);
      final patched = o.mergedWith(
        Offer.fromJson({...json, 'quote': null, 'status': 'Kabul Edildi'}),
      );
      expect(patched.status, 'Kabul Edildi');
      expect(patched.quote, isNotNull);
    });

    test('draft gövdeleri', () {
      const d = OfferDraft(
        name: ' Ali ',
        phone: '0532',
        service: 'Montaj',
        email: '',
        region: 'Bodrum',
      );
      expect(d.toCreateJson(), {
        'name': 'Ali',
        'phone': '0532',
        'service': 'Montaj',
        'region': 'Bodrum',
      });
      // PATCH'te boşaltılan alan null gider (temizleme)
      expect(d.toPatchJson()['email'], isNull);
      expect(d.toPatchJson().containsKey('email'), true);
    });
  });

  group('Teklif form doğrulama', () {
    test('zorunlu alanlar', () {
      expect(OfferValidators.name(''), isNotNull);
      expect(OfferValidators.phone('12'), isNotNull);
      expect(OfferValidators.phone('0532 111 22 33'), isNull);
      expect(OfferValidators.service(null), isNotNull);
    });
    test('e-posta: boş serbest; çoklu/biçimsiz reddedilir', () {
      expect(OfferValidators.email(''), isNull);
      expect(OfferValidators.email('a@b.com'), isNull);
      expect(OfferValidators.email('a@b.com, c@d.com'), isNotNull);
      expect(OfferValidators.email('Ad <a@b.com>'), isNotNull);
      expect(OfferValidators.email('abc'), isNotNull);
      expect(OfferValidators.email('${'a' * 250}@b.co'), isNotNull);
    });
    test('uzunluk sınırları', () {
      expect(OfferValidators.message('x' * 2001), isNotNull);
      expect(OfferValidators.message('x' * 2000), isNull);
      expect(OfferValidators.address('x' * 501), isNotNull);
    });
  });

  group('Gönderim sonucu (200 / 207 / 502)', () {
    test('200: tüm kanallar gitti', () {
      final r = QuoteSendResult.fromResponse(200, {
        'sent': true,
        'channel': 'whatsapp,email',
        'status': 'gonderildi',
        'channels': {
          'whatsapp': {'sent': true, 'error': null},
          'email': {'sent': true, 'skipped': false, 'error': null},
        },
        'pdfUrl': 'https://x/p.pdf?exp=1&sig=2',
      });
      expect(r.outcome, SendOutcome.sent);
      expect(r.sentChannelLabels, ['WhatsApp', 'E-posta']);
      expect(r.failedChannels, isEmpty);
    });

    test('207: kısmen; hata kanalı ve metni korunur', () {
      final r = QuoteSendResult.fromResponse(207, {
        'sent': true,
        'channel': 'email',
        'status': 'kismen',
        'error': 'WhatsApp: 24 saat kuralı',
        'channels': {
          'whatsapp': {'sent': false, 'error': '24 saat kuralı'},
          'email': {'sent': true, 'skipped': false, 'error': null},
        },
        'whatsappUrl': 'https://wa.me/90532?text=a',
      });
      expect(r.outcome, SendOutcome.partial);
      expect(r.sentChannelLabels, ['E-posta']);
      expect(r.failedChannels.single.label, 'WhatsApp');
      expect(r.failedChannels.single.error, '24 saat kuralı');
      expect(r.whatsappUrl, isNotNull);
    });

    test('502: hiçbiri gitmedi', () {
      final r = QuoteSendResult.fromResponse(502, {
        'sent': false,
        'channel': null,
        'status': 'basarisiz',
        'error': 'WhatsApp: hata',
        'channels': {
          'whatsapp': {'sent': false, 'error': 'hata'},
          'email': {
            'sent': false,
            'skipped': true,
            'error': 'Müşterinin e-posta adresi yok.',
          },
        },
      });
      expect(r.outcome, SendOutcome.failed);
      expect(r.sentChannelLabels, isEmpty);
      expect(r.failedChannels.single.label, 'WhatsApp');
    });

    test(
      'çelişki: 200 ama gövde sent:false → başarısız sayılır (kötümser)',
      () {
        expect(
          QuoteSendResult.fromResponse(200, {
            'sent': false,
            'status': 'basarisiz',
          }).outcome,
          SendOutcome.failed,
        );
      },
    );

    test('çelişki: 200 ama bir kanal hata verdi → kısmen (sessizce "gönderildi" denmez)', () {
      final r = QuoteSendResult.fromResponse(200, {
        'sent': true,
        'status': 'gonderildi',
        'channels': {
          'whatsapp': {'sent': false, 'error': 'x'},
          'email': {'sent': true, 'skipped': false},
        },
      });
      expect(r.outcome, SendOutcome.partial);
    });

    test('kanal ayrıntısı yoksa channel alanından etiket', () {
      final r = QuoteSendResult.fromResponse(200, {
        'sent': true,
        'channel': 'whatsapp',
      });
      expect(r.sentChannelLabels, ['WhatsApp']);
    });

    test('sunucu hatası (500) başarısız', () {
      expect(QuoteSendResult.failure('x').outcome, SendOutcome.failed);
      expect(
        QuoteSendResult.fromResponse(500, {'sent': false}).outcome,
        SendOutcome.failed,
      );
    });
  });

  group('Proje modeli', () {
    final pj = {
      'id': 'p1',
      'code': 'PRJ-501',
      'offer_id': 'o1',
      'customer_name': 'Zeynep',
      'service': 'Montaj',
      'stage': 'Üretim',
      'total_amount': 8500,
      'paid_amount': 4000,
      'start_date': '2026-11-01T09:00:00.000Z',
      'end_date': '2026-11-10T09:00:00.000Z',
    };

    test('gecikme ve kalan', () {
      final p = Project.fromJson(pj);
      final now = DateTime.utc(2026, 11, 20, 9);
      expect(p.isOverdue(now), true);
      expect(p.daysOverdue(now), 10);
      expect(p.listBalance, Money.fromKurus(450000));
      expect(
        Project.fromJson({...pj, 'stage': 'Tamamlandı'}).isOverdue(now),
        false,
      );
      expect(p.stageProgress, 0.25);
    });

    test('saha: total_amount yok → null, çökmez', () {
      final p = Project.fromJson({...pj}..remove('total_amount'));
      expect(p.totalAmount, isNull);
      expect(p.listBalance, isNull);
    });

    test(
      'ProjectFull: kalan = sözleşme + ilave işler − tahsilat; ilerleme',
      () {
        final f = ProjectFull.fromJson({
          'project': pj,
          'tasks': [
            {
              'id': 't1',
              'project_id': 'p1',
              'title': 'a',
              'status': 'tamamlandi',
            },
            {
              'id': 't2',
              'project_id': 'p1',
              'title': 'b',
              'status': 'bekliyor',
            },
          ],
          'extras': [
            {'id': 'e1', 'description': 'ek', 'amount': 1500},
            {'id': 'e2', 'description': 'indirim', 'amount': -500},
          ],
          'payments': [
            {
              'id': 'x',
              'amount': 4000,
              'method': 'Havale',
              'paid_at': '2026-11-02T09:00:00Z',
            },
          ],
          'expenses': [
            {
              'id': 'g',
              'category': 'Malzeme',
              'amount': 3200.5,
              'expense_date': '2026-11-03T09:00:00Z',
            },
          ],
        });
        expect(f.extrasTotal, Money.fromKurus(100000));
        expect(f.balance, Money.fromKurus(550000)); // 8500 + 1000 - 4000
        expect(f.progress, 0.5);
        expect(f.paidRatio, closeTo(4000 / 9500, 1e-9));
        expect(f.expensesTotal.toApiString(), '3200.50');
      },
    );

    test('görev yokken ilerleme aşamadan gelir', () {
      final f = ProjectFull.fromJson({
        'project': {...pj, 'stage': 'Montaj'},
      });
      expect(f.progress, 0.5);
    });

    test('proje taslağı doğrulama', () {
      expect(ProjectValidators.customerName(''), isNotNull);
      expect(ProjectValidators.service(' '), isNotNull);
      expect(ProjectValidators.amount(''), isNull);
      expect(ProjectValidators.amount('-5'), isNotNull);
      expect(ProjectValidators.amount('abc'), isNotNull);
      expect(ProjectValidators.amount('12.500,50'), isNull);
      expect(ProjectValidators.extraAmount('-250'), isNull); // indirim serbest
      expect(ProjectValidators.extraAmount('0'), isNotNull);
      expect(ProjectValidators.taskTitle('  '), isNotNull);
      const d = ProjectDraft(
        customerName: ' A ',
        service: 'B',
        totalAmount: Money.zero,
      );
      expect(d.toJson()['customer_name'], 'A');
      expect(d.toJson()['stage'], 'Malzeme Temini');
      expect(d.toJson().containsKey('address'), false);
    });
  });

  group('Belge kuralları', () {
    test('izin listesi ve boyut', () {
      expect(DocumentRules.validate('a.pdf', 100), isNull);
      expect(DocumentRules.validate('FOTO.JPG', 100), isNull);
      expect(DocumentRules.validate('a.exe', 100), 'Bu dosya türü yüklenemez.');
      expect(DocumentRules.validate('a', 100), isNotNull);
      expect(
        DocumentRules.validate('a.pdf', DocumentRules.maxBytes + 1),
        isNotNull,
      );
      expect(DocumentRules.validate('a.pdf', 0), isNotNull);
      expect(DocumentRules.allowedExtensions, contains('dwg'));
      expect(DocumentRules.allowedExtensions, isNot(contains('svg')));
    });
    test('görsel/pdf ayrımı', () {
      final d = DocumentItem.fromJson({
        'id': '1',
        'file_url': 'u',
        'file_name': 'x.HEIC',
      });
      expect(d.isImage, true);
      expect(DocumentItem.fromJson({'file_name': 'a.pdf'}).isPdf, true);
    });
  });

  group('Küçük yardımcılar', () {
    test('dative (yönelme eki)', () {
      expect(dative('Proje'), 'Projeye');
      expect(dative('İş'), 'İşe');
      expect(dative('Çalışma'), 'Çalışmaya');
      expect(dative('Sipariş'), 'Siparişe');
      expect(dative('Montaj'), 'Montaja');
    });

    test('WhatsApp metni: marka, kod, toplam, takip kodu/bağlantısı', () {
      final o = Offer.fromJson({
        'id': 'a',
        'code': 'OFR-1',
        'name': 'Ayşe',
        'status': 'Teklif Verildi',
        'tracking_code': 'XCY-1',
        'quote': {'total': 1200, 'subtotal': 1000, 'tax': 200},
      });
      final t = quoteWhatsAppText(
        companyName: 'Firma',
        offerTerm: 'Teklif',
        offer: o,
      );
      expect(t, contains('Merhaba Ayşe, Firma olarak'));
      expect(t, contains('teklif (OFR-1)'));
      expect(t, contains('₺1.200'));
      expect(t, contains('Takip kodunuz: XCY-1'));
      final link = quoteWhatsAppText(
        companyName: 'Firma',
        offerTerm: 'Teklif',
        offer: o,
        trackingBase: 'https://s.com/teklif-takip/',
      );
      expect(link, contains('https://s.com/teklif-takip/XCY-1'));
    });

    test('Ist günü ile bekleme: gece yarısı sınırı İstanbul', () {
      // 19 Kas 21:30 UTC = 20 Kas 00:30 İstanbul → 1 gün sayılır
      final o = Offer.fromJson({
        'id': 'a',
        'status': 'Yeni',
        'created_at': '2026-11-19T21:30:00Z',
      });
      expect(o.waitingDays(DateTime.utc(2026, 11, 20, 20)), 0);
      expect(
        Ist.dayDiff(
          DateTime.utc(2026, 11, 19, 20),
          DateTime.utc(2026, 11, 19, 22),
        ),
        1,
      );
    });
  });
}
