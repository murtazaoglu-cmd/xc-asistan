// Web yardımcıları: CSV, sayfa başlığı, seçilen dosya deposu, yükleme (bayttan), demo jeton deposu.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xc_asistan/app_wiring.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/files/picked_files.dart';
import 'package:xc_asistan/core/storage/token_store.dart';
import 'package:xc_asistan/core/util/csv.dart';
import 'package:xc_asistan/core/web/browser.dart';
import 'package:xc_asistan/core/web/page_title.dart';
import 'package:xc_asistan/features/invoices_vat/data/invoices_vat_models.dart';

import '../helpers/fakes.dart';

void main() {
  group('Csv (Türkçe Excel uyumlu)', () {
    test('BOM + noktalı virgül + CRLF + tırnaklama', () {
      final b = Csv.bytes(
        ['Ad', 'Not'],
        [
          ['Ayşe; Yılmaz', 'He said "ok"'],
          ['Çağrı', 'iki\nsatır'],
        ],
      );
      expect(b.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(b.sublist(3));
      expect(
        text,
        'Ad;Not\r\n"Ayşe; Yılmaz";"He said ""ok"""\r\nÇağrı;"iki\nsatır"',
      );
    });

    test('formül enjeksiyonu etkisizleşir; eksi tutar bozulmaz', () {
      final t = Csv.encode(
        ['x'],
        [
          ['=HYPERLINK("http://x")'],
          ['@SUM(1)'],
          ['-cmd'],
          ['-₺6.550,50'],
          ['+90 532'],
        ],
      );
      final lines = t.split('\r\n');
      expect(lines[1], startsWith("\"'=HYPERLINK") /* tırnaklı */);
      expect(lines[2], "'@SUM(1)");
      expect(lines[3], "'-cmd");
      expect(lines[4], '-₺6.550,50');
      expect(lines[5], '+90 532');
    });
  });

  group('Sekme başlığı', () {
    const g = Glossary();
    test('rota → sayfa adı', () {
      expect(pageNameFor('/today', g), 'Bugün');
      expect(pageNameFor('/jobs', g), 'İşler');
      expect(pageNameFor('/jobs/offers/o1', g), 'Teklif');
      expect(pageNameFor('/jobs/projects/p1', g), 'İş ayrıntısı');
      expect(pageNameFor('/customers/05321112233', g), 'Müşteri kartı');
      expect(pageNameFor('/customers/new', g), 'Yeni müşteri');
      expect(pageNameFor('/finance', g), 'Para');
      expect(pageNameFor('/invoices-vat', g), 'Fatura / KDV');
      expect(pageNameFor('/reports', g), 'Raporlar');
      expect(pageNameFor('/settings/password', g), 'Şifre değiştir');
      expect(pageNameFor('/login', g), 'Giriş');
      expect(pageNameFor('/splash', g), isNull);
      expect(pageNameFor('/bilinmeyen', g), isNull);
    });
    test('belge başlığı', () {
      expect(
        documentTitleFor('/reports', g, 'XC Asistan'),
        'Raporlar · XC Asistan',
      );
      expect(documentTitleFor('/splash', g, 'XC Asistan'), 'XC Asistan');
    });
  });

  group('PickedFileStore + yükleme', () {
    test('bellek yolu bayt verir; unut siler; blob web dışında null', () async {
      final path = PickedFileStore.put(Uint8List.fromList([1, 2, 3]));
      expect(PickedFileStore.isMemory(path), isTrue);
      expect(PickedFileStore.sizeOf(path), 3);
      expect(await PickedFileStore.read(path), [1, 2, 3]);
      PickedFileStore.forget(path);
      expect(await PickedFileStore.read(path), isNull);
      expect(await PickedFileStore.read('blob:http://x/1'), isNull);
      expect(await PickedFileStore.read('/tmp/gercek.pdf'), isNull);
    });

    test(
      'ApiClient.upload bellek yolunu multipart bayt olarak gönderir',
      () async {
        final adapter = ScriptedAdapter(
          (i, o) => ScriptedResponse(200, {'ok': true}),
        );
        final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
          ..httpClientAdapter = adapter;
        final path = PickedFileStore.put(
          Uint8List.fromList(List.filled(10, 7)),
        );
        await ApiClient(dio).upload(
          '/documents/x',
          field: 'file',
          filePath: path,
          fileName: 'fatura.pdf',
        );
        final form = adapter.requests.single.data as FormData;
        expect(form.files.single.key, 'file');
        expect(form.files.single.value.filename, 'fatura.pdf');
        expect(form.files.single.value.length, 10);
      },
    );

    test('okunamayan bellek yolu: anlaşılır hata (çökme yok)', () async {
      final adapter = ScriptedAdapter((i, o) => ScriptedResponse(200, {}));
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
        ..httpClientAdapter = adapter;
      expect(
        () =>
            ApiClient(dio).upload('/d', field: 'file', filePath: 'xcmem://yok'),
        throwsA(isA<Object>()),
      );
      expect(adapter.requests, isEmpty);
    });
  });

  group('Platform korumaları (web dışında güvenli)', () {
    test('tarayıcı işlemleri web dışında false/null döner', () async {
      expect(await browserDownload(Uint8List(1), 'a.csv', 'text/csv'), isFalse);
      expect(
        browserPrintTable(
          't',
          ['a'],
          [
            ['b'],
          ],
        ),
        isFalse,
      );
      expect(await browserReadBlob('blob:x'), isNull);
    });

    test(
      'WebDownloadExportSharer indirme başlatılamazsa UnsupportedError',
      () async {
        final f = ExportFile(
          bytes: Uint8List.fromList([1]),
          filename: 'kdv.xlsx',
          mime: 'application/octet-stream',
        );
        await expectLater(
          WebDownloadExportSharer().deliver(f),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });

  group('PrefsTokenStore (DEMO web: F5 sonrası oturum)', () {
    test('yaz / oku / temizle', () async {
      SharedPreferences.setMockInitialValues({});
      final s = PrefsTokenStore(await SharedPreferences.getInstance());
      expect(await s.readToken(), isNull);
      await s.writeToken('demo-token-admin');
      await s.writeMeCache('{"a":1}');
      expect(await s.readToken(), 'demo-token-admin');
      expect(await s.readMeCache(), '{"a":1}');
      await s.clear();
      expect(await s.readToken(), isNull);
      expect(await s.readMeCache(), isNull);
    });
  });
}
