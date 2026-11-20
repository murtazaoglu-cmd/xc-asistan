// GET /health (herkese açık) bağlantı denemesi + "zorunlu güncelleme" kancası.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../util/json.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'api_providers.dart';

@immutable
class HealthResult {
  const HealthResult({
    required this.ok,
    this.serverTime,
    this.latency,
    this.minAppVersion,
    this.error,
  });
  final bool ok;
  final DateTime? serverTime;
  final Duration? latency;

  /// Sunucu (ileride) `/health` içinde `minAppVersion` bildirirse.
  final String? minAppVersion;
  final String? error;
}

class HealthService {
  HealthService(this._api);
  final ApiClient _api;

  Future<HealthResult> check() async {
    final sw = Stopwatch()..start();
    try {
      final j = await _api.getMap('/health');
      sw.stop();
      return HealthResult(
        ok: j.str('status') == 'ok',
        serverTime: j.dateTime('time'),
        latency: sw.elapsed,
        minAppVersion: j.strOrNull('minAppVersion'),
      );
    } catch (e) {
      return HealthResult(ok: false, error: AppException.from(e).message);
    }
  }
}

final healthServiceProvider = Provider<HealthService>(
  (ref) => HealthService(ref.watch(apiClientProvider)),
);

/// Sürüm karşılaştırma: "1.2.3" biçimi; a < b ise negatif.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e.trim()) ?? 0)
      .toList();
  final x = parse(a), y = parse(b);
  for (var i = 0; i < 3; i++) {
    final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

@immutable
class UpdateRequirement {
  const UpdateRequirement({required this.isRequired, this.minVersion});
  final bool isRequired;
  final String? minVersion;
  static const none = UpdateRequirement(isRequired: false);
}

/// Zorunlu güncelleme kancası. PASİF: `FORCE_UPDATE_ENABLED=true` derleme bayrağı ve
/// sunucunun /health'te `minAppVersion` bildirmesi gerekir; ikisi yoksa hiçbir şey olmaz.
final updateRequirementProvider = FutureProvider<UpdateRequirement>((
  ref,
) async {
  final config = ref.watch(appConfigProvider);
  if (!config.forceUpdateEnabled || config.demo) return UpdateRequirement.none;
  final h = await ref.watch(healthServiceProvider).check();
  final min = h.minAppVersion;
  if (!h.ok || min == null) return UpdateRequirement.none;
  final current = (await PackageInfo.fromPlatform()).version;
  return UpdateRequirement(
    isRequired: compareVersions(current, min) < 0,
    minVersion: min,
  );
});

final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
