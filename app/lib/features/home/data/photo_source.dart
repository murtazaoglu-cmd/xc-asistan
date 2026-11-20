// SAHİBİ: home ajanı. Kamera/galeri erişimi tek yerde (testte sahte ile değişir).
// `image_picker`: Android 13+ ve iOS izinleri manifest/Info.plist'te tanımlıdır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoOrigin { camera, gallery }

class PickedPhoto {
  const PickedPhoto(this.path, this.name);
  final String path;
  final String name;
}

abstract class PhotoSource {
  /// Kullanıcı vazgeçerse null. İzin/kamera hatası exception fırlatır.
  Future<PickedPhoto?> pick(PhotoOrigin origin);
}

class ImagePickerPhotoSource implements PhotoSource {
  ImagePickerPhotoSource([ImagePicker? picker])
    : _picker = picker ?? ImagePicker();
  final ImagePicker _picker;

  @override
  Future<PickedPhoto?> pick(PhotoOrigin origin) async {
    // 15 MB sınırı için görüntü küçültülür (sözleşme §12).
    final f = await _picker.pickImage(
      source: origin == PhotoOrigin.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    return f == null ? null : PickedPhoto(f.path, f.name);
  }
}

final photoSourceProvider = Provider<PhotoSource>(
  (ref) => ImagePickerPhotoSource(),
);
