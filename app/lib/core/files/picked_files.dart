// Web'de dosya SEÇİCİLER yol vermez (bayt verir). Yükleme kodu `filePath` bekler; bu yüzden
// baytlar bellekte tutulur ve sahte bir yol (`xcmem://<id>`) döner. `ApiClient.upload` bu yolu
// çözer. Mobilde dosya yolu gerçektir; bu sınıf devreye girmez.
import 'dart:typed_data';

import '../web/browser.dart';

abstract final class PickedFileStore {
  static const scheme = 'xcmem://';
  static final Map<String, Uint8List> _files = {};
  static int _n = 0;

  /// Baytları saklar, sahte yol döner.
  static String put(Uint8List bytes) {
    final key = '${DateTime.now().microsecondsSinceEpoch}-${_n++}';
    _files[key] = bytes;
    // Bellek sızıntısını sınırla: en çok 20 dosya tutulur.
    while (_files.length > 20) {
      _files.remove(_files.keys.first);
    }
    return '$scheme$key';
  }

  static bool isMemory(String path) => path.startsWith(scheme);

  /// Yola karşılık gelen baytlar. `blob:` adresleri (web image_picker) tarayıcıdan okunur.
  static Future<Uint8List?> read(String path) async {
    if (isMemory(path)) return _files[path.substring(scheme.length)];
    if (path.startsWith('blob:')) return browserReadBlob(path);
    return null;
  }

  static int? sizeOf(String path) =>
      isMemory(path) ? _files[path.substring(scheme.length)]?.length : null;

  static void forget(String path) {
    if (isMemory(path)) _files.remove(path.substring(scheme.length));
  }
}
