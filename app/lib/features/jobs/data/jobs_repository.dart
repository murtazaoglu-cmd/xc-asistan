// SAHİBİ: jobs ajanı. Başka feature bu dosyaya yazmaz.
// İşler veri erişimi. Uçlar (sözleşme /mnt/user-data/outputs/mobile-api-contract.md):
//   - GET/POST/PATCH/DELETE /offers, /offers/:id, /offers/:id/status
//   - POST /quotes/:offerId, POST /quotes/:offerId/send (200/207/502)
//   - GET/POST/PATCH /projects, /projects/:id/full, /stage, /amount, /dates, /tasks, /extras
//   - /documents/offer|project/:id, /shares, /activity, /quote-templates
//
// Kalıp: modeller bu klasörde elle yazılır (fromJson/toJson, null-güvenli);
// metotlar AppException fırlatır; para alanları Money, tarihler UTC DateTime'dır.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/api/api_providers.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import 'jobs_models.dart';
import 'jobs_project_models.dart';

/// "Projeye çevir" sonucu.
class OfferProjectResult {
  const OfferProjectResult({this.projectId, required this.created});

  /// Bulunamadıysa null (proje oluştu ama listeden eşleşmedi).
  final String? projectId;

  /// false: teklifin zaten projesi vardı (mevcut projeye gidilir).
  final bool created;
}

abstract class JobsRepository {
  // ---- Teklifler ----
  Future<Paged<Offer>> offers({
    String? q,
    OfferStatus? status,
    int limit = 30,
    int offset = 0,
  });
  Future<Offer> offer(String id);

  /// Herkese açık POST /offers (jetonlu: teklif oluşturana ait olur). Tam kayıt döner.
  Future<Offer> createOffer(OfferDraft draft);
  Future<Offer> updateOffer(String id, OfferDraft draft);
  Future<Offer> setOfferStatus(String id, OfferStatus status);
  Future<void> deleteOffer(String id);

  /// PATCH /offers/bulk-status `{ids, status}` → güncellenen sayı. Sunucu erişimi olmayan ve
  /// (admin dışı için) Kabul Edilmiş teklifleri SESSİZCE atlar; yalnız sayı döner.
  Future<int> bulkSetOfferStatus(List<String> ids, OfferStatus status);

  /// DELETE /offers/bulk `{ids}` → silinen sayı (admin hepsini, diğerleri yalnız kendi kayıtlarını).
  Future<int> bulkDeleteOffers(List<String> ids);

  // ---- Teklif hazırlama / gönderme ----
  Future<OfferQuote> saveQuote(String offerId, List<QuoteItem> items);

  /// 200 / 207 / 502 DÜRÜST sonuç olarak döner (502 istisna FIRLATMAZ). Diğer hatalar AppException.
  Future<QuoteSendResult> sendQuote(String offerId);
  Future<List<QuoteTemplate>> quoteTemplates();

  /// Teklife bağlı projeyi bulur (`projects.offer_id`); yoksa null.
  Future<String?> findProjectIdForOffer(Offer offer);

  /// "Projeye çevir": zaten varsa mevcut proje; yoksa Kabul Edildi ile otomatik oluşur.
  Future<OfferProjectResult> offerToProject(Offer offer);

  // ---- Projeler ----
  Future<Paged<Project>> projects({String? q, int limit = 30, int offset = 0});
  Future<Project> createProject(ProjectDraft draft);

  /// DELETE /projects/:id (yalnız admin, GERİ ALINAMAZ): görev/ödeme/gider kayıtları (CASCADE),
  /// galeri fotoğrafları ve randevular da silinir.
  Future<void> deleteProject(String id);

  /// [fieldMode] saha rolü: /full yasak (403); proje /dashboard-init'ten, görevler ayrı uçtan.
  Future<ProjectFull> projectFull(String id, {bool fieldMode = false});
  Future<void> setStage(String id, ProjectStage stage);
  Future<void> setAmount(String id, Money amount);
  Future<void> setDates(
    String id, {
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
  });
  Future<void> setProjectInfo(
    String id, {
    String? customerName,
    String? service,
    String? notes,
    String? address,
  });

