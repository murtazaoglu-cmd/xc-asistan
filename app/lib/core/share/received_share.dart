import 'package:flutter/foundation.dart';

@immutable
class SharedFileRef {
  const SharedFileRef({required this.path, required this.name, this.mimeType});
  final String path;
  final String name;
  final String? mimeType;

  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  bool get isText =>
      extension == 'txt' || (mimeType?.startsWith('text/') ?? false);
  bool get isZip => extension == 'zip' || (mimeType?.contains('zip') ?? false);
  bool get isImage =>
      mimeType?.startsWith('image/') ??
      const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension);
}

/// "Paylaş" menüsünden uygulamaya düşen içerik (Türkçe adıyla "alınan paylaşım").
/// Metin ve/veya dosyalar taşır; işleme (ör. WhatsApp sohbet dışa aktarımı → müşteri notu)
/// assistant özelliğinin işidir.
@immutable
class ReceivedShare {
  const ReceivedShare({
    this.text,
    this.files = const [],
    required this.receivedAt,
  });

  final String? text;
  final List<SharedFileRef> files;
  final DateTime receivedAt;

  bool get isEmpty => (text == null || text!.trim().isEmpty) && files.isEmpty;

  /// WhatsApp sohbet dışa aktarımı: "WhatsApp Chat with …" .txt ya da .zip.
  bool get looksLikeWhatsAppExport => files.any(
    (f) => (f.isText || f.isZip) && f.name.toLowerCase().contains('whatsapp'),
  );
}
