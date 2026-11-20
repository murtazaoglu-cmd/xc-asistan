// Bildirim dokunuşu / paylaşım gibi dış olaylardan gelen "şu rotaya git" isteği.
// Oturum açık değilse (ya da biyometrik kilitliyse) bekletilir, uygun olunca uygulanır.
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingLocationNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// [location] yalnızca uygulama içi yol olmalı ("/jobs/offers/123").
  void open(String location) {
    if (location.startsWith('/')) state = location;
  }

  void clear() => state = null;
}

final pendingLocationProvider =
    NotifierProvider<PendingLocationNotifier, String?>(
      PendingLocationNotifier.new,
    );