  // ---- Görevler / ilave işler ----
  Future<List<PersonRef>> collaborators(String projectId);
  Future<ProjectTask> addTask(
    String projectId,
    String title, {
    String? assignedUserId,
  });
  Future<void> setTaskStatus(String taskId, TaskStatus status);
  Future<void> deleteTask(String taskId);
  Future<ProjectExtra> addExtra(
    String projectId,
    String description,
    Money amount,
  );
  Future<void> deleteExtra(String extraId);

  // ---- Belgeler / paylaşım / aktivite ----
  Future<List<DocumentItem>> documents(String type, String id);
  Future<DocumentItem> uploadDocument(
    String type,
    String id, {
    required String filePath,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  });
  Future<void> deleteDocument(String documentId);
  Future<List<ShareItem>> shares(String type, String id);
  Future<void> addShare(String type, String id, String userId);
  Future<void> removeShare(String shareId);
  Future<List<PersonRef>> shareCandidates();
  Future<List<ActivityItem>> activity(String type, String id);
}

class HttpJobsRepository implements JobsRepository {
  HttpJobsRepository(this.api);
  final ApiClient api;

  static String _q(String? q) {
    final t = (q ?? '').trim();
    return t.length > 100 ? t.substring(0, 100) : t;
  }

  // ---- Teklifler ----
  @override
  Future<Paged<Offer>> offers({
    String? q,
    OfferStatus? status,
    int limit = 30,
    int offset = 0,
  }) async {
    final page = await api.getPaged(
      '/offers',
      query: {
        'q': _q(q),
        'status': status?.api,
        'limit': limit,
        'offset': offset,
      },
    );
    return Paged(page.items.map(Offer.fromJson).toList(), page.total);
  }

  @override
  Future<Offer> offer(String id) async =>
      Offer.fromJson(await api.getMap('/offers/$id'));

  @override
  Future<Offer> createOffer(OfferDraft draft) async {
    final created = asJsonMap(
      await api.post('/offers', data: draft.toCreateJson()),
    );
    final id = created.strOr('id');
    if (id.isEmpty) {
      throw const AppException(
        AppErrorCode.unknown,
        AppException.unknownMessage,
      );
    }
    return offer(id);
  }

  @override
  Future<Offer> updateOffer(String id, OfferDraft draft) async =>
      Offer.fromJson(
        asJsonMap(await api.patch('/offers/$id', data: draft.toPatchJson())),
      );

  @override
  Future<Offer> setOfferStatus(String id, OfferStatus status) async =>
      Offer.fromJson(
        asJsonMap(
          await api.patch('/offers/$id/status', data: {'status': status.api}),
        ),
      );

  @override
  Future<void> deleteOffer(String id) async {
    await api.delete('/offers/$id');
  }

  @override
  Future<int> bulkSetOfferStatus(List<String> ids, OfferStatus status) async {
    final res = await api.patch(
      '/offers/bulk-status',
      data: {'ids': ids, 'status': status.api},
    );
    return asJsonMap(res).intOr('updated');
  }

  @override
  Future<int> bulkDeleteOffers(List<String> ids) async {
    final res = await api.delete('/offers/bulk', data: {'ids': ids});
    return asJsonMap(res).intOr('deleted');
  }

  @override
  Future<void> deleteProject(String id) async {
    await api.delete('/projects/$id');
  }

  // ---- Teklif hazırlama / gönderme ----
  @override
  Future<OfferQuote> saveQuote(String offerId, List<QuoteItem> items) async {
    final err = QuoteMath.validate(items);
    if (err != null) throw AppException(AppErrorCode.validation, err);
    final res = await api.post(
      '/quotes/$offerId',
      data: {'items': items.map((e) => e.toJson()).toList()},
    );
    return OfferQuote.fromJson(asJsonMap(res));
  }

  @override
  Future<QuoteSendResult> sendQuote(String offerId) async {
    final res = await api.send(
      'POST',
      '/quotes/$offerId/send',
      acceptStatuses: const {207, 502},
    );
    return QuoteSendResult.fromResponse(res.statusCode, res.map);
  }

  @override
  Future<List<QuoteTemplate>> quoteTemplates() async =>
      (await api.getList('/quote-templates'))
          .map(QuoteTemplate.fromJson)
          .toList();

