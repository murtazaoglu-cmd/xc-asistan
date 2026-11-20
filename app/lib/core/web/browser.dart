// Tarayıcıya özgü işler (dosya indirme, tablo yazdırma, kopyalama) için tek kapı.
// Web dışında güvenli boş uygulama (stub) kullanılır: `dart.library.js_interop` koşullu içe aktarma.
export 'browser_stub.dart' if (dart.library.js_interop) 'browser_web.dart';
