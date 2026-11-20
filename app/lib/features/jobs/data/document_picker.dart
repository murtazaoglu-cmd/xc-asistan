// SAHİBİ: jobs ajanı. Kamera/galeri/dosya seçici: testte sahte ile değiştirilebilsin diye arayüz.
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/biometric.dart';

class PickedDocument {
  const PickedDocument({
    required this.path,
    required this.name,
    required this.size,
  });
  final String path;
  final String name;
  final int size;
}

abstract class DocumentPicker {
  /// Kamerayla fotoğraf çek. Vazgeçildiyse null.
  Future<PickedDocument?> takePhoto();

  /// Galeriden fotoğraf seç.
  Future<PickedDocument?> pickPhoto();

  /// Herhangi bir belge (PDF, Office, DWG...). Sunucu izin listesi ayrıca denetler.
  Future<PickedDocument?> pickFile();
}

const String _pickerFailed =
    'Kamera ya da dosyalara erişilemedi. Uygulama izinlerini kontrol edin.';

class PlatformDocumentPicker implements DocumentPicker {
  PlatformDocumentPicker(this._runUnlocked);

  /// Sistem ekranı açılırken biyometrik kilidin devreye girmesini engeller.
  final Future<PickedDocument?> Function(
    Future<PickedDocument?> Function() action,
  )
  _runUnlocked;

  final ImagePicker _images = ImagePicker();

  Future<PickedDocument?> _image(ImageSource source) => _runUnlocked(() async {
    try {
      final f = await _images.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2560,
      );
      if (f == null) return null;
      return PickedDocument(path: f.path, name: f.name, size: await f.length());
    } catch (_) {
      throw const AppException(AppErrorCode.unknown, _pickerFailed);
    }
  });

  @override
  Future<PickedDocument?> takePhoto() => _image(ImageSource.camera);

  @override
  Future<PickedDocument?> pickPhoto() => _image(ImageSource.gallery);

  @override
  Future<PickedDocument?> pickFile() => _runUnlocked(() async {
    try {
      final f = await FilePicker.pickFile();
      if (f == null || f.path == null) return null;
      return PickedDocument(
        path: f.path!,
        name: f.name,
        size: await f.xFile.length(),
      );
    } catch (_) {
      throw const AppException(AppErrorCode.unknown, _pickerFailed);
    }
  });
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => PlatformDocumentPicker(
    (action) => ref.read(appLockProvider.notifier).runUnlocked(action),
  ),
);
