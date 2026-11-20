// SAHİBİ: jobs ajanı. İşler sekmesi: Teklifler / Projeler (tasarım ekran 5).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_access.dart';
import '../data/jobs_models.dart';
import '../data/jobs_project_models.dart';
import '../jobs_paths.dart';
import 'jobs_cards.dart';
import 'jobs_common.dart';
import 'jobs_lists.dart';
import 'offer_bulk.dart';
import 'paged_list_body.dart';

class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(jobsAccessProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    final showOffers = access.canSeeOffers;
    final showProjects = access.canSeeProjects;
    if (!showOffers && !showProjects) {
      return const AppScaffold(
        title: 'İşler',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
        ),
      );
    }
    final tabs = [
      if (showOffers) _JobsTab.offers,
      if (showProjects) _JobsTab.projects,
    ];
    // Sekme sayıları: süzgeçsiz listelerin toplamı (aynı sağlayıcı, ek istek yok).
    final offerTotal = showOffers
        ? ref.watch(offersListProvider(const OfferQuery())).value?.total
        : null;
    final projectTotal = showProjects
        ? ref.watch(projectsListProvider(const ProjectQuery())).value?.total
        : null;
    String label(_JobsTab t) => switch (t) {
      _JobsTab.offers =>
        offerTotal == null ? terms.offers : '${terms.offers} ($offerTotal)',
      _JobsTab.projects =>
        projectTotal == null ? terms.jobs : '${terms.jobs} ($projectTotal)',
    };
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          return AppScaffold(
            title: 'İşler',
            bottom: tabs.length > 1
                ? TabBar(tabs: [for (final t in tabs) Tab(text: label(t))])
                : null,
            floatingActionButton: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final tab = tabs[controller.index.clamp(0, tabs.length - 1)];
                final isOffer = tab == _JobsTab.offers;
                final tip = isOffer
                    ? 'Yeni ${terms.offer}'
                    : 'Yeni ${terms.job}';
                return FloatingActionButton(
                  tooltip: tip,
                  onPressed: () async {
                    await context.push(
                      isOffer ? JobsPaths.newOffer : JobsPaths.newProject,
                    );
                    _refreshAll(ref);
                  },
                  child: const Icon(Icons.add),
                );
              },
            ),
            body: tabs.length > 1
                ? TabBarView(
                    children: [
                      for (final t in tabs)
                        t == _JobsTab.offers
                            ? const OffersTab()
                            : const ProjectsTab(),
                    ],
                  )
                : (tabs.first == _JobsTab.offers
                      ? const OffersTab()
                      : const ProjectsTab()),
          );
        },
      ),
    );
  }

  /// Yeni kayıt sonrası görünür listeleri sessizce yeniler (kaydırma bozulmaz).
  static void _refreshAll(WidgetRef ref) {
    ref.invalidate(offersListProvider);
    ref.invalidate(projectsListProvider);
  }
}

enum _JobsTab { offers, projects }

/// Arama kutusu (400 ms gecikmeli) + temizleme düğmesi.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.hint, required this.onChanged});
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final TextEditingController _c = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => widget.onChanged(v.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.md,
        Space.lg,
        Space.xs,
      ),
      child: TextField(
        controller: _c,
        textInputAction: TextInputAction.search,
        maxLength: 100,
        buildCounter: (
          _, {
          required currentLength,
          required isFocused,
          required maxLength,
        }) => null,
        onChanged: _changed,
        onSubmitted: (v) {
          _debounce?.cancel();
          widget.onChanged(v.trim());
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _c.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Aramayı temizle',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _c.clear();
                    _debounce?.cancel();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: Sizes.minTouch + Space.xs,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, i) => Center(child: chips[i]),
      ),
    );
  }
}

Widget _choice(
  String label, {
  required bool selected,
  required VoidCallback onTap,
}) => ChoiceChip(
  label: Text(label),
  selected: selected,
  materialTapTargetSize: MaterialTapTargetSize.padded,
  onSelected: (_) => onTap(),
);

// ---------------------------------------------------------------------------
// Teklifler
// ---------------------------------------------------------------------------

class OffersTab extends ConsumerStatefulWidget {
  const OffersTab({super.key});

  @override
  ConsumerState<OffersTab> createState() => _OffersTabState();
}

