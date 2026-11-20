// SAHİBİ: jobs ajanı. Toplu işlem yürütücüsü (teklif durum/silme). Saf Dart: arayüzden bağımsız, test edilebilir.
//
// Sunucunun toplu uçları (PATCH /offers/bulk-status, DELETE /offers/bulk) yalnız SAYI döner ve erişimi
// olmayan kayıtları sessizce atlar. Bu yüzden: parça başına (<= [bulkChunkSize]) toplu çağrı yapılır;
// sayı eksikse hangi kayıtların işlenmediği tek tek doğrulanır; toplu çağrı hata verirse (ağ dışı)
// kayıtlar tek tek uygulanır. Tek tek istekler eşzamanlılık <= [bulkConcurrency].
import '../../../core/api/api_exception.dart';

const int bulkChunkSize = 50;
const int bulkConcurrency = 3;

class BulkTarget {
  const BulkTarget(this.id, this.label);
  final String id;

  /// Sonuç özetinde gösterilen ad ("OFR-1001 · Ayşe Yılmaz").
  final String label;
}

class BulkFailure {
  const BulkFailure(this.target, this.reason);
  final BulkTarget target;
  final String reason;
}

class BulkOutcome {
  const BulkOutcome({
    required this.total,
    required this.succeeded,
    required this.failures,
  });
  final int total;
  final List<BulkTarget> succeeded;
  final List<BulkFailure> failures;

  int get ok => succeeded.length;
  bool get allOk => failures.isEmpty;
  List<String> get succeededIds => [for (final t in succeeded) t.id];

  /// "5 işlem: 4 başarılı, 1 hatalı".
  String get summary =>
      '$total işlem: $ok başarılı${failures.isEmpty ? '' : ', ${failures.length} hatalı'}';
}

/// En çok [limit] eşzamanlı çalışan basit havuz; sıra korunmaz, her öğe tam bir kez işlenir.
Future<void> runPool<T>(
  List<T> items,
  int limit,
  Future<void> Function(T item) task,
) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final item = items[next++];
      await task(item);
    }
  }

  final n = items.length < limit ? items.length : limit;
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
}

Future<BulkOutcome> runBulk({
  required List<BulkTarget> targets,
  required Future<int> Function(List<String> ids) bulkCall,
  required Future<void> Function(String id) single,

  /// Toplu çağrı sayıyı eksik döndürünce: kayıt işlendi mi? (hata fırlatırsa doğrulanamadı)
  required Future<bool> Function(String id) isDone,

  /// Sunucu sessizce atladığında gösterilecek neden.
  required String skippedReason,
  void Function(int done, int total)? onProgress,
}) async {
  final okList = <BulkTarget>[];
  final failures = <BulkFailure>[];
  var done = 0;
  void tick(int by) {
    done += by;
    onProgress?.call(done, targets.length);
  }

  onProgress?.call(0, targets.length);
  for (var i = 0; i < targets.length; i += bulkChunkSize) {
    final chunk = targets.sublist(
      i,
      i + bulkChunkSize > targets.length ? targets.length : i + bulkChunkSize,
    );
    int? count;
    Object? error;
    try {
      count = await bulkCall([for (final t in chunk) t.id]);
    } catch (e) {
      error = e;
    }
    if (error == null && count != null && count >= chunk.length) {
      okList.addAll(chunk);
    } else if (error != null) {
      final ex = AppException.from(error);
      if (ex.isNetwork || ex.isUnauthorized) {
        for (final t in chunk) {
          failures.add(BulkFailure(t, ex.message));
        }
      } else {
        await runPool<BulkTarget>(chunk, bulkConcurrency, (t) async {
          try {
            await single(t.id);
            okList.add(t);
          } catch (e) {
            failures.add(BulkFailure(t, AppException.from(e).message));
          }
        });
      }
    } else {
      await runPool<BulkTarget>(chunk, bulkConcurrency, (t) async {
        try {
          if (await isDone(t.id)) {
            okList.add(t);
          } else {
            failures.add(BulkFailure(t, skippedReason));
          }
        } catch (e) {
          failures.add(
            BulkFailure(
              t,
              'Sonucu doğrulanamadı: ${AppException.from(e).message}',
            ),
          );
        }
      });
    }
    tick(chunk.length);
  }
  // Başarı/başarısızlık sırası asıl liste sırasını korusun.
  final order = {for (var i = 0; i < targets.length; i++) targets[i].id: i};
  okList.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
  failures.sort((a, b) => order[a.target.id]!.compareTo(order[b.target.id]!));
  return BulkOutcome(
    total: targets.length,
    succeeded: okList,
    failures: failures,
  );
}
