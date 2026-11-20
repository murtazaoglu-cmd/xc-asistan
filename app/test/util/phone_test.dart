import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/phone.dart';

void main() {
  test('0532… → 90532…', () {
    expect(PhoneUtil.toInternational('0532 111 22 33'), '905321112233');
    expect(PhoneUtil.toInternational('(0532) 111-22-33'), '905321112233');
    expect(PhoneUtil.toInternational('532 111 22 33'), '905321112233');
    expect(PhoneUtil.toInternational('+90 532 111 22 33'), '905321112233');
    expect(PhoneUtil.toInternational('0090 532 111 22 33'), '905321112233');
    expect(PhoneUtil.toInternational('905321112233'), '905321112233');
  });

  test('yurt dışı korunur, geçersiz null', () {
    expect(PhoneUtil.toInternational('+49 170 1234567'), '491701234567');
    expect(PhoneUtil.toInternational('123'), isNull);
    expect(PhoneUtil.toInternational(''), isNull);
    expect(PhoneUtil.toInternational(null), isNull);
  });

  test('phone_key yalnız rakam', () {
    expect(PhoneUtil.phoneKey('0532 111 22 33'), '05321112233');
  });

  test('tel ve WhatsApp bağlantıları', () {
    expect(PhoneUtil.telUri('0532 111 22 33').toString(), 'tel:+905321112233');
    final app = PhoneUtil.whatsappAppUri(
      '0532 111 22 33',
      text: 'Merhaba Ayşe',
    )!;
    expect(app.scheme, 'whatsapp');
    expect(app.host, 'send');
    expect(app.queryParameters, {
      'phone': '905321112233',
      'text': 'Merhaba Ayşe',
    });
    final web = PhoneUtil.whatsappWebUri(
      '0532 111 22 33',
      text: 'Merhaba Ayşe',
    )!;
    expect(
      web.toString(),
      'https://wa.me/905321112233?text=Merhaba%20Ay%C5%9Fe',
    );
    expect(
      PhoneUtil.whatsappWebUri('0532 111 22 33')!.toString(),
      'https://wa.me/905321112233',
    );
    expect(PhoneUtil.whatsappAppUri('12'), isNull);
  });

  test('gösterim', () {
    expect(PhoneUtil.formatDisplay('05321112233'), '0532 111 22 33');
    expect(PhoneUtil.formatDisplay('+905321112233'), '0532 111 22 33');
    expect(PhoneUtil.formatDisplay('abc'), 'abc');
  });
}
