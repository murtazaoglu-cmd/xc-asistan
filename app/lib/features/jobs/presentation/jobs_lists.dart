// SAHİBİ: jobs ajanı. Sayfalı liste durumu (limit/offset + X-Total-Count; sonsuz kaydırma).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart' show Paged;
import '../../../core/api/api_exception.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_models.dart';
import '../data/jobs_project_models.dart';
import '../data/jobs_repository.dart';

const int jobsPageSize = 30;

/// Sunucu `limit` en çok 200 kabul eder.
const int _maxLimit = 200;

@immutable
class PagedList<T> {
  const PagedList({
    required this.items,
    required this.total,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;

  /// `X-Total-Count` (başlık yoksa yüklenen sayı).
  final int total;
  final bool loadingMore;
  final AppException? loadMoreError;

  bool get hasMore => items.length < total;

  PagedList<T> copyWith({
    List<T>? items,
    int? total,
    bool? loadingMore,
    AppException? loadMoreError,
    bool clearError = false,
  }) => PagedList(
    items: items ?? this.items,
    total: total ?? this.total,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

@immutable
class OfferQuery {
  const OfferQuery({this.q = '', this.status});
  final String q;
  final OfferStatus? status;

  bool get isFiltered => q.trim().isNotEmpty || status != null;

  @override
  bool operator ==(Object other) =>
      other is OfferQuery && other.q == q && other.status == status;

  @override
  int get hashCode => Object.hash(q, status);
}

@immutable
class ProjectQuery {
  const ProjectQuery({this.q = ''});
  final String q;

  @override
  bool operator ==(Object other) => other is ProjectQuery && other.q == q;

  @override
  int get hashCode => q.hashCode;
}

/// Ortak sayfalama mantığı: ilk sayfa, sonraki sayfa, sessiz yenileme.
abstract class _PagedNotifier<T, Q> extends AsyncNotifier<PagedList<T>> {
  _PagedNotifier(this.query);
  final Q query;
  bool _busy = false;

  Future<Paged<T>> fetch(int limit, int offset);

  @override
  Future<PagedList<T>> build() async {
    final p = await fetch(jobsPageSize, 0);
    return _fromPage(p);
  }

  PagedList<T> _fromPage(Paged<T> p) => PagedList(
    items: p.items,
    // Boş sayfa gelirse sonsuz yüklemeyi önle.
    total: p.items.isEmpty ? 0 : p.total,
  );

  /// Listenin sonuna yaklaşınca çağrılır. Çift çağrı ve hata sonrası döngü engellenir.
  Future<void> loadMore() async {
    final cur = state.value;
    if (cur == null || !cur.hasMore || cur.loadingMore || _busy) return;
    if (cur.loadMoreError != null) return; // kullanıcı "Tekrar dene" demeli
    _busy = true;
    state = AsyncData(cur.copyWith(loadingMore: true, clearError: true));
    try {
      final p = await fetch(jobsPageSize, cur.items.length);
      final merged = [...cur.items, ...p.items];
      state = AsyncData(
        PagedList(
          items: merged,
          total: p.items.isEmpty ? merged.length : p.total,
        ),
      );
    } catch (e) {
      state = AsyncData(
        cur.copyWith(loadingMore: false, loadMoreError: AppException.from(e)),
      );
    } finally {
      _busy = false;
    }
  }

  /// "Devamı yüklenemedi" satırındaki Tekrar dene.
  Future<void> retryLoadMore() async {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(cur.copyWith(clearError: true));
    await loadMore();
  }

  /// Yüklü kayıt sayısı kadarını (en çok 200) baştan çekip listeyi KAYDIRMAYI bozmadan yeniler.
  /// Başarısızlıkta eski liste kalır ve hata fırlatılır.
  Future<void> refresh() async {
    final cur = state.value;
    final limit = cur == null
        ? jobsPageSize
        : cur.items.length.clamp(jobsPageSize, _maxLimit);
    final p = await fetch(limit, 0);
    state = AsyncData(_fromPage(p));
  }
}

class OffersListNotifier extends _PagedNotifier<Offer, OfferQuery> {
  OffersListNotifier(super.query);

  @override
  Future<Paged<Offer>> fetch(int limit, int offset) => ref
      .read(jobsRepositoryProvider)
      .offers(q: query.q, status: query.status, limit: limit, offset: offset);

  /// Durum değişimini listeye anında yansıtır (sunucuya yazıldıktan sonra).
  void replaceStatus(String id, String status) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(
        items: [
          for (final o in cur.items) o.id == id ? o.withStatus(status) : o,
        ],
      ),
    );
  }

  /// Toplu durum değişimini listeye anında yansıtır.
  void replaceStatuses(Set<String> ids, String status) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(
        items: [
          for (final o in cur.items)
            ids.contains(o.id) ? o.withStatus(status) : o,
        ],
      ),
    );
  }

