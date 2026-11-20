import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bağlantı durumu kaynağı (testte override edilir). true = çevrimiçi (ağ arayüzü var).
/// Not: "ağ var" ≠ "sunucuya erişilir"; gerçek hatalar AppException(network) ile gelir.
final connectivityStreamProvider = Provider<Stream<bool>>((ref) {
  final c = Connectivity();
  late final StreamController<bool> ctrl;
  StreamSubscription<List<ConnectivityResult>>? sub;
  bool online(List<ConnectivityResult> r) =>
      r.any((e) => e != ConnectivityResult.none);
  ctrl = StreamController<bool>.broadcast(
    onListen: () async {
      try {
        ctrl.add(online(await c.checkConnectivity()));
      } catch (_) {}
      sub = c.onConnectivityChanged.listen(
        (r) => ctrl.add(online(r)),
        onError: (_) {},
      );
    },
    onCancel: () => sub?.cancel(),
  );
  ref.onDispose(ctrl.close);
  return ctrl.stream;
});

/// Çevrimiçi mi (ilk değer gelene kadar true: yanlış "çevrimdışı" şeridi göstermemek için).
final isOnlineProvider = StreamProvider<bool>(
  (ref) => ref.watch(connectivityStreamProvider),
);

bool isOnlineValue(AsyncValue<bool> v) => v.value ?? true;
