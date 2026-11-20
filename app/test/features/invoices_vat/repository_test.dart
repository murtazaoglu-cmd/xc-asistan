import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_errors.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_input.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_models.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_repository.dart';

import '../../helpers/fakes.dart';
import 'harness.dart';

HttpInvoicesVatRepository repoFor(ScriptedAdapter a) =>
    HttpInvoicesVatRepository(apiWith(a));

void main() {
  group('faturalar', () {
    test('liste: sorgu parametreleri ve X-Total-Count', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(
          200,
          [
            {
              'id': '1',
              'direction': 'giden',
              'matrah_kurus': 100,
              'kdv_kurus': 20,
              'status': 'kesildi',
            },
          ],
          {'x-total-count': '37'},
        ),
      );
      final page = await repoFor(a).listInvoices(
        const InvoiceQuery(
          direction: InvoiceDirection.giden,
          statuses: {InvoiceStatus.odendi, InvoiceStatus.kesildi},
          period: '2026-11',
          q: ' Ali ',
          overdueOnly: true,
          limit: 100,
          offset: 100,
        ),
      );
      final q = a.requests.single.queryParameters;
      expect(a.requests.single.path, '/invoices');
      expect(q['direction'], 'giden');
      expect(q['status'], 'kesildi,odendi');
      expect(q['period'], '2026-11');
      expect(q['q'], 'Ali');
      expect(q['overdue'], 1);
      expect(q['limit'], 100);
      expect(q['offset'], 100);
      expect(page.total, 37);
      expect(page.items.single.tutar.kurus, 120);
      expect(page.hasMore(0), isTrue);
    });

    test('liste: boş filtre direction/status/q göndermez', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, <dynamic>[]));
      await repoFor(a).listInvoices(const InvoiceQuery());
      final q = a.requests.single.queryParameters;
      expect(q.containsKey('direction'), isFalse);
      expect(q.containsKey('status'), isFalse);
      expect(q.containsKey('q'), isFalse);
      expect(q.containsKey('overdue'), isFalse);
    });

    test('oluştur: gövde kuruş tamsayı + Idempotency-Key', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(201, {
          'id': 'n1',
          'matrah_kurus': 10000,
          'kdv_kurus': 2000,
          'tutar_kurus': 12000,
        }),
      );
      final inv = await repoFor(a).createInvoice(
        InvoiceInput(
          direction: InvoiceDirection.gelen,
          issueDate: '2026-11-20',
          amount: Money.fromKurus(10000),
          basis: AmountBasis.exclusive,
          counterparty: 'Tedarikçi',
          kdvOran: 20,
          kdvDeductible: true,
        ),
        idempotencyKey: 'KEY-1',
      );
      final r = a.requests.single;
      expect(r.method, 'POST');
      expect(r.path, '/invoices');
      expect(r.headers['Idempotency-Key'], 'KEY-1');
      final body = r.data as Map;
      expect(body['matrah_kurus'], 10000);
      expect(body['direction'], 'gelen');
      expect(body['kdv_indirilebilir'], true);
      expect(inv.id, 'n1');
      expect(inv.tutar.kurus, 12000);
    });

    test(
      'Idempotency-Key verilmezse üretilir ve her çağrıda farklıdır',
      () async {
        final a = ScriptedAdapter((i, o) => ScriptedResponse(201, {'id': 'x'}));
        final r = repoFor(a);
        final input = InvoiceInput(
          direction: InvoiceDirection.giden,
          issueDate: '2026-11-20',
          amount: Money.fromKurus(1),
          basis: AmountBasis.inclusive,
        );
        await r.createInvoice(input);
        await r.createInvoice(input);
        final k1 = a.requests[0].headers['Idempotency-Key'] as String;
        final k2 = a.requests[1].headers['Idempotency-Key'] as String;
        expect(k1, hasLength(32));
        expect(k1, isNot(k2));
        expect((a.requests[0].data as Map).containsKey('tutar_kurus'), isTrue);
      },
    );

    test('güncelle: PATCH, temizlenen alanlar null gider', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, {'id': 'p1'}));
      await repoFor(a).updateInvoice(
        'p1',
        InvoiceInput(
          direction: InvoiceDirection.giden,
          issueDate: '2026-11-20',
          amount: Money.fromKurus(500),
          basis: AmountBasis.exclusive,
        ),
      );
      final r = a.requests.single;
      expect(r.method, 'PATCH');
      expect(r.path, '/invoices/p1');
      final b = r.data as Map;
      expect(b.containsKey('due_date') && b['due_date'] == null, isTrue);
      expect(b.containsKey('project_id') && b['project_id'] == null, isTrue);
    });

    test('400 kdv_mismatch: kod ve beklenen KDV okunur; onayla gönder accept_mismatch', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(400, {
          'error': 'KDV uyuşmuyor',
          'code': 'kdv_mismatch',
          'expectedKdvKurus': 2000,
        }),
      );
      try {
        await repoFor(a).createInvoice(
          InvoiceInput(
            direction: InvoiceDirection.giden,
            issueDate: '2026-11-20',
            amount: Money.fromKurus(10000),
            basis: AmountBasis.exclusive,
            documentKdv: Money.fromKurus(3000),
          ),
        );
        fail('hata beklenirdi');
      } on AppException catch (e) {
        final mm = KdvMismatch.of(e)!;
        expect(mm.expected, Money.fromKurus(2000));
        expect((a.requests.single.data as Map)['kdv_kurus'], 3000);
      }
      expect(
        (InvoiceInput(
          direction: InvoiceDirection.giden,
          issueDate: '2026-11-20',
          amount: Money.fromKurus(1),
          basis: AmountBasis.exclusive,
        ).copyWith(acceptMismatch: true)).toJson()['accept_mismatch'],
        true,
      );
    });

    test(
      '409 vat_period_locked → nazik mesaj; 403/404 eşlemesi; 5xx maskelenir',
      () async {
        Future<AppException> fail(
          int status, [
          Map<String, dynamic>? body,
        ]) async {
          final a = ScriptedAdapter(
            (i, o) => ScriptedResponse(status, body ?? {'error': 'ham sunucu'}),
          );
          try {
            await repoFor(a).invoice('x');
          } on AppException catch (e) {
            return e;
          }
          throw StateError('hata beklenirdi');
        }

        final locked = await fail(409, {
          'error': 'kilitli',
          'code': 'vat_period_locked',
        });
        expect(InvoicesVatErrors.isPeriodLocked(locked), isTrue);
        expect(
          InvoicesVatErrors.message(locked, InvoicesVatOp.save),
          InvoicesVatErrors.periodLocked,
        );
        final other409 = await fail(409, {
          'error': 'Yalnız taslak silinebilir',
        });
        expect(InvoicesVatErrors.isPeriodLocked(other409), isFalse);
        expect(
          InvoicesVatErrors.message(other409, InvoicesVatOp.delete),
          'Yalnız taslak silinebilir',
        );
        expect((await fail(403)).code, AppErrorCode.forbidden);
        expect(
          InvoicesVatErrors.message(await fail(403), InvoicesVatOp.load),
          'Bu işlem için yetkiniz yok.',
        );
        expect(
          InvoicesVatErrors.message(await fail(404), InvoicesVatOp.load),
          contains('bulunamadı'),
        );
        final e500 = await fail(500, {'error': 'SELECT * FROM secret'});
        expect(e500.message.contains('SELECT'), isFalse);
        expect(
          InvoicesVatErrors.message(
            e500,
            InvoicesVatOp.load,
          ).contains('SELECT'),
          isFalse,
        );
      },
    );

    test('ödendi işaretle gövdesi ve kapanan plan sayısı', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {'schedule_items_closed': 2}),
      );
      final r = await repoFor(a).markInvoicePaid(
        'i1',
        paidAt: '2026-11-20',
        method: ScheduleMethod.cek,
        createPayment: true,
      );
      final q = a.requests.single;
      expect(q.path, '/invoices/i1/mark-paid');
      expect(q.data, {
        'paid_at': '2026-11-20',
        'method': 'Çek',
        'create_payment': true,
      });
      expect(r.scheduleItemsClosed, 2);
    });

    test('dosya yükle: multipart alan adı file', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(201, {
          'id': 'f1',
          'file_name': 'a.pdf',
          'file_url': 'https://x/u',
        }),
      );
      // Gerçek dosya gerekir.
      final tmp = await _tmpFile();
      final f = await repoFor(a)
          .uploadInvoiceFile('i1', tmp, fileName: 'fatura.pdf');
      final r = a.requests.single;
      expect(r.path, '/invoices/i1/files');
      expect(r.data, isA<FormData>());
      expect((r.data as FormData).files.single.key, 'file');
      expect(f.id, 'f1');
    });
  });

  group('KDV', () {
    test('dönemler: liste ve sarmalı biçim; tek dönem', () async {
      var n = 0;
      final a = ScriptedAdapter((i, o) {
        n++;
        return ScriptedResponse(
          200,
          o.path == '/vat/periods'
              ? (n == 1
                    ? [
                        {'period': '2026-11', 'odenecek_kurus': 500},
                      ]
                    : {
                        'periods': [
                          {'period': '2026-Q4'},
                        ],
                      })
              : {'period': '2026-11', 'odenecek_kurus': 700},
        );
      });
      final r = repoFor(a);
      final l1 = await r.vatPeriods(year: 2026);
      expect(a.requests[0].queryParameters, {'year': 2026, 'type': 'aylik'});
      expect(l1.single.odenecek.kurus, 500);
      final l2 = await r.vatPeriods(year: 2026, type: 'uc_aylik');
      expect(l2.single.isQuarterly, isTrue);
      expect((await r.vatPeriod('2026-11')).odenecek.kurus, 700);
    });

    test('kilitle/aç/hesapla/devreden uçları', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {'period': '2026-11'}),
      );
      final r = repoFor(a);
      await r.lockVatPeriod('2026-11');
      await r.unlockVatPeriod('2026-11');
      await r.calculateVatPeriod('2026-11');
      await r.updateVatPeriod(
        '2026-11',
        manualCarryIn: Money.fromKurus(1500),
        note: 'n',
      );
      expect(a.requests.map((e) => '${e.method} ${e.path}'), [
        'POST /vat/periods/2026-11/lock',
        'POST /vat/periods/2026-11/unlock',
        'POST /vat/periods/2026-11/calculate',
        'PATCH /vat/periods/2026-11',
      ]);
      expect(a.requests.last.data, {
        'manual_carry_in_kurus': 1500,
        'note': 'n',
      });
    });

    test('oranlar', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {
          'rates': [
            {'id': '1', 'rate': 20, 'is_default': true},
          ],
          'withholding_types': <dynamic>[],
          'disclaimer': 'd',
        }),
      );
      final v = await repoFor(a).vatRates();
      expect(v.defaultRate!.percent, 20);
      expect(v.disclaimer, 'd');
    });
  });

  group('dışa aktarma', () {
    Future<ExportFile> run(
      Map<String, String> headers,
      List<int> bytes, {
      String format = 'csv',
    }) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'));
      dio.httpClientAdapter = _BytesAdapter(bytes, headers);
      return HttpInvoicesVatRepository(ApiClient(dio))
          .exportInvoices(period: '2026-11', format: format);
    }

    test('baytlar, dosya adı ve teyit başlığı', () async {
      final f = await run(
        {
          'content-type': 'text/csv; charset=utf-8',
          'content-disposition': 'attachment; filename="faturalar-2026-11.csv"',
          'x-needs-confirmation': 'true',
        },
        [0xEF, 0xBB, 0xBF, 0x54, 0x61],
      );
      expect(f.filename, 'faturalar-2026-11.csv');
      expect(f.mime, 'text/csv');
      expect(f.needsConfirmation, isTrue);
      expect(f.bytes.take(3), [0xEF, 0xBB, 0xBF]);
    });

    test('başlık yoksa varsayılan ad; yol kaçışı temizlenir', () async {
      final f = await run({}, [1, 2, 3], format: 'xlsx');
      expect(f.filename, 'faturalar-2026-11.xlsx');
      expect(f.mime, contains('spreadsheetml'));
      expect(f.needsConfirmation, isFalse);
      expect(
        HttpInvoicesVatRepository.filenameFromDisposition(
          'attachment; filename="../../etc/passwd"',
        ),
        'passwd',
      );
      expect(
        HttpInvoicesVatRepository.filenameFromDisposition(
          "attachment; filename*=UTF-8''kdv%20%C3%B6zet.csv",
        ),
        'kdv özet.csv',
      );
      expect(HttpInvoicesVatRepository.filenameFromDisposition(null), isNull);
    });

    test('istek: period, format, include=all', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, <dynamic>[]));
      try {
        await repoFor(a).exportInvoices(
          period: '2026-Q4',
          format: 'xlsx',
          direction: InvoiceDirection.gelen,
          includeAll: true,
        );
      } catch (_) {}
      expect(a.requests.single.path, '/invoices/export');
      expect(a.requests.single.queryParameters, {
        'period': '2026-Q4',
        'format': 'xlsx',
        'direction': 'gelen',
        'include': 'all',
      });
      expect(a.requests.single.responseType, ResponseType.bytes);
    });
  });

  group('vergi takvimi', () {
    test('takvim ve kendi hatırlatma uçları', () async {
      final a = ScriptedAdapter((i, o) {
        if (o.method == 'GET') {
          return ScriptedResponse(200, {
            'items': [
              {
                'key': 'k',
                'title': 'KDV',
                'due_date': '2026-11-28',
                'needs_confirmation': true,
              },
            ],
            'needs_confirmation_count': 1,
            'disclaimer': 'x',
          });
        }
        return ScriptedResponse(201, {
          'id': 't1',
          'key': 'o1',
          'title': 'Not',
          'kind': 'ozel',
        });
      });
      final r = repoFor(a);
      final cal = await r.taxCalendar(days: 120);
      expect(a.requests.first.queryParameters, {'days': 120});
      expect(cal.needsConfirmationCount, 1);
      expect(cal.items.single.confirmation.needed, isTrue);
      final c = await r.createTaxItem(
        title: ' Not ',
        dueDate: '2026-12-01',
        note: ' n ',
      );
      expect(c.custom, isTrue);
      final body = a.requests[1].data as Map;
      expect(body['title'], 'Not');
      expect(body['due_date'], '2026-12-01');
      expect(body['note'], 'n');
      await r.updateTaxItem('t1', title: 'Yeni');
      await r.deleteTaxItem('t1');
      expect(a.requests[2].method, 'PATCH');
      expect(a.requests[3].path, '/tax-calendar/items/t1');
    });
  });

  group('tahsilat planı ve şablonlar', () {
    test('plan üret: gövde ve yanıt (items sarmalı ya da dizi)', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(201, {
          'items': [
            {'id': 's1', 'amount_kurus': 33333, 'due_date': '2026-12-01'},
            {'id': 's2', 'amount_kurus': 33334, 'due_date': '2026-12-31'},
          ],
        }),
      );
      final rows = await repoFor(a).generateSchedule(
        PlanRequest(
          projectId: 'p1',
          total: Money.fromKurus(66667),
          count: 2,
          firstDue: '2026-12-01',
          kind: ScheduleKind.cek,
          method: ScheduleMethod.cek,
        ),
        idempotencyKey: 'K',
      );
      final r = a.requests.single;
      expect(r.path, '/payment-schedule/generate');
      expect(r.headers['Idempotency-Key'], 'K');
      expect(r.data, {
        'project_id': 'p1',
        'total_kurus': 66667,
        'count': 2,
        'first_due': '2026-12-01',
        'kind': 'cek',
        'interval_days': 30,
        'method': 'Çek',
      });
      expect(rows.map((e) => e.amount.kurus), [33333, 33334]);
    });

    test('satır oluştur ve ödendi (gerçekleşen ödemeye bağ)', () async {
      final a = ScriptedAdapter((i, o) => ScriptedResponse(200, {'id': 's'}));
      final r = repoFor(a);
      await r.createScheduleItem(
        ScheduleInput(
          amount: Money.fromKurus(1000),
          dueDate: '2026-12-01',
          projectId: 'p1',
          offerId: 'o1',
          kind: ScheduleKind.senet,
          method: ScheduleMethod.senet,
          instrumentNo: 'SN-1',
          bank: ' ',
        ),
      );
      final body = a.requests[0].data as Map;
      expect(body['project_id'], 'p1');
      expect(body.containsKey('offer_id'), isFalse); // yalnız bir bağ
      expect(body['kind'], 'senet');
      expect(body['instrument_no'], 'SN-1');
      expect(body.containsKey('bank'), isFalse);
      await r.markSchedulePaid(
        's',
        paidAt: '2026-11-20',
        createPayment: true,
        paymentId: 'pay1',
        method: ScheduleMethod.havale,
      );
      expect(a.requests[1].path, '/payment-schedule/s/mark-paid');
      expect(a.requests[1].data, {
        'paid_at': '2026-11-20',
        'create_payment': true,
        'payment_id': 'pay1',
        'method': 'Havale',
      });
    });

    test('yaşlandırma ve plan listesi sorguları', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(
          200,
          o.path == '/receivables/aging' ? {'buckets': {}} : <dynamic>[],
        ),
      );
      final r = repoFor(a);
      await r.aging(projectId: 'p1');
      await r.schedule(projectId: 'p1', status: 'bekliyor');
      expect(a.requests[0].queryParameters, {'project_id': 'p1'});
      expect(a.requests[1].queryParameters, {
        'project_id': 'p1',
        'status': 'bekliyor',
      });
    });

    test('şablon render: bağlam kimliği ve telefon', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, {
          'text': 'Merhaba',
          'whatsappUrl': 'https://wa.me/905321112233?text=Merhaba',
          'complete': true,
        }),
      );
      final m = await HttpInvoicesVatRepository(apiWith(a)).renderTemplate(
        'tpl1',
        scheduleId: 's1',
        invoiceId: 'i1',
        phone: ' 0532 111 22 33 ',
      );
      final r = a.requests.single;
      expect(r.path, '/message-templates/tpl1/render');
      expect(r.data, {'schedule_id': 's1', 'phone': '0532 111 22 33'});
      expect(m.whatsappUrl, startsWith('https://wa.me/'));
    });

    test('şablon listesi kategori/ton', () async {
      final a = ScriptedAdapter(
        (i, o) => ScriptedResponse(200, [
          {
            'id': 't',
            'key': 'odeme_nazik',
            'name': 'Nazik',
            'tone': 'nazik',
            'category': 'odeme',
          },
        ]),
      );
      final l = await repoFor(a).templates(category: 'odeme', tone: 'nazik');
      expect(a.requests.single.queryParameters, {
        'category': 'odeme',
        'tone': 'nazik',
      });
      expect(l.single.key, 'odeme_nazik');
    });
  });

  group('DEMO sahte API (sözleşme biçimi)', () {
    test(
      'admin: fatura oluştur → dönem KDV değişir; kilitli döneme yazılamaz',
      () async {
        final r = demoRepo();
        final before = await r.vatPeriod('2026-11');
        final created = await r.createInvoice(
          InvoiceInput(
            direction: InvoiceDirection.giden,
            issueDate: '2026-11-18',
            amount: Money.fromKurus(100000),
            basis: AmountBasis.exclusive,
            counterparty: 'Demo Müşteri',
            status: InvoiceStatus.kesildi,
          ),
        );
        expect(created.kdv.kurus, 20000);
        final after = await r.vatPeriod('2026-11');
        expect(after.hesaplanan.kurus - before.hesaplanan.kurus, 20000);
        await r.lockVatPeriod('2026-11');
        expect((await r.vatPeriod('2026-11')).locked, isTrue);
        try {
          await r.createInvoice(
            InvoiceInput(
              direction: InvoiceDirection.giden,
              issueDate: '2026-11-19',
              amount: Money.fromKurus(100),
              basis: AmountBasis.exclusive,
              counterparty: 'X',
            ),
          );
          fail('kilitli dönem 409 vermeliydi');
        } on AppException catch (e) {
          expect(InvoicesVatErrors.isPeriodLocked(e), isTrue);
        }
        await r.unlockVatPeriod('2026-11');
        expect((await r.vatPeriod('2026-11')).locked, isFalse);
      },
    );

    test('kdv_mismatch demo ve kabul', () async {
      final r = demoRepo();
      final input = InvoiceInput(
        direction: InvoiceDirection.giden,
        issueDate: '2026-11-18',
        amount: Money.fromKurus(10000),
        basis: AmountBasis.exclusive,
        counterparty: 'M',
        documentKdv: Money.fromKurus(3000),
      );
      try {
        await r.createInvoice(input);
        fail('mismatch beklenirdi');
      } on AppException catch (e) {
        expect(KdvMismatch.of(e)!.expected, Money.fromKurus(2000));
      }
      final ok = await r.createInvoice(input.copyWith(acceptMismatch: true));
      expect(ok.kdv.kurus, 2000);
    });

    test('plan üret, ödendi + gerçekleşen ödeme, yaşlandırma', () async {
      final r = demoRepo();
      final rows = await r.generateSchedule(
        PlanRequest(
          projectId: 'prj-3',
          total: Money.fromKurus(100000),
          count: 3,
          firstDue: '2026-12-01',
        ),
      );
      expect(rows.map((e) => e.amount.kurus), [33333, 33333, 33334]);
      final aging = await r.aging();
      expect(aging.overdueCount, greaterThan(0));
      expect(aging.total.kurus, greaterThan(0));
      await r.markSchedulePaid(rows.first.id, createPayment: true);
      final after = await r.schedule(projectId: 'prj-3');
      expect(after.first.isPaid, isTrue);
    });

    test('şablon render: wa.me bağlantısı telefonla', () async {
      final r = demoRepo();
      final sched = (await r.schedule(status: 'bekliyor'))
          .firstWhere((s) => s.isOverdue());
      final tpls = await r.templates();
      final m = await r.renderTemplate(tpls.first.id, scheduleId: sched.id);
      expect(m.complete, isTrue);
      expect(m.whatsappUrl, startsWith('https://wa.me/90'));
    });

    test('personel/saha: 403', () async {
      for (final role in ['personel', 'saha']) {
        final r = demoRepo(role: role);
        await expectLater(
          r.listInvoices(const InvoiceQuery()),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.forbidden,
            ),
          ),
        );
      }
    });

    test(
      'ortak: vergi takvimi okur, kendi hatırlatma ekleyemez (403)',
      () async {
        final r = demoRepo(role: 'ortak');
        final cal = await r.taxCalendar();
        expect(cal.items, isNotEmpty);
        await expectLater(
          r.createTaxItem(title: 'x', dueDate: '2026-12-01'),
          throwsA(
            isA<AppException>().having(
              (e) => e.code,
              'code',
              AppErrorCode.forbidden,
            ),
          ),
        );
      },
    );

    test('dışa aktarma CSV: BOM + ; ayırıcı', () async {
      final f = await demoRepo().exportInvoices(
        period: '2026-11',
        format: 'csv',
      );
      expect(f.bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(f.bytes), contains('Tarih;Belge Türü'));
      expect(f.needsConfirmation, isTrue);
    });
  });
}

Future<String> _tmpFile() async {
  final d = Directory.systemTemp.createTempSync('invvat');
  final f = File('${d.path}/fatura.pdf')..writeAsBytesSync([37, 80, 68, 70]);
  addTearDown(() => d.deleteSync(recursive: true));
  return f.path;
}

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes, this.headers);
  final List<int> bytes;
  final Map<String, String> headers;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    bytes,
    200,
    headers: {
      for (final e in headers.entries) e.key: [e.value],
    },
  );
  @override
  void close({bool force = false}) {}
}
