import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/features/assistant/application/chat_controller.dart';
import 'package:xc_asistan/features/assistant/application/chat_models.dart';
import 'package:xc_asistan/features/assistant/data/command_models.dart';

import 'harness.dart';

Future<ChatNotifier> _chat(
  Future<void> Function(ChatNotifier n, dynamic c) body, {
  UserRole role = UserRole.admin,
}) async {
  final c = containerFor(await assistantOverrides(role: role));
  final n = c.read(chatControllerProvider.notifier);
  await body(n, c);
  return n;
}

ChatState _s(dynamic c) => c.read(chatControllerProvider) as ChatState;

void main() {
  test('answer: kullanıcı balonu + yanıt, veri korunur', () async {
    await _chat((n, c) async {
      await n.send('Bu ay ne kadar tahsilat?');
      final m = _s(c).messages;
      expect(m.first.isUser, isTrue);
      expect(m.last.kind, ChatKind.answer);
      expect(m.last.text, contains('tahsilat'));
      expect(m.last.data['total_kurus'], 9200000);
    });
  });

  test('anlaşılmayan komut: "ne demek istediniz?" seçenekleri', () async {
    await _chat((n, c) async {
      await n.send('blah blah');
      final last = _s(c).messages.last;
      expect(last.kind, ChatKind.options);
      expect(last.chips, isNotEmpty);
    });
  });

  test('boş ve çok uzun komut gönderilmez', () async {
    await _chat((n, c) async {
      await n.send('   ');
      expect(_s(c).messages, isEmpty);
      await n.send('a' * (maxCommandLength + 1));
      expect(_s(c).messages, isEmpty);
      expect(_s(c).notice, isNotNull);
    });
  });

  test('clarify → seçimle komut yeniden gider → onay kartı', () async {
    await _chat((n, c) async {
      await n.send('Ahmet için randevu ekle');
      final q = _s(c).messages.last;
      expect(q.kind, ChatKind.clarify);
      expect(q.questions.single.options.length, 2);
      await n.answerClarify(
        q.id,
        'customer_key',
        '5321112222',
        label: 'Ahmet Kaya',
      );
      final s = _s(c);
      expect(s.messages.where((m) => m.isUser).last.text, 'Ahmet Kaya');
      expect(s.messages.last.kind, ChatKind.card);
      expect(s.messages.last.card!.title, contains('Ahmet Kaya'));
      expect(
        s.messages.firstWhere((m) => m.kind == ChatKind.clarify).resolved,
        isTrue,
      );
    });
  });

  test('onayla → uygulandı → geri al → geri alındı', () async {
    await _chat((n, c) async {
      await n.send('Ahmet için randevu ekle');
      await n.answerClarify(
        _s(c).messages.last.id,
        'customer_key',
        '5321110000',
      );
      final id = _s(c).messages.last.cardId!;
      expect(_s(c).messages.last.card!.isPending, isTrue);

      await n.confirm(id);
      var card = _s(c).messages.last.card!;
      expect(card.status, CardStatus.uygulandi);
      expect(card.canUndo(), isTrue);

      await n.undo(id);
      card = _s(c).messages.last.card!;
      expect(card.status, CardStatus.geriAlindi);
      expect(card.canUndo(), isFalse);
      expect(_s(c).busyCards, isEmpty);
    });
  });

  test(
    'vazgeç → reddedildi; ikinci onay 409 hatası kartta gösterilir',
    () async {
      await _chat((n, c) async {
        await n.send('Ödeme ekle');
        final id = _s(c).messages.last.cardId!;
        await n.reject(id);
        expect(_s(c).messages.last.card!.status, CardStatus.reddedildi);
        await n.confirm(id);
        expect(_s(c).messages.last.card!.status, CardStatus.reddedildi);
        expect(_s(c).busyCards, isEmpty);
      });
    },
  );

  test('silme isteği reddedilir (asistan silmez)', () async {
    await _chat((n, c) async {
      await n.send('müşteriyi sil');
      final m = _s(c).messages.last;
      expect(m.refused, isTrue);
    });
  });

  test('saha: randevu komutu 403 → hata balonu', () async {
    await _chat((n, c) async {
      await n.send('randevu ekle');
      expect(_s(c).messages.last.kind, ChatKind.error);
    }, role: UserRole.saha);
  });

  test(
    'sohbet geçmişi kısa ve kullanıcıya özel saklanır; temizlenir',
    () async {
      final c = containerFor(await assistantOverrides());
      final n = c.read(chatControllerProvider.notifier);
      await n.send('Bugün ne var?');
      final store = c.read(chatHistoryStoreProvider);
      expect(store.load('anon'), isNotEmpty);
      await n.clear();
      expect(store.load('anon'), isEmpty);
      expect(_s(c).messages, isEmpty);
    },
  );

  test('geçmiş en çok 30 mesaj tutar', () async {
    final c = containerFor(await assistantOverrides());
    final n = c.read(chatControllerProvider.notifier);
    for (var i = 0; i < 20; i++) {
      await n.send('Bugün ne var?');
    }
    expect(
      c.read(chatHistoryStoreProvider).load('anon').length,
      lessThanOrEqualTo(ChatHistoryStore.maxMessages),
    );
  });
}
