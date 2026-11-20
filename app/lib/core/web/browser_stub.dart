// Web dışı platformlar: tarayıcı işlemleri yok (false döner).
import 'dart:typed_data';

/// Tarayıcı indirmesi başlatır. Web dışında false.
Future<bool> browserDownload(
  Uint8List bytes,
  String filename,
  String mime,
) async => false;

/// Tabloyu yazdırma iletişim kutusuyla yazdırır. Web dışında false.
bool browserPrintTable(
  String title,
  List<String> headers,
  List<List<String>> rows,
) => false;

/// `blob:` adresindeki baytları okur (web'de image_picker çıktısı). Web dışında null.
Future<Uint8List?> browserReadBlob(String url) async => null;