  @override
  Future<String?> findProjectIdForOffer(Offer offer) async {
    final page = await api.getPaged(
      '/projects',
      query: {'q': _q(offer.name), 'limit': 200, 'offset': 0},
    );
    for (final p in page.items) {
      if (p.strOrNull('offer_id') == offer.id) return p.strOr('id');
    }
    return null;
  }

  @override
  Future<OfferProjectResult> offerToProject(Offer offer) async {
    if (offer.isAccepted) {
      final existing = await findProjectIdForOffer(offer);
      if (existing != null) {
        return OfferProjectResult(projectId: existing, created: false);
      }
    }
    // Sunucu `createProjectFromOffer` idempotenttir (çift proje oluşmaz).
    await api.patch(
      '/offers/${offer.id}/status',
      data: {'status': OfferStatus.kabulEdildi.api},
    );
    final id = await findProjectIdForOffer(offer);
    return OfferProjectResult(projectId: id, created: !offer.isAccepted);
  }

  // ---- Projeler ----
  @override
  Future<Paged<Project>> projects({
    String? q,
    int limit = 30,
    int offset = 0,
  }) async {
    final page = await api.getPaged(
      '/projects',
      query: {'q': _q(q), 'limit': limit, 'offset': offset},
    );
    return Paged(page.items.map(Project.fromJson).toList(), page.total);
  }

  @override
  Future<Project> createProject(ProjectDraft draft) async => Project.fromJson(
    asJsonMap(await api.post('/projects', data: draft.toJson())),
  );

  @override
  Future<ProjectFull> projectFull(String id, {bool fieldMode = false}) async {
    if (!fieldMode) {
      return ProjectFull.fromJson(await api.getMap('/projects/$id/full'));
    }
    final init = await api.getMap('/dashboard-init');
    final row = init
        .list('projects')
        .where((p) => p.strOr('id') == id)
        .firstOrNull;
    if (row == null) {
      throw const AppException(AppErrorCode.notFound, 'Proje bulunamadı.');
    }
    final tasks = await api.getList('/projects/$id/tasks');
    return ProjectFull(
      project: Project.fromJson(row),
      tasks: tasks.map(ProjectTask.fromJson).toList(),
      financeVisible: false,
    );
  }

  @override
  Future<void> setStage(String id, ProjectStage stage) async {
    await api.patch('/projects/$id/stage', data: {'stage': stage.api});
  }

  @override
  Future<void> setAmount(String id, Money amount) async {
    if (amount.isNegative) {
      throw const AppException(
        AppErrorCode.validation,
        'Tutar negatif olamaz.',
      );
    }
    await api.patch(
      '/projects/$id/amount',
      data: {'total_amount': amount.toJson()},
    );
  }

  @override
  Future<void> setDates(
    String id, {
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
  }) async {
    // Panel kuralı: tarihler İstanbul öğlen 12:00 ile gönderilir.
    await api.patch(
      '/projects/$id/dates',
      data: {
        if (start != null) 'start_date': Ist.noonIso(start),
        if (end != null) 'end_date': Ist.noonIso(end),
        if (end == null && clearEnd) 'end_date': null,
      },
    );
  }

  @override
  Future<void> setProjectInfo(
    String id, {
    String? customerName,
    String? service,
    String? notes,
    String? address,
  }) async {
    await api.patch(
      '/projects/$id',
      data: {
        'customer_name': ?customerName,
        'service': ?service,
        'notes': ?notes,
        'address': ?address,
      },
    );
  }

  // ---- Görevler / ilave işler ----
  @override
  Future<List<PersonRef>> collaborators(String projectId) async =>
      (await api.getList('/projects/$projectId/collaborators'))
          .map(PersonRef.fromJson)
          .toList();

  @override
  Future<ProjectTask> addTask(
    String projectId,
    String title, {
    String? assignedUserId,
  }) async {
    final err = ProjectValidators.taskTitle(title);
    if (err != null) throw AppException(AppErrorCode.validation, err);
    return ProjectTask.fromJson(
      asJsonMap(
        await api.post(
          '/projects/$projectId/tasks',
          data: {'title': title.trim(), 'assigned_user_id': ?assignedUserId},
        ),
      ),
    );
  }

  @override
  Future<void> setTaskStatus(String taskId, TaskStatus status) async {
    await api.patch('/projects/tasks/$taskId', data: {'status': status.api});
  }

  @override
  Future<void> deleteTask(String taskId) async {
    await api.delete('/projects/tasks/$taskId');
  }