  /// Silinen (silme gecikmesi süren) kayıtları listeden çıkarır; toplam da düşer.
  void removeIds(Set<String> ids) {
    final cur = state.value;
    if (cur == null) return;
    final kept = cur.items.where((o) => !ids.contains(o.id)).toList();
    state = AsyncData(
      cur.copyWith(
        items: kept,
        total: (cur.total - (cur.items.length - kept.length)).clamp(
          kept.length,
          1 << 30,
        ),
      ),
    );
  }
}

final offersListProvider = AsyncNotifierProvider.autoDispose
    .family<OffersListNotifier, PagedList<Offer>, OfferQuery>(
      OffersListNotifier.new,
      retry: (_, _) => null,
    );

class ProjectsListNotifier extends _PagedNotifier<Project, ProjectQuery> {
  ProjectsListNotifier(super.query);

  @override
  Future<Paged<Project>> fetch(int limit, int offset) => ref
      .read(jobsRepositoryProvider)
      .projects(q: query.q, limit: limit, offset: offset);

  void replaceStage(String id, String stage) {
    final cur = state.value;
    if (cur == null) return;
    state = AsyncData(
      cur.copyWith(
        items: [for (final p in cur.items) p.id == id ? p.withStage(stage) : p],
      ),
    );
  }
}

final projectsListProvider = AsyncNotifierProvider.autoDispose
    .family<ProjectsListNotifier, PagedList<Project>, ProjectQuery>(
      ProjectsListNotifier.new,
      retry: (_, _) => null,
    );

/// Proje listesindeki istemci tarafı süzgeç (sunucuda aşama süzgeci YOK: yalnız ?q).
enum ProjectFilter {
  all('Tümü'),
  malzeme('Malzeme Temini'),
  uretim('Üretim'),
  montaj('Montaj'),
  teslim('Teslim'),
  tamamlandi('Tamamlandı'),
  overdue('Geciken');

  const ProjectFilter(this.label);
  final String label;

  /// Süzgeç çipi etiketi + yüklü kayıtlardaki sayı. Sunucu aşama süzgeci sunmadığından sayı yalnız
  /// YÜKLÜ kayıtlardandır; devamı varsa "+" eklenir ("Tümü" için sunucunun toplamı).
  String labelWithCount(PagedList<Project>? data, [DateTime? now]) {
    if (data == null) return label;
    if (this == ProjectFilter.all) return '$label (${data.total})';
    final n = data.items.where((p) => matches(p, now)).length;
    return '$label ($n${data.hasMore ? '+' : ''})';
  }

  bool matches(Project p, [DateTime? now]) {
    switch (this) {
      case ProjectFilter.all:
        return true;
      case ProjectFilter.malzeme:
        return p.stageEnum == ProjectStage.malzemeTemini;
      case ProjectFilter.uretim:
        return p.stageEnum == ProjectStage.uretim;
      case ProjectFilter.montaj:
        return p.stageEnum == ProjectStage.montaj;
      case ProjectFilter.teslim:
        return p.stageEnum == ProjectStage.teslim;
      case ProjectFilter.tamamlandi:
        return p.stageEnum == ProjectStage.tamamlandi;
      case ProjectFilter.overdue:
        return p.isOverdue(now);
    }
  }
}
