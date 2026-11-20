// Telefon kuralları (sözleşme §0): serbest metin saklanır; eşleştirme için yalnız
// rakamlar (phone_key); WhatsApp/arama için 0532… → 90532… çevrilir.
abstract final class PhoneUtil {
  /// Yalnız rakamlar (sunucudaki `phone_key` ile aynı).
  static String digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

  static String phoneKey(String? s) => digits(s);

  /// Uluslararası biçim (artı işaretsiz): "905321112233". Çözülemezse null.
  /// Kabul: 0532…, 532…, +90 532…, 0090 532…, 90 532…
  static String? toInternational(String? phone, {String countryCode = '90'}) {
    var d = digits(phone);
    if (d.isEmpty) return null;
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith(countryCode) && d.length == countryCode.length + 10) {
      return d;
    }
    if (d.startsWith('0') && d.length == 11)
      return '$countryCode${d.substring(1)}';
    if (d.length == 10 && d.startsWith('5')) return '$countryCode$d';
    // Yurt dışı numara (ülke kodlu, 11-15 hane): olduğu gibi.
    if (d.length >= 11 && d.length <= 15 && !d.startsWith('0')) return d;
    return null;
  }

  /// `tel:` bağlantısı ("tel:+905321112233"). Çözülemezse ham rakamlarla.
  static Uri telUri(String phone) {
    final intl = toInternational(phone);
    return Uri.parse('tel:${intl != null ? '+$intl' : digits(phone)}');
  }

  /// WhatsApp uygulaması şeması: whatsapp://send?phone=…&text=…
  static Uri? whatsappAppUri(String phone, {String? text}) {
    final intl = toInternational(phone);
    if (intl == null) return null;
    return Uri(
      scheme: 'whatsapp',
      host: 'send',
      query: _query({
        'phone': intl,
        if (text != null && text.isNotEmpty) 'text': text,
      }),
    );
  }

  /// Web bağlantısı (yedek): https://wa.me/90532…?text=…
  static Uri? whatsappWebUri(String phone, {String? text}) {
    final intl = toInternational(phone);
    if (intl == null) return null;
    return Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$intl',
      query: (text != null && text.isNotEmpty) ? _query({'text': text}) : null,
    );
  }

  // Boşluk "+" değil "%20" olmalı (WhatsApp metni birebir gösterir).
  static String _query(Map<String, String> p) => p.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');

  /// Gösterim: "0532 111 22 33". Tanınmazsa girişi olduğu gibi döndürür.
  static String formatDisplay(String? phone) {
    final raw = phone ?? '';
    final intl = toInternational(raw);
    if (intl != null && intl.startsWith('90') && intl.length == 12) {
      final n = intl.substring(2);
      return '0${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6, 8)} ${n.substring(8)}';
    }
    return raw.trim();
  }
}
