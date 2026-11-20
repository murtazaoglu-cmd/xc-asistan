// Arama / WhatsApp / yol tarifi bağlantılarını kuran ve açan saf mantık (testlenebilir).
import 'package:flutter/foundation.dart' show kIsWeb;

import '../util/phone.dart';
import 'ui_providers.dart';

class ContactLauncher {
  ContactLauncher(this._launcher);
  final LinkLauncher _launcher;

  /// Telefon uygulamasında arama ekranı.
  Future<bool> call(String phone) => _launcher.open(PhoneUtil.telUri(phone));

  /// WhatsApp: önce uygulama şeması (whatsapp://send?phone=90532…&text=…), olmazsa wa.me.
  /// Numara tanınmazsa false.
  Future<bool> whatsapp(String phone, {String? text}) async {
    final app = PhoneUtil.whatsappAppUri(phone, text: text);
    final web = PhoneUtil.whatsappWebUri(phone, text: text);
    if (app == null || web == null) return false;
    // Web'de `whatsapp://` şeması boş sekme açar; doğrudan wa.me kullanılır.
    if (!kIsWeb && await _launcher.open(app)) return true;
    return _launcher.open(web);
  }

  /// Haritada yol tarifi. Koordinat varsa onu, yoksa adresi hedef alır.
  static Uri? directionsUri({String? address, double? lat, double? lng}) {
    String? dest;
    if (lat != null && lng != null) {
      dest = '$lat,$lng';
    } else if (address != null && address.trim().isNotEmpty) {
      dest = address.trim();
    }
    if (dest == null) return null;
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': dest,
    });
  }

  Future<bool> directions({String? address, double? lat, double? lng}) async {
    final u = directionsUri(address: address, lat: lat, lng: lng);
    return u == null ? false : _launcher.open(u);
  }

  Future<void> copy(String text) => _launcher.copy(text);
}
