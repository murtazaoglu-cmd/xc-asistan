// KDV özet metni (paylaşım için). Tahmini; beyan sorumluluğu mali müşavirdedir.
import '../../../core/util/formatters.dart';
import 'invoices_vat_models.dart';

abstract final class VatSummaryText {
  /// WhatsApp/e-posta ile mali müşavire gönderilecek kısa özet.
  static String build(
    VatPeriod p, {
    required String companyName,
    String? label,
  }) {
    final b = StringBuffer()
      ..writeln('$companyName KDV özeti (tahmini)')
      ..writeln('Dönem: ${label ?? p.key}')
      ..writeln('Hesaplanan KDV: ${p.hesaplanan.format()}')
      ..writeln('İndirilecek KDV: ${p.indirilecek.format()}');
    if (!p.indirilemeyen.isZero) {
      b.writeln('İndirilemeyen KDV: ${p.indirilemeyen.format()}');
    }
    if (!p.oncekiDevreden.isZero) {
      b.writeln('Önceki dönemden devreden: ${p.oncekiDevreden.format()}');
    }
    if (!p.kdv2.isZero) b.writeln('KDV-2 (tevkifat): ${p.kdv2.format()}');
    b.writeln('Ödenecek KDV: ${p.odenecek.format()}');
    if (!p.devreden.isZero)
      b.writeln('Sonraki döneme devreden: ${p.devreden.format()}');
    if (p.dueDate != null) b.writeln('Son tarih: ${Fmt.date(p.dueDate!)}');
    b.writeln('Belge sayısı: ${p.documentCount}');
    b
      ..writeln()
      ..write(
        'Tutarlar uygulama tarafından tahmini hesaplanmıştır; kontrol ve beyan için teyit rica ederim.',
      );
    if (p.confirmation.needed) {
      b.write(' (Doğrulanmamış oran/tarih/tevkifat içeren belgeler olabilir.)');
    }
    return b.toString();
  }
}
