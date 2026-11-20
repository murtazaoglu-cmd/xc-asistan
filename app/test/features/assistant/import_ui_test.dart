import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/share/received_share.dart';
import 'package:xc_asistan/core/share/share_service.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/assistant/application/import_flow.dart';
import 'package:xc_asistan/features/assistant/application/import_picker.dart';
import 'package:xc_asistan/features/assistant/presentation/conversation_section.dart';
import 'package:xc_asistan/features/assistant/presentation/share_inbox_screen.dart';

import 'harness.dart';

class _FakePicker implements ImportFilePicker {
  @override
  Future<ImportSource?> pick({String? customerKey}) async => ImportSource(
    filePath: '/tmp/WhatsApp Chat.txt',
    fileName: 'WhatsApp Chat.txt',
    customerKey: customerKey,
  );
}

void main() {
  test(
    'paylaşımdan kaynak: dosya metne tercih edilir; desteklenmeyen null',
    () {
      final f = importSourceFromShare(
        text: 'merhaba',
        files: [(path: '/a/chat.txt', name: 'chat.txt', isTextOrZip: true)],
      );
      expect(f!.isFile, isTrue);
      final t = importSourceFromShare(text: '  merhaba  ');
      expect(t!.text, 'merhaba');
      expect(
        importSourceFromShare(
          files: [(path: '/a/x.jpg', name: 'x.jpg', isTextOrZip: false)],
        ),
        isNull,
      );
      expect(importSourceFromShare(), isNull);
    },
  );

  testWidgets('paylaşım gelir → aydınlatma → rıza → önizleme → kaydet → bitti', (
    t,
  ) async {
    await pumpScreen(t, const ShareInboxScreen(), size: const Size(400, 1600));
    await settle(t);
    expect(find.textContaining('Dosya seç'), findsOneWidget);

    final container = ProviderScope.containerOf(
      t.element(find.byType(ShareInboxScreen)),
    );
    container
        .read(receivedShareProvider.notifier)
        .receive(
          ReceivedShare(
            text:
                '[12.11.2026 10:00] Ahmet: Merhaba, keşif için müsait misiniz?',
            receivedAt: Ist.now(),
          ),
        );
    await settle(t);
    // Paylaşım tüketildi; rıza ekranı.
    expect(container.read(receivedShareProvider), isNull);
    expect(find.textContaining('aydınlatma'), findsOneWidget);
    final next = find.widgetWithText(FilledButton, 'Devam et');
    expect(
      t.widget<FilledButton>(next).onPressed,
      isNull,
      reason: 'Rıza verilmeden devam edilemez',
    );

    await t.tap(find.byType(CheckboxListTile));
    await settle(t);
    expect(t.widget<FilledButton>(next).onPressed, isNotNull);

    await t.tap(next);
    await settle(t, 20);
    expect(find.text('Önizleme'), findsOneWidget);
    expect(find.textContaining('mesaj'), findsWidgets);
    final save = find.widgetWithText(
      FilledButton,
      'Yazışmayı kaydet ve önerileri çıkar',
    );
    expect(find.text('Siz hangisisiniz?'), findsOneWidget);

    // Sohbetin sahibini seç; müşteri eşleşmediyse bağlamadan devam et.
    final owner = container.read(importFlowProvider).preview!.participants.last;
    await t.tap(find.widgetWithText(ChoiceChip, owner));
    await settle(t);
    if (find.text('Müşteriyi eşleştirelim').evaluate().isNotEmpty) {
      await t.ensureVisible(find.text('Müşteriye bağlama'));
      await t.tap(find.text('Müşteriye bağlama'));
      await settle(t);
    }
    await t.ensureVisible(save);
    await t.tap(save);
    await settle(t, 20);
    expect(find.text('Yazışma kaydedildi'), findsOneWidget);
    expect(find.text('Önerilere bak'), findsOneWidget);
  });

  testWidgets('saha: içe aktarma kapalı', (t) async {
    await pumpScreen(t, const ShareInboxScreen(), role: UserRole.saha);
    await settle(t);
    expect(find.text('Bu bölüm sizin için kapalı'), findsOneWidget);
  });

  testWidgets('dosya seçici sahte ile rıza ekranına gider', (t) async {
    await pumpScreen(
      t,
      const ShareInboxScreen(customerKey: '5321110000'),
      overrides: [importFilePickerProvider.overrideWithValue(_FakePicker())],
    );
    await settle(t);
    await t.tap(find.textContaining('Dosya seç'));
    await settle(t);
    expect(find.textContaining('WhatsApp Chat.txt'), findsOneWidget);
  });

  group('Müşteri kartı yazışma bölümü', () {
    testWidgets('boş durum, "Yazışma ekle" ve silme düğmesi', (t) async {
      await pumpScreen(
        t,
        const AssistantConversationSection(
          phoneKey: '05321110000',
          name: 'Ahmet Yılmaz',
        ),
      );
      await settle(t);
      expect(find.text('Yazışma ekle'), findsOneWidget);
      expect(find.text('Tüm yazışma verisini sil'), findsOneWidget);
    });

    testWidgets('saha: bölüm görünmez', (t) async {
      await pumpScreen(
        t,
        const AssistantConversationSection(phoneKey: '05321110000'),
        role: UserRole.saha,
      );
      await settle(t);
      expect(find.text('Yazışma ekle'), findsNothing);
    });

    testWidgets('Yazışma ekle: müşteri ön ayarlı paylaşım rotası', (t) async {
      final router = await pumpScreen(
        t,
        const AssistantConversationSection(phoneKey: '905321110000'),
      );
      await settle(t);
      await t.tap(find.text('Yazışma ekle'));
      await settle(t);
      expect(router.state.uri.path, '/assistant/share');
      expect(router.state.uri.queryParameters['customer'], '5321110000');
    });
  });
}
