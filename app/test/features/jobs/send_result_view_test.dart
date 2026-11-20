import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/theme/app_theme.dart';
import 'package:xc_asistan/features/jobs/data/jobs_models.dart';
import 'package:xc_asistan/features/jobs/presentation/send_result_view.dart';

Future<void> show(WidgetTester t, int status, Map<String, Object?> body) async {
  final r = QuoteSendResult.fromResponse(status, body);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SendResultView(result: r, onAction: (_) {}),
      ),
    ),
  );
}

String title(WidgetTester t) =>
    (t.widget(find.byKey(const ValueKey('send-result-title'))) as Text).data!;

void main() {
  testWidgets('200: Gönderildi', (t) async {
    await show(t, 200, {
      'sent': true,
      'channel': 'whatsapp',
      'status': 'gonderildi',
      'channels': {
        'whatsapp': {'sent': true},
        'email': {'sent': false, 'skipped': true},
      },
    });
    expect(title(t), 'Gönderildi');
    expect(find.text('Gönderilemedi'), findsNothing);
  });

  testWidgets('207: Kısmen, hata görünür', (t) async {
    await show(t, 207, {
      'sent': true,
      'channel': 'email',
      'status': 'kismen',
      'channels': {
        'whatsapp': {'sent': false, 'error': 'numara geçersiz'},
        'email': {'sent': true},
      },
    });
    expect(title(t), 'Kısmen gönderildi');
    expect(find.textContaining('numara geçersiz'), findsOneWidget);
  });

  testWidgets('502: Gönderilemedi, "Gönderildi" başlığı YOK, tekrar dene var', (
    t,
  ) async {
    await show(t, 502, {
      'sent': false,
      'status': 'basarisiz',
      'error': 'WhatsApp: hata',
      'channels': {
        'whatsapp': {'sent': false, 'error': 'hata'},
        'email': {'sent': false, 'skipped': true},
      },
    });
    expect(title(t), 'Gönderilemedi');
    expect(find.text('Gönderildi'), findsNothing);
    expect(find.text('Tekrar dene'), findsOneWidget);
  });
}
