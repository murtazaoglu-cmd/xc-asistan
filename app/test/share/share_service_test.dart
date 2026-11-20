import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:xc_asistan/core/share/share_service.dart';

import '../helpers/fakes.dart';

SharedMediaFile m(String path, SharedMediaType t, {String? mime}) =>
    SharedMediaFile(path: path, type: t, mimeType: mime);

void main() {
  test('metin ve dosya ayrışır; WhatsApp dışa aktarımı tanınır', () {
    final s = ShareService.toReceivedShare([
      m('  Merhaba  ', SharedMediaType.text),
      m(
        '/data/user/0/cache/WhatsApp Chat with Ayşe.zip',
        SharedMediaType.file,
        mime: 'application/zip',
      ),
      m('/x/foto.JPG', SharedMediaType.image, mime: 'image/jpeg'),
    ], now: DateTime.utc(2026, 11, 20))!;
    expect(s.text, 'Merhaba');
    expect(s.files.length, 2);
    expect(s.files.first.name, 'WhatsApp Chat with Ayşe.zip');
    expect(s.files.first.isZip, isTrue);
    expect(s.files.last.isImage, isTrue);
    expect(s.looksLikeWhatsAppExport, isTrue);
  });

  test('boş/yalnız boşluk paylaşım null', () {
    expect(ShareService.toReceivedShare([]), isNull);
    expect(
      ShareService.toReceivedShare([m('   ', SharedMediaType.text)]),
      isNull,
    );
  });

  test('Windows yolu dosya adı çıkarır; WhatsApp olmayan txt', () {
    final s = ShareService.toReceivedShare([
      m(r'C:\a\b\not.txt', SharedMediaType.file, mime: 'text/plain'),
    ])!;
    expect(s.files.single.name, 'not.txt');
    expect(s.files.single.isText, isTrue);
    expect(s.looksLikeWhatsAppExport, isFalse);
  });

  test(
    'soğuk açılış + sonradan gelen paylaşımlar akışa düşer, reset çağrılır',
    () async {
      final src = FakeShareSource([m('ilk', SharedMediaType.text)]);
      final svc = ShareService(src);
      final got = <String?>[];
      svc.shares.listen((s) => got.add(s.text));
      await svc.start();
      await svc.start(); // ikinci çağrı güvenli
      src.ctrl.add([m('ikinci', SharedMediaType.text)]);
      await Future<void>.delayed(Duration.zero);
      expect(got, ['ilk', 'ikinci']);
      expect(src.resets, 2);
    },
  );
}