  @override
  Future<ProjectExtra> addExtra(
    String projectId,
    String description,
    Money amount,
  ) async => ProjectExtra.fromJson(
    asJsonMap(
      await api.post(
        '/projects/$projectId/extras',
        data: {'description': description.trim(), 'amount': amount.toJson()},
      ),
    ),
  );

  @override
  Future<void> deleteExtra(String extraId) async {
    await api.delete('/projects/extras/$extraId');
  }

  // ---- Belgeler / paylaşım / aktivite ----
  @override
  Future<List<DocumentItem>> documents(String type, String id) async =>
      (await api.getList('/documents/$type/$id'))
          .map(DocumentItem.fromJson)
          .toList();

  @override
  Future<DocumentItem> uploadDocument(
    String type,
    String id, {
    required String filePath,
    required String fileName,
    void Function(int sent, int total)? onProgress,
  }) async => DocumentItem.fromJson(
    await api.upload(
      '/documents/$type/$id',
      field: 'file',
      filePath: filePath,
      fileName: fileName,
      onProgress: onProgress,
    ),
  );

  @override
  Future<void> deleteDocument(String documentId) async {
    await api.delete('/documents/$documentId');
  }

  @override
  Future<List<ShareItem>> shares(String type, String id) async =>
      (await api.getList('/shares/$type/$id')).map(ShareItem.fromJson).toList();

  @override
  Future<void> addShare(String type, String id, String userId) async {
    await api.post(
      '/shares',
      data: {'resource_type': type, 'resource_id': id, 'user_id': userId},
    );
  }

  @override
  Future<void> removeShare(String shareId) async {
    await api.delete('/shares/$shareId');
  }

  @override
  Future<List<PersonRef>> shareCandidates() async =>
      (await api.getList('/users')).map(PersonRef.fromJson).toList();

  @override
  Future<List<ActivityItem>> activity(String type, String id) async =>
      (await api.getList('/activity/$type/$id'))
          .map(ActivityItem.fromJson)
          .toList();
}

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => HttpJobsRepository(ref.watch(apiClientProvider)),
);

// ---- Ayrıntı sağlayıcıları (otomatik yeniden deneme KAPALI: hata ekranı "Tekrar dene" ile) ----
Duration? _noRetry(int retryCount, Object error) => null;

final offerProvider = FutureProvider.autoDispose.family<Offer, String>(
  (ref, id) => ref.watch(jobsRepositoryProvider).offer(id),
  retry: _noRetry,
);

typedef ProjectKey = ({String id, bool fieldMode});

final projectFullProvider = FutureProvider.autoDispose
    .family<ProjectFull, ProjectKey>(
      (ref, k) => ref
          .watch(jobsRepositoryProvider)
          .projectFull(k.id, fieldMode: k.fieldMode),
      retry: _noRetry,
    );

typedef ResourceKey = ({String type, String id});

final documentsProvider = FutureProvider.autoDispose
    .family<List<DocumentItem>, ResourceKey>(
      (ref, k) => ref.watch(jobsRepositoryProvider).documents(k.type, k.id),
      retry: _noRetry,
    );

final sharesProvider = FutureProvider.autoDispose
    .family<List<ShareItem>, ResourceKey>(
      (ref, k) => ref.watch(jobsRepositoryProvider).shares(k.type, k.id),
      retry: _noRetry,
    );

final activityProvider = FutureProvider.autoDispose
    .family<List<ActivityItem>, ResourceKey>(
      (ref, k) => ref.watch(jobsRepositoryProvider).activity(k.type, k.id),
      retry: _noRetry,
    );

final quoteTemplatesProvider = FutureProvider.autoDispose<List<QuoteTemplate>>(
  (ref) => ref.watch(jobsRepositoryProvider).quoteTemplates(),
  retry: _noRetry,
);

final collaboratorsProvider = FutureProvider.autoDispose
    .family<List<PersonRef>, String>(
      (ref, projectId) =>
          ref.watch(jobsRepositoryProvider).collaborators(projectId),
      retry: _noRetry,
    );

final shareCandidatesProvider = FutureProvider.autoDispose<List<PersonRef>>(
  (ref) => ref.watch(jobsRepositoryProvider).shareCandidates(),
  retry: _noRetry,
);
