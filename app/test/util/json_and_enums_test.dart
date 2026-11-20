import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/domain_enums.dart';
import 'package:xc_asistan/core/util/json.dart';
import 'package:xc_asistan/core/util/money.dart';

void main() {
  test('JsonReader null-güvenli', () {
    final j = <String, dynamic>{
      'a': 5,
      'b': '7',
      'c': null,
      'd': 'x',
      'e': '2026-11-20T16:00:00Z',
      'f': 1250.5,
      'g': ' ',
      'h': [1, 'x'],
      'i': {'k': 1},
      'j': true,
      'k': 'true',
    };
    expect(j.intOrNull('a'), 5);
    expect(j.intOrNull('b'), 7);
    expect(j.intOrNull('c'), isNull);
    expect(j.intOrNull('d'), isNull);
    expect(j.intOr('zz', 9), 9);
    expect(j.str('a'), '5');
    expect(j.strOrNull('g'), isNull);
    expect(j.strOr('c', 'yok'), 'yok');
    expect(j.dateTime('e'), DateTime.utc(2026, 11, 20, 16));
    expect(j.dateTime('d'), isNull);
    expect(j.money('f'), Money.fromTl(1250.5));
    expect(j.money('c'), Money.zero);
    expect(j.stringList('h'), ['1', 'x']);
    expect(j.mapOrNull('i'), {'k': 1});
    expect(j.mapOrNull('a'), isNull);
    expect(j.boolOr('j'), isTrue);
    expect(j.boolOr('k'), isTrue);
    expect(asJsonList('x'), isEmpty);
    expect(
      asJsonList([
        {'a': 1},
        5,
      ]).length,
      1,
    );
  });

  test('enum yazımları sözleşmeyle birebir', () {
    expect(OfferStatus.fromApi('Keşif Planlandı'), OfferStatus.kesifPlanlandi);
    expect(OfferStatus.fromApi('Kesif Planlandi'), isNull);
    expect(OfferStatus.values.map((e) => e.api), [
      'Yeni',
      'İncelendi',
      'Keşif Planlandı',
      'Teklif Verildi',
      'Kabul Edildi',
      'Reddedildi',
    ]);
    expect(ProjectStage.values.map((e) => e.api), [
      'Malzeme Temini',
      'Üretim',
      'Montaj',
      'Teslim',
      'Tamamlandı',
    ]);
    expect(TaskStatus.devamEdiyor.api, 'devam_ediyor');
    expect(PaymentMethod.fromApi('Kredi Kartı'), PaymentMethod.krediKarti);
    expect(ExpenseScope.genel.label, 'İşletme');
    expect(SendStatus.fromApi('kismen'), SendStatus.kismen);
  });

  test('randevu serbest metin normalleştirme', () {
    expect(AppointmentValues.isCancelled('iptal edildi'), isTrue);
    expect(AppointmentValues.isCancelled('İptal'), isTrue);
    expect(AppointmentValues.isDone('tamamlandi'), isTrue);
    expect(AppointmentValues.isDone('tamamlandı'), isTrue);
    expect(AppointmentValues.statusLabel('beklemede'), 'Beklemede');
    expect(AppointmentValues.statusLabel('planlandi'), 'Planlandı');
    expect(AppointmentValues.statusLabel('garip durum'), 'Garip durum');
    expect(AppointmentValues.typeLabel('baslama'), 'Başlama');
    expect(AppointmentValues.typeLabel('Özel tür'), 'Özel tür');
  });
}
