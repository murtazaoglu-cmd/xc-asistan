// Android/iOS "Paylaş" menüsünden metin/dosya alma (receive_sharing_intent).
// Gelen içerik [receivedShareProvider]'a düşer ve rota '/assistant/share' açılır
// (oturum yoksa giriş sonrası). İşleyen ekran: features/assistant.
//
// Android: AndroidManifest.xml intent filter'ları hazır. iOS: Share Extension hedefi
// Xcode'da elle eklenmelidir (docs/IOS-BUILD.md "Paylaşım uzantısı").
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../util/dates.dart';
import 'received_share.dart';

/// Eklentiye ince arayüz (testte sahte ile değiştirilir).
abstract class ShareSource {
  Future<List<SharedMediaFile>> initialMedia();
  Stream<List<SharedMediaFile>> mediaStream();
  Future<void> reset();
}

/// Web'de "Paylaş" menüsü yoktur: boş kaynak.
class NoopShareSource implements ShareSource {
  @override
  Future<List<SharedMediaFile>> initialMedia() async => const [];
  @override
  Stream<List<SharedMediaFile>> mediaStream() => const Stream.empty();
  @override
  Future<void> reset() async {}
}

class PluginShareSource implements ShareSource {
  ReceiveSharingIntent get _r => ReceiveSharingIntent.instance;
  @override
  Future<List<SharedMediaFile>> initialMedia() => _r.getInitialMedia();
  @override
  Stream<List<SharedMediaFile>> mediaStream() => _r.getMediaStream();
  @override
  Future<void> reset() async {
    await _r.reset();
  }
}

class ShareService {
  ShareService(this._source);
  final ShareSource _source;

  StreamSubscription<List<SharedMediaFile>>? _sub;
  final StreamController<ReceivedShare> _out =
      StreamController<ReceivedShare>.broadcast();

  Stream<ReceivedShare> get shares => _out.stream;

  /// Soğuk açılıştaki paylaşım + çalışırken gelenler. Birden çok çağrı güvenlidir.
  Future<void> start() async {
    if (_sub != null) return;
    _sub = _source.mediaStream().listen(_handle, onError: (_) {});
    try {
      final initial = await _source.initialMedia();
      _handle(initial, fromInitial: true);
    } catch (_) {}
  }

  void _handle(List<SharedMediaFile> media, {bool fromInitial = false}) {
    final share = toReceivedShare(media);
    if (share == null) return;
    _out.add(share);
    unawaited(
      _source.reset().catchError((_) {}),
    ); // aynı paylaşım tekrar gelmesin
  }

  /// Eklenti çıktısını uygulama modeline çevirir (boşsa null).
  static ReceivedShare? toReceivedShare(
    List<SharedMediaFile> media, {
    DateTime? now,
  }) {
    if (media.isEmpty) return null;
    final texts = <String>[];
    final files = <SharedFileRef>[];
    for (final m in media) {
      if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
        if (m.path.trim().isNotEmpty) texts.add(m.path.trim());
      } else {
        final name = m.path.split(RegExp(r'[\\/]')).last;
        files.add(
          SharedFileRef(path: m.path, name: name, mimeType: m.mimeType),
        );
      }
    }
    final s = ReceivedShare(
      text: texts.isEmpty ? null : texts.join('\n'),
      files: files,
      receivedAt: now ?? Ist.now(),
    );
    return s.isEmpty ? null : s;
  }

  void dispose() {
    _sub?.cancel();
    _out.close();
  }
}

final shareSourceProvider = Provider<ShareSource>(
  (ref) => kIsWeb ? NoopShareSource() : PluginShareSource(),
);

final shareServiceProvider = Provider<ShareService>((ref) {
  final s = ShareService(ref.watch(shareSourceProvider));
  ref.onDispose(s.dispose);
  return s;
});

/// Bekleyen (henüz işlenmemiş) paylaşım. assistant ekranı okur; işleyince [consume] çağırır.
class ReceivedShareNotifier extends Notifier<ReceivedShare?> {
  @override
  ReceivedShare? build() => null;
  void receive(ReceivedShare s) => state = s;
  void consume() => state = null;
}

final receivedShareProvider =
    NotifierProvider<ReceivedShareNotifier, ReceivedShare?>(
      ReceivedShareNotifier.new,
    );
