import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';

void main() {
  test('varsayılan profil sektör nötr', () {
    const p = BrandProfile.generic;
    expect(p.id, 'genel');
    expect(p.appName, 'XC Asistan');
    final all = [
      p.companyName,
      p.tagline,
      p.terms.offer,
      p.terms.survey,
      ...p.terms.serviceTypes,
    ].join(' ').toLowerCase();
    for (final bad in ['pergola', 'metal', 'demir', 'doğrama', 'cam balkon']) {
      expect(all.contains(bad), isFalse, reason: bad);
    }
  });

  test('sözlük: api değeri → etiket, bilinmeyen olduğu gibi', () {
    const g = BrandProfile.generic;
    expect(g.terms.appointmentTypeLabel('Keşif'), 'Ön görüşme');
    expect(g.terms.appointmentTypeLabel('kesif'), 'Ön görüşme'); // eski kayıt
    expect(g.terms.appointmentTypeLabel('baslama'), 'Başlama');
    expect(g.terms.appointmentTypeLabel('Özel'), 'Özel');
    expect(g.terms.appointmentTypeLabel(null), 'Randevu');
    expect(BrandProfile.xControl.terms.appointmentTypeLabel('Keşif'), 'Keşif');
    // Sunucuya giden değerler sözleşmedeki gibi kalır
    expect(g.terms.appointmentTypeOptions.map((e) => e.api), [
      'Keşif',
      'Montaj',
      'Teslim',
      'Bakım',
      'Diğer',
    ]);
  });

  test(
    'fromJson eksik alanları varsayılandan tamamlar (GET /config hazırlığı)',
    () {
      final p = BrandProfile.fromJson({
        'appName': 'Usta Asistan',
        'primaryColor': '#FF5500',
        'terms': {
          'offer': 'Fiyat Teklifi',
          'appointmentTypeLabels': {'Keşif': 'Ölçü'},
        },
      });
      expect(p.appName, 'Usta Asistan');
      expect(p.companyName, 'İşletmem');
      expect(p.primaryColor!.toARGB32(), 0xFFFF5500);
      expect(p.terms.offer, 'Fiyat Teklifi');
      expect(p.terms.appointmentTypeLabel('Keşif'), 'Ölçü');
      expect(
        BrandProfile.fromJson({'primaryColor': 'bozuk'}).primaryColor,
        isNull,
      );
    },
  );
}
