// SAHİBİ: home ajanı. Başka feature bu dosyaya yazmaz.
// Uçlar (sözleşme /mnt/user-data/outputs/mobile-api-contract.md):
//   GET /mobile/home (§2) · PATCH/POST /reminders (§8) · POST /documents/:offer|project/:id (§12, saha fotoğrafı)
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/dates.dart';
import 'home_models.dart';

abstract class HomeRepository {
  Future<HomeSummary> fetch();

  /// PATCH /reminders/:id `{status}` (`bekliyor` | `tamamlandi`). Yalnız kendi oluşturduğu
  /// hatırlatıcı (admin/muhasebe hepsi); aksi 403.
  Future<void> setReminderStatus(String id, String status);

  /// POST /reminders (ertele = yeni hatırlatıcı + eskiyi tamamla; PATCH `remind_at` yok).
  Future<void> createReminder({
    required String title,
    required DateTime remindAt,
    String? projectId,
    String? note,
  });

  /// POST /documents/:resourceType/:resourceId (multipart, alan `file`, ≤15 MB).
  /// [resourceType] `offer` | `project`.
  Future<void> uploadDocument({
    required String resourceType,
    required String resourceId,
    required String filePath,
    String? fileName,
    void Function(int sent, int total)? onProgress,
  });
}

class HttpHomeRepository implements HomeRepository {
  HttpHomeRepository(this.api);
  final ApiClient api;

  @override
  Future<HomeSummary> fetch() async =>
      HomeSummary.fromJson(await api.getMap('/mobile/home'));

  @override
  Future<void> setReminderStatus(String id, String status) async {
    await api.patch('/reminders/$id', data: {'status': status});
  }

  @override
  Future<void> createReminder({
    required String title,
    required DateTime remindAt,
    String? projectId,
    String? note,
  }) async {
    await api.post(
      '/reminders',
      data: {
        'title': title,
        'remind_at': Ist.toApiIso(remindAt),
        if (projectId != null) 'project_id': projectId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  @override
  Future<void> uploadDocument({
    required String resourceType,
    required String resourceId,
    required String filePath,
    String? fileName,
    void Function(int sent, int total)? onProgress,
  }) async {
    await api.upload(
      '/documents/$resourceType/$resourceId',
      field: 'file',
      filePath: filePath,
      fileName: fileName,
      onProgress: onProgress,
    );
  }
}

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HttpHomeRepository(ref.watch(apiClientProvider)),
);

/// Salt okunur yardımcı (başka ajanların brifing gibi kullanımları için): tek seferlik özet.
/// Bugün ekranı bunun yerine `homeControllerProvider` kullanır (sessiz yenileme + hata koruması).
final homeSummaryProvider = FutureProvider.autoDispose<HomeSummary>(
  (ref) => ref.watch(homeRepositoryProvider).fetch(),
  retry: (retryCount, error) => null,
);
