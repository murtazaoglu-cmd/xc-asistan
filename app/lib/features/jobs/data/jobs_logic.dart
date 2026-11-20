// SAHİBİ: jobs ajanı. Arayüzden bağımsız, test edilebilir küçük kurallar.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/domain_enums.dart';
import 'jobs_models.dart';

/// Teklif bekleme yaşı etiketi: "Bugün geldi", "3 gündür bekliyor", "5 gün yanıt bekliyor".
/// Kapalı (Kabul/Red) tekliflerde null.
String? waitingLabel(Offer o, [DateTime? now]) {
  final d = o.waitingDays(now);
  if (d == null) return null;
  if (o.statusEnum == OfferStatus.teklifVerildi) {
    return d == 0 ? 'Bugün gönderildi' : '$d gün yanıt bekliyor';
  }
  return d == 0 ? 'Bugün geldi' : '$d gündür bekliyor';
}

/// Dikkat: Yeni/İncelendi/Keşif'te 3+ gün, Teklif Verildi'de 7+ gün.
bool isWaitingStale(Offer o, [DateTime? now]) {
  final d = o.waitingDays(now);
  if (d == null) return false;
  return d >= (o.statusEnum == OfferStatus.teklifVerildi ? 7 : 3);
}

/// Müşteri takip sayfası bağlantısı tabanı (`--dart-define=TRACK_BASE_URL=https://.../teklif-takip`).
/// Boşsa metne bağlantı yerine takip kodu konur (sunucunun `whatsappUrl`'si varsa o tercih edilir).
final trackingBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('TRACK_BASE_URL'),
);

String? trackingLink(String base, Offer o) {
  final b = base.trim();
  final code = o.trackingCode;
  if (b.isEmpty || code == null || code.isEmpty) return null;
  return '${b.endsWith('/') ? b.substring(0, b.length - 1) : b}/$code';
}

/// "WhatsApp'ta Aç" için hazır metin: marka adı, teklif kodu, toplam ve takip bağlantısı/kodu.
String quoteWhatsAppText({
  required String companyName,
  required String offerTerm,
  required Offer offer,
  String trackingBase = '',
}) {
  final total = offer.amount;
  final buf = StringBuffer(
    'Merhaba ${offer.name.trim()}, $companyName olarak hazırladığımız '
    '${offerTerm.toLowerCase()} (${offer.code})',
  );
  if (total != null && total.isPositive) {
    buf.write(' toplam ${total.format(hideZeroKurus: true)}');
  }
  buf.write('.');
  final link = trackingLink(trackingBase, offer);
  if (link != null) {
    buf.write(' Ayrıntılar: $link');
  } else if (offer.trackingCode != null) {
    buf.write(' Takip kodunuz: ${offer.trackingCode}');
  }
  return buf.toString();
}

/// Türkçe yönelme (-e/-a) eki: "Proje" → "Projeye", "İş" → "İşe", "Çalışma" → "Çalışmaya".
/// Sektör sözlüğünden gelen sözcüklerle ("Projeye Çevir") sabit ek yazmadan cümle kurmak için.
String dative(String word) {
  final w = word.trim();
  if (w.isEmpty) return w;
  const back = 'aıouAIOU';
  const vowels = 'aıoueiöüAIOUEİÖÜ';
  var lastVowel = '';
  for (var i = w.length - 1; i >= 0; i--) {
    if (vowels.contains(w[i])) {
      lastVowel = w[i];
      break;
    }
  }
  final suffix = back.contains(lastVowel) && lastVowel.isNotEmpty ? 'a' : 'e';
  final endsWithVowel = vowels.contains(w[w.length - 1]);
  return '$w${endsWithVowel ? 'y' : ''}$suffix';
}
