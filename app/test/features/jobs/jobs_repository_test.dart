import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/core/util/domain_enums.dart';
import 'package:xc_asistan/core/util/money.dart';
import 'package:xc_asistan/features/jobs/data/jobs_models.dart';
import 'package:xc_asistan/features/jobs/data/jobs_project_models.dart';
import 'package:xc_asistan/features/jobs/data/jobs_repository.dart';

import '../../helpers/fakes.dart';

(HttpJobsRepository, ScriptedAdapter) make(
  FutureOr<ScriptedResponse> Function(int i, RequestOptions o) script,
) {
  final adapter = ScriptedAdapter(script);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'));
  dio.httpClientAdapter = adapter;
  return (HttpJobsRepository(ApiClient(dio)), adapter);
}

const offerJson = {
  'id': 'o1',
  'code': 'OFR-1001',
  'name': 'Ayşe Yılmaz',
  'phone': '0532 111 22 33',
  'service': 'Pergola',
  'status': 'Yeni',
};

void main() {
  group('Teklif listesi: arama + sayfalama (§6)', () {
    test('q, status, limit, offset gönderilir; X-Total-Count okunur', () async {
      final (repo, a) = make(
        (i, o) => ScriptedResponse(200, [offerJson], {'x-total-count': '41'}),
      );
      final page = await repo.offers(
        q: ' ayşe ',
        status: OfferStatus.kesifPlanlandi,
        limit: 30,
        offset: 60,
      );
      final q = a.requests.single.queryParameters;
      expect(a.requests.single.path, '/offers');
      expect(q['q'], ' ayşe '.trim() == q['q'] ? q['q'] : 'ayşe');
      expect(q['status'], 'Keşif Planlandı'); // tam yazım
      expect(q['limit'], 30);
      expect(q['offset'], 60);
      expect(page.total, 41);
      expect(page.items.single.name, 'Ayşe Yılmaz');
      expect(page.hasMore(60), false); // 60 + 1 < 41 değil → son sayfa
      expect(Paged<int>(const [1], 41).hasMore(0), true);
    });

    test('boş arama ve boş süzgeç sorguya girmez', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(200, <Object>[]));
      final page = await repo.offers(q: '  ');
      final q = a.requests.single.queryParameters;
      expect(q.containsKey('q'), false);
      expect(q.containsKey('status'), false);
      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test('arama 100 karakterle sınırlanır (sözleşme)', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(200, <Object>[]));
      await repo.offers(q: 'a' * 150);
      expect((a.requests.single.queryParameters['q'] as String).length, 100);
    });

    test('403 → AppException.forbidden (saha)', () async {
      final (repo, _) = make(
        (i, o) =>
            ScriptedResponse(403, {'error': 'Bu işlem için yetkiniz yok.'}),
      );
      await expectLater(
        repo.offers(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });

    test(
      'ağ hatası → AppException.network (yeniden denenmez: Dio çıplak)',
      () async {
        final (repo, _) = make(
          (i, o) => ScriptedResponse.error(DioExceptionType.connectionError, o),
        );
        await expectLater(
          repo.offers(),
          throwsA(
            isA<AppException>().having((e) => e.isNetwork, 'network', true),
          ),
        );
      },
    );
  });

  group('Teklif gönderimi /quotes/:id/send', () {
    Future<QuoteSendResult> run(int status, Map<String, Object?> body) async {
      final (repo, a) = make((i, o) => ScriptedResponse(status, body));
      final r = await repo.sendQuote('o1');
      expect(a.requests.single.method, 'POST');
      expect(a.requests.single.path, '/quotes/o1/send');
      return r;
    }

    test('200 gönderildi', () async {
      final r = await run(200, {
        'sent': true,
        'channel': 'whatsapp,email',
        'status': 'gonderildi',
        'channels': {
          'whatsapp': {'sent': true},
          'email': {'sent': true, 'skipped': false},
        },
      });
      expect(r.httpStatus, 200);
      expect(r.outcome, SendOutcome.sent);
    });

    test('207 kısmen: istisna FIRLATMAZ, kanal hatası döner', () async {
      final r = await run(207, {
        'sent': true,
        'channel': 'email',
        'status': 'kismen',
        'error': 'WhatsApp: x',
        'channels': {
          'whatsapp': {'sent': false, 'error': 'x'},
          'email': {'sent': true},
        },
        'whatsappUrl': 'https://wa.me/905321112233?text=a',
        'pdfUrl': 'https://api/uploads/a.pdf?exp=1&sig=2',
      });
      expect(r.outcome, SendOutcome.partial);
      expect(r.failedChannels.single.error, 'x');
      expect(r.pdfUrl, contains('sig='));
    });

    test('502 gönderilemedi: istisna FIRLATMAZ', () async {
      final r = await run(502, {
        'sent': false,
        'channel': null,
        'status': 'basarisiz',
        'error': 'WhatsApp: hata',
        'channels': {
          'whatsapp': {'sent': false, 'error': 'hata'},
          'email': {'sent': false, 'skipped': true},
        },
      });
      expect(r.outcome, SendOutcome.failed);
      expect(r.error, 'WhatsApp: hata');
    });

    test('400 (önce teklif hazırlanmalı) → AppException.validation', () async {
      final (repo, _) = make(
        (i, o) =>
            ScriptedResponse(400, {'error': 'Önce bir teklif hazırlanmalı.'}),
      );
      await expectLater(
        repo.sendQuote('o1'),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.validation)
              .having((e) => e.message, 'msg', 'Önce bir teklif hazırlanmalı.'),
        ),
      );
    });

    test('500 ayrıntısı maskelenir', () async {
      final (repo, _) = make(
        (i, o) => ScriptedResponse(500, {
          'error': 'relation "x" does not exist',
          'sent': false,
        }),
      );
      await expectLater(
        repo.sendQuote('o1'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'msg',
            AppException.serverMessage,
          ),
        ),
      );
    });
  });

  group('Teklif kaydet /quotes/:id', () {
    test('kalemler sözleşme biçiminde gider; fiyat noktalı metin', () async {
      final (repo, a) = make(
        (i, o) => ScriptedResponse(201, {
          'id': 'q1',
          'items': [],
          'subtotal': 1000,
          'tax': 200,
          'total': 1200,
        }),
      );
      final q = await repo.saveQuote('o1', [
        QuoteItem(desc: 'Pergola', qty: 1, price: Money.fromKurus(100000)),
        QuoteItem(
          desc: 'Bakım',
          qty: 2.5,
          price: Money.fromKurus(120050),
          vatIncluded: true,
        ),
      ]);
      expect(a.requests.single.path, '/quotes/o1');
      final items = (a.requests.single.data as Map)['items'] as List;
      expect(items[0], {
        'desc': 'Pergola',
        'qty': 1,
        'price': '1000.00',
        'vatIncluded': false,
      });
      expect(items[1]['price'], '1200.50');
      expect(items[1]['qty'], 2.5);
      expect(items[1]['vatIncluded'], true);
      expect(q.total, Money.fromKurus(120000));
    });

    test('geçersiz kalem ağa çıkmadan reddedilir', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(201, {}));
      await expectLater(
        repo.saveQuote('o1', const []),
        throwsA(isA<AppException>()),
      );
      expect(a.requests, isEmpty);
    });
  });

  group('Durum ve CRUD', () {
    test('durum PATCH: TAM yazım (İncelendi, Keşif Planlandı…)', () async {
      for (final s in OfferStatus.values) {
        final (repo, a) = make(
          (i, o) => ScriptedResponse(200, {...offerJson, 'status': s.api}),
        );
        final o = await repo.setOfferStatus('o1', s);
        expect((a.requests.single.data as Map)['status'], s.api);
        expect(a.requests.single.method, 'PATCH');
        expect(o.status, s.api);
      }
      expect(OfferStatus.values.map((e) => e.api), [
        'Yeni',
        'İncelendi',
        'Keşif Planlandı',
        'Teklif Verildi',
        'Kabul Edildi',
        'Reddedildi',
      ]);
    });

    test('409: kabul edilmiş teklif → conflict + sunucu mesajı', () async {
      final (repo, _) = make(
        (i, o) => ScriptedResponse(409, {
          'error': 'Kabul edilmiş teklifin durumu değiştirilemez.',
        }),
      );
      await expectLater(
        repo.setOfferStatus('o1', OfferStatus.yeni),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', AppErrorCode.conflict)
              .having((e) => e.message, 'm', contains('değiştirilemez')),
        ),
      );
    });

    test('createOffer: POST sonra tam kayıt GET', () async {
      final (repo, a) = make((i, o) {
        if (i == 0) return ScriptedResponse(201, {'id': 'o9', 'code': 'OFR-9'});
        return ScriptedResponse(200, {...offerJson, 'id': 'o9'});
      });
      final o = await repo.createOffer(
        const OfferDraft(name: 'A', phone: '0532', service: 'S'),
      );
      expect(a.requests[0].method, 'POST');
      expect(a.requests[0].path, '/offers');
      expect(a.requests[1].path, '/offers/o9');
      expect(o.id, 'o9');
    });

    test('updateOffer PATCH gövdesi: boş alanlar null (temizleme)', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(200, offerJson));
      await repo.updateOffer(
        'o1',
        const OfferDraft(name: 'A', phone: '1', service: 'S'),
      );
      final body = a.requests.single.data as Map;
      expect(body['email'], isNull);
      expect(body.containsKey('address'), true);
    });

    test('deleteOffer DELETE /offers/:id', () async {
      final (repo, a) = make(
        (i, o) => ScriptedResponse(200, {'message': 'ok'}),
      );
      await repo.deleteOffer('o1');
      expect(a.requests.single.method, 'DELETE');
      expect(a.requests.single.path, '/offers/o1');
    });
  });

  group('Projeye çevir', () {
    const prj = {
      'id': 'p7',
      'code': 'PRJ-7',
      'offer_id': 'o1',
      'customer_name': 'Ayşe Yılmaz',
      'stage': 'Malzeme Temini',
    };

    test(
      'zaten Kabul Edildi ve proje var → PATCH yok, mevcut projeye gider',
      () async {
        final (repo, a) = make(
          (i, o) => ScriptedResponse(
            200,
            [
              {...prj, 'id': 'baska', 'offer_id': 'x'},
              prj,
            ],
            {'x-total-count': '2'},
          ),
        );
        final r = await repo.offerToProject(
          Offer.fromJson({...offerJson, 'status': 'Kabul Edildi'}),
        );
        expect(r.projectId, 'p7');
        expect(r.created, false);
        expect(a.requests.where((x) => x.method == 'PATCH'), isEmpty);
      },
    );

    test('kabul edilmemiş → Kabul Edildi PATCH sonra proje bulunur', () async {
      final (repo, a) = make((i, o) {
        if (o.method == 'PATCH')
          return ScriptedResponse(200, {
            ...offerJson,
            'status': 'Kabul Edildi',
          });
        return ScriptedResponse(200, [prj], {'x-total-count': '1'});
      });
      final r = await repo.offerToProject(Offer.fromJson(offerJson));
      expect(a.requests.first.path, '/offers/o1/status');
      expect((a.requests.first.data as Map)['status'], 'Kabul Edildi');
      expect(r.projectId, 'p7');
      expect(r.created, true);
    });

    test('proje listede bulunamazsa projectId null', () async {
      final (repo, _) = make((i, o) {
        if (o.method == 'PATCH') return ScriptedResponse(200, offerJson);
        return ScriptedResponse(200, <Object>[], {'x-total-count': '0'});
      });
      final r = await repo.offerToProject(Offer.fromJson(offerJson));
      expect(r.projectId, isNull);
    });
  });

  group('Projeler', () {
    const pj = {
      'id': 'p1',
      'code': 'PRJ-1',
      'customer_name': 'Z',
      'stage': 'Üretim',
      'total_amount': 8500,
      'paid_amount': 4000,
    };

    test('liste: q/limit/offset, toplam başlıktan', () async {
      final (repo, a) = make(
        (i, o) => ScriptedResponse(200, [pj], {'x-total-count': '9'}),
      );
      final page = await repo.projects(q: 'z', limit: 30, offset: 30);
      expect(a.requests.single.path, '/projects');
      expect(a.requests.single.queryParameters['offset'], 30);
      expect(page.total, 9);
      expect(page.items.single.paidAmount, Money.fromKurus(400000));
    });

    test('/full çözümleme', () async {
      final (repo, a) = make(
        (i, o) => ScriptedResponse(200, {
          'project': pj,
          'tasks': [],
          'extras': [],
          'payments': [
            {'id': 'a', 'amount': 4000, 'method': 'Havale'},
          ],
          'expenses': [],
        }),
      );
      final f = await repo.projectFull('p1');
      expect(a.requests.single.path, '/projects/p1/full');
      expect(f.balance, Money.fromKurus(450000));
    });

    test('saha: /full YOK; dashboard-init + görevler (finans yok)', () async {
      final (repo, a) = make((i, o) {
        if (o.path == '/dashboard-init') {
          return ScriptedResponse(200, {
            'projects': [
              {
                'id': 'p1',
                'code': 'PRJ-1',
                'customer_name': 'Z',
                'stage': 'Üretim',
                'customer_phone': '0532',
              },
            ],
          });
        }
        return ScriptedResponse(200, [
          {'id': 't', 'project_id': 'p1', 'title': 'a', 'status': 'bekliyor'},
        ]);
      });
      final f = await repo.projectFull('p1', fieldMode: true);
      expect(a.requests.map((r) => r.path), [
        '/dashboard-init',
        '/projects/p1/tasks',
      ]);
      expect(f.project.totalAmount, isNull);
      expect(f.financeVisible, false);
      expect(f.payments, isEmpty);
      expect(f.tasks.single.title, 'a');
    });

    test('saha: projede erişim yoksa 404', () async {
      final (repo, _) = make((i, o) => ScriptedResponse(200, {'projects': []}));
      await expectLater(
        repo.projectFull('yok', fieldMode: true),
        throwsA(
          isA<AppException>().having((e) => e.code, 'c', AppErrorCode.notFound),
        ),
      );
    });

    test('aşama PATCH: TAM yazım', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(200, pj));
      await repo.setStage('p1', ProjectStage.tamamlandi);
      expect(a.requests.single.path, '/projects/p1/stage');
      expect((a.requests.single.data as Map)['stage'], 'Tamamlandı');
    });

    test('tutar: negatif reddedilir, noktalı metin gider', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(200, pj));
      await expectLater(
        repo.setAmount('p1', Money.fromKurus(-1)),
        throwsA(isA<AppException>()),
      );
      expect(a.requests, isEmpty);
      await repo.setAmount('p1', Money.fromKurus(1250050));
      expect((a.requests.single.data as Map)['total_amount'], '12500.50');
    });

    test(
      'tarihler: İstanbul öğlen ISO; clearEnd yalnız isteyince null yollar',
      () async {
        final (repo, a) = make((i, o) => ScriptedResponse(200, pj));
        await repo.setDates('p1', end: DateTime.utc(2026, 11, 25, 9));
        expect(
          (a.requests.last.data as Map)['end_date'],
          '2026-11-25T12:00:00+03:00',
        );
        expect((a.requests.last.data as Map).containsKey('start_date'), false);
        await repo.setDates('p1', start: DateTime.utc(2026, 11, 1, 9));
        expect(
          (a.requests.last.data as Map).containsKey('end_date'),
          false,
        ); // yanlışlıkla temizlenmez
        await repo.setDates('p1', clearEnd: true);
        expect((a.requests.last.data as Map)['end_date'], isNull);
        expect((a.requests.last.data as Map).containsKey('end_date'), true);
      },
    );

    test('görev ve ilave iş uçları', () async {
      final (repo, a) = make((i, o) {
        if (o.path.endsWith('/tasks')) {
          return ScriptedResponse(201, {
            'id': 't1',
            'project_id': 'p1',
            'title': 'Ölç',
            'status': 'bekliyor',
          });
        }
        if (o.path.endsWith('/extras')) {
          return ScriptedResponse(201, {
            'id': 'e1',
            'description': 'ek',
            'amount': -250,
          });
        }
        return ScriptedResponse(200, {'message': 'ok'});
      });
      final t = await repo.addTask('p1', ' Ölç ', assignedUserId: 'u1');
      expect(t.title, 'Ölç');
      expect((a.requests[0].data as Map), {
        'title': 'Ölç',
        'assigned_user_id': 'u1',
      });
      await repo.setTaskStatus('t1', TaskStatus.devamEdiyor);
      expect(a.requests[1].path, '/projects/tasks/t1');
      expect((a.requests[1].data as Map)['status'], 'devam_ediyor');
      await repo.deleteTask('t1');
      expect(a.requests[2].method, 'DELETE');
      final e = await repo.addExtra('p1', 'indirim', Money.fromKurus(-25000));
      expect((a.requests[3].data as Map)['amount'], '-250.00');
      expect(e.amount, Money.fromKurus(-25000));
      await repo.deleteExtra('e1');
      expect(a.requests[4].path, '/projects/extras/e1');
      await expectLater(repo.addTask('p1', '  '), throwsA(isA<AppException>()));
    });

    test('createProject gövdesi ve 201 çözümleme', () async {
      final (repo, a) = make((i, o) => ScriptedResponse(201, pj));
      final p = await repo.createProject(
        const ProjectDraft(
          customerName: 'Z',
          service: 'S',
          totalAmount: Money.zero,
        ),
      );
      expect(a.requests.single.path, '/projects');
      expect((a.requests.single.data as Map)['total_amount'], '0.00');
      expect(p.code, 'PRJ-1');
    });
  });

  group('Belgeler / paylaşım / aktivite', () {
    test('liste + silme + paylaşım', () async {
      final (repo, a) = make((i, o) {
        if (o.path.startsWith('/documents') && o.method == 'GET') {
          return ScriptedResponse(200, [
            {
              'id': 'd1',
              'file_url': 'https://a/f.pdf?exp=1&sig=2',
              'file_name': 'f.pdf',
              'uploaded_by_name': 'A',
            },
          ]);
        }
        if (o.path.startsWith('/shares') && o.method == 'GET') {
          return ScriptedResponse(200, [
            {
              'id': 's1',
              'shared_with_user_id': 'u2',
              'user_name': 'Pers',
              'user_email': 'p@x',
            },
          ]);
        }
        if (o.path.startsWith('/activity')) {
          return ScriptedResponse(200, [
            {
              'id': 'a1',
              'action': 'asama_degisti',
              'details': 'Montaj',
              'user_name': 'A',
              'created_at': '2026-11-20T09:00:00Z',
            },
          ]);
        }
        return ScriptedResponse(200, {'message': 'ok'});
      });
      final docs = await repo.documents('project', 'p1');
      expect(a.requests.last.path, '/documents/project/p1');
      expect(docs.single.isPdf, true);
      await repo.deleteDocument('d1');
      expect(a.requests.last.path, '/documents/d1');
      final sh = await repo.shares('offer', 'o1');
      expect(sh.single.userName, 'Pers');
      await repo.addShare('offer', 'o1', 'u2');
      expect(a.requests.last.data, {
        'resource_type': 'offer',
        'resource_id': 'o1',
        'user_id': 'u2',
      });
      await repo.removeShare('s1');
      expect(a.requests.last.path, '/shares/s1');
      final act = await repo.activity('project', 'p1');
      expect(act.single.label, 'Aşama değişti');
    });

    test(
      'yükleme: multipart, alan adı "file", Content-Type elle verilmez',
      () async {
        final dir = await Directory.systemTemp.createTemp('jobs_up');
        addTearDown(() => dir.delete(recursive: true));
        final f = File('${dir.path}/foto.jpg')..writeAsBytesSync([1, 2, 3, 4]);
        final (repo, a) = make(
          (i, o) => ScriptedResponse(201, {
            'id': 'd2',
            'file_url': 'https://a/foto.jpg?exp=1&sig=2',
            'file_name': 'foto.jpg',
          }),
        );
        final d = await repo.uploadDocument(
          'project',
          'p1',
          filePath: f.path,
          fileName: 'foto.jpg',
        );
        final req = a.requests.single;
        expect(req.path, '/documents/project/p1');
        expect(req.data, isA<FormData>());
        final form = req.data as FormData;
        expect(form.files.single.key, 'file');
        expect(form.files.single.value.filename, 'foto.jpg');
        expect(d.isImage, true);
      },
    );

    test('yükleme 400 (uzantı) → doğrulama hatası mesajı', () async {
      final dir = await Directory.systemTemp.createTemp('jobs_up');
      addTearDown(() => dir.delete(recursive: true));
      final f = File('${dir.path}/a.pdf')..writeAsBytesSync([1]);
      final (repo, _) = make(
        (i, o) => ScriptedResponse(400, {
          'error': 'Dosya içeriği uzantısıyla uyuşmuyor; yüklenemez.',
        }),
      );
      await expectLater(
        repo.uploadDocument('offer', 'o1', filePath: f.path, fileName: 'a.pdf'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'm',
            contains('uyuşmuyor'),
          ),
        ),
      );
    });

    test('şablonlar GET /quote-templates; 403 anlaşılır', () async {
      final (repo, _) = make(
        (i, o) => ScriptedResponse(200, [
          {
            'id': 't',
            'name': 'Paket',
            'items': [
              {'desc': 'A', 'qty': 1, 'price': 10, 'vatIncluded': true},
            ],
          },
        ]),
      );
      final t = await repo.quoteTemplates();
      expect(t.single.items.single.vatIncluded, true);
      final (r2, _) = make(
        (i, o) =>
            ScriptedResponse(403, {'error': 'Bu işlem için yetkiniz yok.'}),
      );
      await expectLater(
        r2.quoteTemplates(),
        throwsA(
          isA<AppException>().having(
            (e) => e.code,
            'c',
            AppErrorCode.forbidden,
          ),
        ),
      );
    });
  });
}
