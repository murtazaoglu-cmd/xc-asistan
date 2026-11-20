// Yazışma dosyası seçici (.txt / .zip). Testte sahte ile değiştirilir.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/biometric.dart';
import '../../../core/files/picked_files.dart';
import 'import_flow.dart';

abstract class ImportFilePicker {
  Future<ImportSource?> pick({String? customerKey});
}

class DeviceImportFilePicker implements ImportFilePicker {
  DeviceImportFilePicker(this._runUnlocked);
  final Future<T> Function<T>(Future<T> Function()) _runUnlocked;

  @override
  Future<ImportSource?> pick({String? customerKey}) => _runUnlocked(() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'zip'],
    );
    if (f == null) return null;
    final p = kIsWeb
        ? PickedFileStore.put(await f.xFile.readAsBytes())
        : f.path;
    if (p == null) return null;
    return ImportSource(
      filePath: p,
      fileName: f.name,
      customerKey: customerKey,
    );
  });
}

final importFilePickerProvider = Provider<ImportFilePicker>(
  (ref) => DeviceImportFilePicker(
    <T>(action) => ref.read(appLockProvider.notifier).runUnlocked<T>(action),
  ),
);

/// Paylaşılan içerikten içe aktarma kaynağı üretir. Desteklenmeyen içerikte null.
/// Öncelik: .txt/.zip dosya (WhatsApp dışa aktarımı); yoksa metin.
ImportSource? importSourceFromShare({
  String? text,
  List<({String path, String name, bool isTextOrZip})> files = const [],
  String? customerKey,
}) {
  for (final f in files) {
    if (f.isTextOrZip) {
      return ImportSource(
        filePath: f.path,
        fileName: f.name,
        customerKey: customerKey,
      );
    }
  }
  if (text != null && text.trim().isNotEmpty) {
    return ImportSource(text: text.trim(), customerKey: customerKey);
  }
  return null;
}
