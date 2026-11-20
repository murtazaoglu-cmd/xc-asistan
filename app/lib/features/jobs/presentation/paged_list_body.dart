// SAHİBİ: jobs ajanı. Sonsuz kaydırmalı liste gövdesi: iskelet / hata / boş / veri + alt şerit.
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import 'jobs_common.dart';
import 'jobs_lists.dart';

class PagedListBody<T> extends StatefulWidget {
  const PagedListBody({
    super.key,
    required this.value,
    required this.itemBuilder,
    required this.empty,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onRetryLoadMore,
    this.where,
    this.emptyFiltered,
    this.skeletonHeight = 110,
    this.groupOf,
    this.groupOrder = const [],
    this.groupHeader,
  });

  final AsyncValue<PagedList<T>> value;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Hiç kayıt yokken gösterilen boş durum.
  final Widget empty;

  /// [where] ile süzülünce hiçbir şey kalmazsa gösterilen boş durum (yoksa [empty]).
  final Widget? emptyFiltered;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final VoidCallback onRetryLoadMore;

  /// İstemci tarafı süzgeç (sunucuda desteklenmeyen süzgeçler için).
  final bool Function(T item)? where;
  final double skeletonHeight;

  /// Kayıtları bölümlere ayırır (ör. "Devam eden" / "Tamamlananlar"). Bölümler [groupOrder] sırasıyla,
  /// bölüm içinde sunucu sırası korunur; boş bölümün başlığı çizilmez. [groupHeader] verilmezse bölümleme yok.
  final String Function(T item)? groupOf;
  final List<String> groupOrder;

  /// (bölüm, yüklü kayıt sayısı, devamı var mı).
  final Widget Function(
    BuildContext context,
    String group,
    int count,
    bool more,
  )?
  groupHeader;

  @override
  State<PagedListBody<T>> createState() => _PagedListBodyState<T>();
}

class _PagedListBodyState<T> extends State<PagedListBody<T>> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter < 600) widget.onLoadMore();
  }

  /// İçerik ekranı doldurmuyorsa (kaydırma yok) ya da süzgeç az sonuç bıraktıysa devamını getir.
  void _autoFill(PagedList<T> d, int visibleCount) {
    if (!mounted || !d.hasMore || d.loadingMore || d.loadMoreError != null) {
      return;
    }
    final noScroll =
        _controller.hasClients && _controller.position.maxScrollExtent <= 0;
    if (visibleCount == 0 ||
        noScroll ||
        (widget.where != null && visibleCount < 8)) {
      widget.onLoadMore();
    }
  }

  Future<void> _refresh() async {
    try {
      await widget.onRefresh();
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncValueView<PagedList<T>>(
      value: widget.value,
      onRetry: widget.onRetry,
      loading: SkeletonList(itemHeight: widget.skeletonHeight),
      isEmpty: (d) => d.items.isEmpty,
      empty: PullToRefresh.fill(onRefresh: _refresh, child: widget.empty),
      data: (d) {
        final items = widget.where == null
            ? d.items
            : d.items.where(widget.where!).toList();
        SchedulerBinding.instance.addPostFrameCallback(
          (_) => _autoFill(d, items.length),
        );
        if (items.isEmpty && !d.hasMore) {
          return PullToRefresh.fill(
            onRefresh: _refresh,
            child: widget.emptyFiltered ?? widget.empty,
          );
        }
        final showFooter =
            d.loadingMore || d.loadMoreError != null || d.items.isNotEmpty;
        // Bölümleme: [başlık | kayıt] düz listesi.
        final grouped = widget.groupOf != null && widget.groupHeader != null;
        final rows = <Object?>[];
        if (grouped) {
          for (final g in widget.groupOrder) {
            final inGroup = items
                .where((e) => widget.groupOf!(e) == g)
                .toList();
            if (inGroup.isEmpty) continue;
            rows.add(_GroupRow(g, inGroup.length));
            rows.addAll(inGroup.cast<Object>());
          }
        }
        final rowCount = grouped ? rows.length : items.length;
        return PullToRefresh(
          onRefresh: _refresh,
          child: ListView.separated(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.sm,
              Space.lg,
              // Sağ alttaki + düğmesinin son kartı kapatmaması için.
              Space.xxxl + Space.xxl,
            ),
            itemCount: rowCount + (showFooter ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) {
              if (i < rowCount) {
                if (!grouped) return widget.itemBuilder(context, items[i]);
                final r = rows[i];
                if (r is _GroupRow) {
                  return widget.groupHeader!(
                    context,
                    r.group,
                    r.count,
                    d.hasMore,
                  );
                }
                return widget.itemBuilder(context, r as T);
              }
              return _Footer(
                loading:
                    d.loadingMore || (d.hasMore && d.loadMoreError == null),
                error: d.loadMoreError?.message,
                total: d.total,
                onRetry: widget.onRetryLoadMore,
              );
            },
          ),
        );
      },
    );
  }
}

class _GroupRow {
  const _GroupRow(this.group, this.count);
  final String group;
  final int count;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loading,
    required this.error,
    required this.total,
    required this.onRetry,
  });
  final bool loading;
  final String? error;
  final int total;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Column(
          children: [
            Text(
              'Devamı yüklenemedi. $error',
              textAlign: TextAlign.center,
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar dene'),
            ),
          ],
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.lg),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Center(
        child: Text(
          'Toplam $total kayıt',
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