class _OffersTabState extends ConsumerState<OffersTab>
    with AutomaticKeepAliveClientMixin {
  String _q = '';
  OfferStatus? _status;

  /// Çoklu seçim kipi ve seçili teklif kimlikleri.
  bool _selecting = false;
  bool _bulkBusy = false;
  Set<String> _selected = <String>{};

  @override
  bool get wantKeepAlive => true;

  OfferQuery get _query => OfferQuery(q: _q, status: _status);

  void _exitSelection() => setState(() {
    _selecting = false;
    _selected = <String>{};
  });

  /// Süzgeç değişince (görünmeyen kayıtlar seçili kalmasın) seçim sıfırlanır.
  void _filterChanged(void Function() change) => setState(() {
    change();
    _selected = <String>{};
  });

  List<Offer> _loaded() =>
      ref.read(offersListProvider(_query)).value?.items ?? const [];

  /// Seçili kayıtlar, yalnız şu an yüklü olanlar (görünmeyen kayıt asla işlenmez).
  List<Offer> _selectedOffers() => [
    for (final o in _loaded())
      if (_selected.contains(o.id)) o,
  ];

  void _toggle(String id) => setState(() {
    _selected = _selected.contains(id)
        ? ({..._selected}..remove(id))
        : {..._selected, id};
  });

  void _toggleAll() {
    final ids = _loaded().map((o) => o.id).toSet();
    setState(() {
      _selected = _selected.length >= ids.length && ids.isNotEmpty
          ? <String>{}
          : ids;
    });
  }

  Future<void> _bulkStatus() async {
    final sel = _selectedOffers();
    if (sel.isEmpty || _bulkBusy) return;
    final next = await showOfferStatusSheet(context, '');
    if (next == null || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      final out = await bulkChangeOfferStatus(
        context,
        ref,
        sel,
        next,
        onApplied: (ids, st) {
          if (mounted) _notifier.replaceStatuses(ids, st);
        },
        onRefresh: _silentRefresh,
      );
      if (out == null || !mounted) return;
      // Başarılar seçimden düşer; hatalılar seçili kalır (yeniden denenebilir).
      setState(() {
        _selected = {for (final f in out.failures) f.target.id};
        if (out.allOk) _selecting = false;
      });
      await _silentRefresh();
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _bulkDelete() async {
    final sel = _selectedOffers();
    if (sel.isEmpty || _bulkBusy) return;
    final notifier = _notifier;
    await bulkDeleteOffers(
      context,
      ref,
      sel,
      onHide: (ids) {
        notifier.removeIds(ids);
        if (mounted) {
          setState(() {
            _selected = <String>{};
            _selecting = false;
          });
        }
      },
      onRefresh: _silentRefresh,
      onFailed: (ids) {
        if (mounted) {
          setState(() {
            _selected = ids;
            _selecting = true;
          });
        }
      },
    );
  }

  OffersListNotifier get _notifier =>
      ref.read(offersListProvider(_query).notifier);

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      await _notifier.refresh();
    } catch (_) {
      // Sessiz: eski liste kalır; kullanıcı çekip yenileyebilir.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final terms = ref.watch(brandProfileProvider).terms;
    final provider = offersListProvider(_query);
    final value = ref.watch(provider);
    final offerLower = terms.offer.toLowerCase();
    final access = ref.watch(jobsAccessProvider);
    final canSelect = access.canBulkOfferStatus || access.canBulkDeleteOffers;
    final loaded = value.value?.items ?? const <Offer>[];
    final loadedIds = loaded.map((o) => o.id).toSet();
    final selectedCount = _selected.where(loadedIds.contains).length;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_bulkBusy) _exitSelection();
      },
      child: Column(
        children: [
          _SearchField(
            hint: 'Ara (${terms.customer.toLowerCase()}, kod, hizmet…)',
            onChanged: (v) => _filterChanged(() => _q = v),
          ),
          _ChipRow(
            chips: [
              _choice(
                'Tümü',
                selected: _status == null,
                onTap: () => _filterChanged(() => _status = null),
              ),
              for (final s in OfferStatus.values)
                _choice(
                  s.label,
                  selected: _status == s,
                  onTap: () =>
                      _filterChanged(() => _status = _status == s ? null : s),
                ),
            ],
          ),
          if (_selecting)
            OfferSelectionBar(
              selectedCount: selectedCount,
              visibleCount: loaded.length,
              total: value.value?.total ?? loaded.length,
              canStatus: access.canBulkOfferStatus,
              canDelete: access.canBulkDeleteOffers,
              busy: _bulkBusy,
              onToggleAll: _toggleAll,
              onClear: () => setState(() => _selected = <String>{}),
              onExit: _exitSelection,
              onStatus: _bulkStatus,
              onDelete: _bulkDelete,
            )
          else if (value.value != null && loaded.isNotEmpty)
            OfferListHeader(
              total: value.value!.total,
              canSelect: canSelect,
              onSelect: () => setState(() => _selecting = true),
            ),
          Expanded(
            child: PagedListBody<Offer>(
              value: value,
              onRetry: () => ref.invalidate(provider),
              onRefresh: () => _notifier.refresh(),
              onLoadMore: () => _notifier.loadMore(),
              onRetryLoadMore: () => _notifier.retryLoadMore(),
              empty: _query.isFiltered
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: 'Sonuç bulunamadı',
                      message:
                          'Arama ya da durum süzgecini değiştirmeyi deneyin.',
                      actionLabel: 'Süzgeçleri temizle',
                      onAction: () => setState(() {
                        _q = '';
                        _status = null;
                      }),
                    )
                  : EmptyState(
                      icon: Icons.request_quote_outlined,
                      title: 'Henüz $offerLower yok',
                      message:
                          'Yeni bir $offerLower talebi eklediğinizde burada görünür.',
                      actionLabel: 'Yeni ${terms.offer}',
                      onAction: () async {
                        await context.push(JobsPaths.newOffer);
                        ref.invalidate(offersListProvider);
                      },
                    ),
              itemBuilder: (context, o) => OfferCard(
                offer: o,
                selecting: _selecting,
                selected: _selected.contains(o.id),
                onLongPress: canSelect && !_selecting
                    ? () => setState(() {
                        _selecting = true;
                        _selected = {o.id};
                      })
                    : null,
                onTap: () async {
                  if (_selecting) {
                    _toggle(o.id);
                    return;
                  }
                  await context.push(Routes.offer(o.id));
                  await _silentRefresh();
                },
                onStatusTap: () async {
                  final s = await showOfferStatusSheet(context, o.status);
                  if (s == null || !context.mounted) return;
                  await changeOfferStatus(
                    context,
                    ref,
                    o,
                    s,
                    onApplied: (st) {
                      if (mounted) _notifier.replaceStatus(o.id, st);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Projeler
// ---------------------------------------------------------------------------

const _kActive = 'devam';
const _kDone = 'tamam';

/// Proje listesi bölüm başlığı: "Devam eden projeler · 12" (devamı yüklenecekse "12+").
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.more,
  });
  final String title;
  final int count;
  final bool more;

  @override
  Widget build(BuildContext context) {
    final n = '$count${more ? '+' : ''}';
    return Semantics(
      header: true,
      label: '$title, $n kayıt',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: Space.sm),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Space.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm,
                    vertical: 2,
                  ),
                  child: Text(n, style: context.text.labelMedium),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectsTab extends ConsumerStatefulWidget {
  const ProjectsTab({super.key});

  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab>
    with AutomaticKeepAliveClientMixin {
  String _q = '';
  ProjectFilter _filter = ProjectFilter.all;

  @override
  bool get wantKeepAlive => true;

  ProjectQuery get _query => ProjectQuery(q: _q);

  ProjectsListNotifier get _notifier =>
      ref.read(projectsListProvider(_query).notifier);

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      await _notifier.refresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final terms = ref.watch(brandProfileProvider).terms;
    final access = ref.watch(jobsAccessProvider);
    final provider = projectsListProvider(_query);
    final value = ref.watch(provider);
    final jobLower = terms.job.toLowerCase();
    final filtered = _q.isNotEmpty || _filter != ProjectFilter.all;

    return Column(
      children: [
        _SearchField(
          hint: 'Ara (${terms.customer.toLowerCase()}, kod, hizmet…)',
          onChanged: (v) => setState(() => _q = v),
        ),
        _ChipRow(
          chips: [
            for (final f in ProjectFilter.values)
              _choice(
                f.labelWithCount(value.value),
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
          ],
        ),
        Expanded(
          child: PagedListBody<Project>(
            value: value,
            onRetry: () => ref.invalidate(provider),
            onRefresh: () => _notifier.refresh(),
            onLoadMore: () => _notifier.loadMore(),
            onRetryLoadMore: () => _notifier.retryLoadMore(),
            where: _filter == ProjectFilter.all ? null : _filter.matches,
            groupOf: (p) =>
                p.stageEnum == ProjectStage.tamamlandi ? _kDone : _kActive,
            groupOrder: const [_kActive, _kDone],
            groupHeader: (context, g, count, more) => _SectionHeader(
              title: g == _kActive
                  ? 'Devam eden ${terms.jobs.toLowerCase()}'
                  : 'Tamamlananlar',
              count: count,
              more: more,
            ),
            empty: filtered
                ? EmptyState(
                    icon: Icons.search_off,
                    title: 'Sonuç bulunamadı',
                    message:
                        'Arama ya da aşama süzgecini değiştirmeyi deneyin.',
                    actionLabel: 'Süzgeçleri temizle',
                    onAction: () => setState(() {
                      _q = '';
                      _filter = ProjectFilter.all;
                    }),
                  )
                : EmptyState(
                    icon: Icons.construction_outlined,
                    title: 'Henüz $jobLower yok',
                    message:
                        'Kabul edilen ${terms.offers.toLowerCase()} otomatik $jobLower olur; elle de ekleyebilirsiniz.',
                    actionLabel: 'Yeni ${terms.job}',
                    onAction: () async {
                      await context.push(JobsPaths.newProject);
                      ref.invalidate(projectsListProvider);
                    },
                  ),
            emptyFiltered: EmptyState(
              icon: Icons.filter_alt_off,
              title: 'Bu süzgece uyan $jobLower yok',
              actionLabel: 'Süzgeci kaldır',
              onAction: () => setState(() => _filter = ProjectFilter.all),
            ),
            itemBuilder: (context, p) => ProjectCard(
              project: p,
              showMoney: access.showProjectMoney,
              onStageChanged: (st) {
                if (mounted) _notifier.replaceStage(p.id, st);
              },
              onTap: () async {
                await context.push(Routes.project(p.id));
                await _silentRefresh();
              },
            ),
          ),
        ),
      ],
    );
  }
}
