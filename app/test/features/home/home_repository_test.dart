import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/api/api_client.dart';
import 'package:xc_asistan/core/api/api_exception.dart';
import 'package:xc_asistan/features/home/data/home_repository.dart';

import '../../helpers/fakes.dart';
import 'home_models_test.dart' show contractSample;

HttpHomeRepository repo(ScriptedAdapter a) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api'))
    ..httpClientAdapter = a;
  return HttpHomeRepository(ApiClient(dio));
}

void main() {
  test('fetch: GET /mobile/home okur', () async {
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(200, contractSample()),
    );
    final s = await repo(a).fetch();
    expect(a.requests.single.method, 'GET');
    expect(a.requests.single.uri.path, '/api/mobile/home');
    expect(s.newOfferCount, 6);
  });

  test('fetch: 401/500/çevrimdışı AppException olur', () async {
    final server = ScriptedAdapter(
      (i, o) => ScriptedResponse(500, {'error': 'Sunucu hatası'}),
    );
    await expectLater(repo(server).fetch(), throwsA(isA<AppException>()));
    final off = ScriptedAdapter(
      (i, o) => ScriptedResponse.error(DioExceptionType.connectionError, o),
    );
    await expectLater(repo(off).fetch(), throwsA(isA<AppException>()));
  });

  test('setReminderStatus: PATCH /reminders/:id {status}', () async {
    final a = ScriptedAdapter((i, o) => ScriptedResponse(200, {'id': 'r1'}));
    await repo(a).setReminderStatus('r1', 'tamamlandi');
    final r = a.requests.single;
    expect(r.method, 'PATCH');
    expect(r.uri.path, '/api/reminders/r1');
    expect(r.data, {'status': 'tamamlandi'});
  });

  test('createReminder: POST /reminders, +03:00 zamanı, boş not yok', () async {
    final a = ScriptedAdapter((i, o) => ScriptedResponse(201, {'id': 'n'}));
    await repo(a).createReminder(
      title: 'Ara',
      remindAt: DateTime.utc(2026, 11, 21, 6),
      projectId: 'p1',
      note: '  ',
    );
    final r = a.requests.single;
    expect(r.method, 'POST');
    expect(r.uri.path, '/api/reminders');
    final d = r.data as Map;
    expect(d['title'], 'Ara');
    expect(d['remind_at'], '2026-11-21T09:00:00+03:00');
    expect(d['project_id'], 'p1');
    expect(d.containsKey('note'), isFalse);
  });

  test(
    'uploadDocument: multipart POST /documents/:type/:id alan file',
    () async {
      final dir = Directory.systemTemp.createTempSync('xc_up');
      addTearDown(() => dir.deleteSync(recursive: true));
      final f = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      final a = ScriptedAdapter((i, o) => ScriptedResponse(201, {'id': 'd1'}));
      await repo(a).uploadDocument(
        resourceType: 'offer',
        resourceId: 'o1',
        filePath: f.path,
        fileName: 'a.jpg',
      );
      final r = a.requests.single;
      expect(r.method, 'POST');
      expect(r.uri.path, '/api/documents/offer/o1');
      final form = r.data as FormData;
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'a.jpg');
    },
  );

  test('uploadDocument: 403 AppException', () async {
    final dir = Directory.systemTemp.createTempSync('xc_up');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File('${dir.path}/a.jpg')..writeAsBytesSync([1]);
    final a = ScriptedAdapter(
      (i, o) => ScriptedResponse(403, {'error': 'Yetkiniz yok'}),
    );
    await expectLater(
      repo(a).uploadDocument(
        resourceType: 'project',
        resourceId: 'p',
        filePath: f.path,
      ),
      throwsA(isA<AppException>()),
    );
  });
}
