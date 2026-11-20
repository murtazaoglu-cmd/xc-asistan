// Dış bağlantılar (arama, WhatsApp, harita) tek yerden; testte sahte ile değiştirilir.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class LinkLauncher {
  /// Bağlantıyı dış uygulamada açar; açılamazsa false.
  Future<bool> open(Uri uri);
  Future<bool> canOpen(Uri uri);
  Future<void> copy(String text);
}

class UrlLauncherLinkLauncher implements LinkLauncher {
  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> canOpen(Uri uri) async {
    try {
      return await canLaunchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => UrlLauncherLinkLauncher(),
);
