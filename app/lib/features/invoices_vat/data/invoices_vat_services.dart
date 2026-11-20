// Cihaz hizmetleri (soyutlama: testte sahte ile değiştirilir).
//  - AttachmentPicker: kamera / galeri / dosya (image_picker + file_picker)
//  - ExportSharer: dışa aktarılan dosyayı kaydet + sistem paylaş menüsü
//  - TaxDoneStore: vergi takvimi "tamamlandı" işareti (sunucuda alan YOK; cihazda tutulur)
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/files/picked_files.dart';
import '../../../core/storage/storage_providers.dart';
import 'invoices_vat_models.dart';

// ---------------------------------------------------------------- Ek dosya seçici

@immutable
class PickedAttachment {
  const PickedAttachment({required this.path, required this.name});
  final String path;
  final String name;
}

/// Sunucunun kabul ettiği uzantılar (sözleşme B: pdf/png/jpg/jpeg/webp/gif/heic/heif, ≤15 MB).
const List<String> attachmentExtensions = [
  'pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'heif', //
];
const int attachmentMaxBytes = 15 * 1024 * 1024;
const int attachmentMaxCount = 10;

abstract class AttachmentPicker {
  Future<PickedAttachment?> takePhoto();
  Future<PickedAttachment?> pickPhoto();
  Future<PickedAttachment?> pickFile();
}

class DeviceAttachmentPicker implements AttachmentPicker {
  final ImagePicker _images = ImagePicker();

  Future<PickedAttachment?> _image(ImageSource s) async {
    final x = await _images.pickImage(
      source: s,
      imageQuality: 85,
      maxWidth: 2400,
      maxHeight: 2400,
    );
    if (x == null) return null;
    // Web: yol yok; baytlar bellekte tutulur (PickedFileStore), yükleme bunu çözer.
    final path = kIsWeb ? PickedFileStore.put(await x.readAsBytes()) : x.path;
    return PickedAttachment(path: path, name: x.name);
  }

  @override
  Future<PickedAttachment?> takePhoto() => _image(ImageSource.camera);

  @override
  Future<PickedAttachment?> pickPhoto() => _image(ImageSource.gallery);

  @override
  Future<PickedAttachment?> pickFile() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: attachmentExtensions,
    );
    final p = f == null
        ? null
        : (kIsWeb ? PickedFileStore.put(await f.xFile.readAsBytes()) : f.path);
    return (f == null || p == null)
        ? null
        : PickedAttachment(path: p, name: f.name);
  }
}

final attachmentPickerProvider = Provider<AttachmentPicker>(
  (ref) => DeviceAttachmentPicker(),
);

/// Dosya boyutu (bayt); okunamazsa (web, izin) null: sunucu 413 ile yine de reddeder.
Future<int?> attachmentSizeOf(String path) async {
  if (kIsWeb) return PickedFileStore.sizeOf(path);
  try {
    return await File(path).length();
  } catch (_) {
    return null;
  }
}

/// Dosya adı uzantısı izinli mi (yüklemeden önce istemci denetimi; sunucu ayrıca içerik imzasına bakar).
bool isAllowedAttachmentName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return attachmentExtensions.contains(name.substring(dot + 1).toLowerCase());
}

// ---------------------------------------------------------------- Dışa aktarma teslimi

@immutable
class ExportDelivery {
  const ExportDelivery({required this.path, this.shared = false});

  /// Kaydedilen dosyanın yolu.
  final String path;

  /// Sistem paylaş menüsü açıldı mı.
  final bool shared;
}

abstract class ExportSharer {
  /// Dosyayı kaydeder ve (destekleniyorsa) sistem paylaş menüsünü açar.
  Future<ExportDelivery> deliver(ExportFile file);
}

/// Varsayılan: dosyayı uygulama geçici/önbellek klasörüne yazar. Paylaş menüsü için
/// `share_plus` gerekir (docs/CORE-REQUESTS.md): paket eklenince bu sağlayıcı override edilir.
class LocalExportSharer implements ExportSharer {
  @override
  Future<ExportDelivery> deliver(ExportFile file) async {
    if (kIsWeb) {
      throw UnsupportedError('Dosya kaydetme bu platformda desteklenmiyor.');
    }
    final dir = await Directory.systemTemp.createTemp('xc_export_');
    final safe = safeFilename(file.filename);
    final f = File('${dir.path}${Platform.pathSeparator}$safe');
    await f.writeAsBytes(file.bytes, flush: true);
    return ExportDelivery(path: f.path);
  }
}

final exportSharerProvider = Provider<ExportSharer>(
  (ref) => LocalExportSharer(),
);

/// Yol kaçışı / denetim karakteri / aşırı uzunluk temizliği.
String safeFilename(String name) {
  var n = name.split(RegExp(r'[\\/]')).last;
  n = n.replaceAll(RegExp(r'[\x00-\x1f<>:"|?*]'), '_').trim();
  if (n.isEmpty || n == '.' || n == '..') n = 'dosya';
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 8 ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n;
}

// ---------------------------------------------------------------- Vergi takvimi "tamamlandı"

/// Sunucu sözleşmesinde tamamlama alanı yok: işaret bu cihazda saklanır (öğe anahtarı + son gün).
class TaxDoneNotifier extends Notifier<Set<String>> {
  static const _prefKey = 'invoices_vat.tax_done';

  @override
  Set<String> build() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      return (prefs.getStringList(_prefKey) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  bool isDone(TaxItem item) => state.contains(item.doneKey);

  Future<void> setDone(TaxItem item, bool done) async {
    final next = {...state};
    done ? next.add(item.doneKey) : next.remove(item.doneKey);
    state = next;
    try {
      await ref
          .read(sharedPreferencesProvider)
          .setStringList(_prefKey, next.toList());
    } catch (_) {}
  }
}

final taxDoneProvider = NotifierProvider<TaxDoneNotifier, Set<String>>(
  TaxDoneNotifier.new,
);
