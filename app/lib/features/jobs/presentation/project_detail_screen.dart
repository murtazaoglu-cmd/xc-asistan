// SAHİBİ: jobs ajanı. Proje detayı (tasarım ekran 7): ilerleme, Özet / Görevler / Ödemeler / Giderler / Belgeler.
// Rol görünürlüğü `JobsAccess` ile (saha: sözleşme ve finans yok; ödeme/gider satırları finans yetkisiyle).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/auth/auth_models.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/money.dart';
import '../data/document_picker.dart';
import '../data/jobs_access.dart';
import '../data/jobs_project_models.dart';
import '../data/jobs_repository.dart';
import '../../finance/finance_nav.dart';
import 'jobs_common.dart';
import 'jobs_lists.dart' show projectsListProvider;
import 'resource_sections.dart';
import 'stage_actions.dart';

enum _PTab {
  overview('Özet'),
  tasks('Görevler'),
  payments('Ödemeler'),
  expenses('Giderler'),
  documents('Belgeler');

  const _PTab(this.label);
  final String label;
}

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  final Set<String> _hidden =
      {}; // silinmesi bekleyen görev/ilave iş kimlikleri
  ProjectKey get _key =>
      (id: widget.id, fieldMode: ref.read(jobsAccessProvider).isField);

  void _reload() => ref.invalidate(projectFullProvider(_key));

  Future<void> _refresh() async {
    try {
      _reload();
      await ref.read(projectFullProvider(_key).future);
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  // -------------------------------------------------------------- aşama
  Future<void> _setStage(ProjectFull full, ProjectStage next) =>
      changeProjectStage(
        context,
        ref,
        projectId: widget.id,
        current: full.project.stageEnum,
        next: next,
        onChanged: (_) {
          if (mounted) _reload();
        },
      );

  // -------------------------------------------------------------- bilgi / tutar / not
  Future<void> _editNotes(Project p) async {
    final c = TextEditingController(text: p.notes ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(hintText: 'Not yazın'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    c.dispose();
    if (saved == null || !mounted) return;
    try {
      await ref
          .read(jobsRepositoryProvider)
          .setProjectInfo(widget.id, notes: saved);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  Future<void> _editMoneyAndDates(ProjectFull full) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _ProjectEditSheet(
          projectId: widget.id,
          project: full.project,
          canEditAmount: ref.read(jobsAccessProvider).showProjectMoney,
        ),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  // -------------------------------------------------------------- ilave iş
  Future<void> _addExtra() async {
    final desc = TextEditingController();
    final amount = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İlave iş'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: desc,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Açıklama'),
                validator: ProjectValidators.extraDescription,
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-−]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Tutar',
                  prefixText: '₺ ',
                  helperText: 'İndirim için eksi (-) yazın.',
                ),
                validator: ProjectValidators.extraAmount,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    final d = desc.text;
    final a = Money.parseUserInput(amount.text);
    desc.dispose();
    amount.dispose();
    if (ok != true || a == null || !mounted) return;
    try {
      await ref.read(jobsRepositoryProvider).addExtra(widget.id, d, a);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  void _deleteExtra(ProjectExtra e) {
    final repo = ref.read(jobsRepositoryProvider);
    setState(() => _hidden.add(e.id));
    UndoSnackbar.deferred(
      context,
      message: '${e.description} silindi',
      onUndo: () {
        if (mounted) setState(() => _hidden.remove(e.id));
      },
      onCommit: () async {
        try {
          await repo.deleteExtra(e.id);
        } catch (err) {
          if (mounted) {
            setState(() => _hidden.remove(e.id));
            showJobsError(context, err);
          }
        }
        if (mounted) _reload();
      },
    );
  }

  // -------------------------------------------------------------- görevler
  Future<void> _setTask(ProjectTask t, TaskStatus s) async {
    try {
      await ref.read(jobsRepositoryProvider).setTaskStatus(t.id, s);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  void _deleteTask(ProjectTask t) {
    final repo = ref.read(jobsRepositoryProvider);
    setState(() => _hidden.add(t.id));
    UndoSnackbar.deferred(
      context,
      message: '"${t.title}" silindi',
      onUndo: () {
        if (mounted) setState(() => _hidden.remove(t.id));
      },
      onCommit: () async {
        try {
          await repo.deleteTask(t.id);
        } catch (err) {
          if (mounted) {
            setState(() => _hidden.remove(t.id));
            showJobsError(context, err);
          }
        }
        if (mounted) _reload();
      },
    );
  }

  Future<void> _taskSheet(ProjectTask t) async {
    final pick = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t.title, style: ctx.text.titleMedium),
              ),
            ),
            for (final s in TaskStatus.values)
              ListTile(
                minTileHeight: Sizes.minTouch,
                selected: t.statusEnum == s,
                leading: Icon(
                  t.statusEnum == s
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(s.label),
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            ListTile(
              minTileHeight: Sizes.minTouch,
              leading: Icon(Icons.delete_outline, color: ctx.colors.error),
              title: Text(
                'Görevi sil',
                style: TextStyle(color: ctx.colors.error),
              ),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (pick is TaskStatus) {
      await _setTask(t, pick);
    } else if (pick == 'delete') {
      _deleteTask(t);
    }
  }

  /// Proje silme (yalnız admin; DELETE /projects/:id geri alınamaz). Bağlı kayıt uyarısı + onay,
  /// sonra gerçek DELETE "Geri al" süresi kadar geciktirilir.
  Future<void> _deleteProject(ProjectFull full) async {
    final terms = ref.read(brandProfileProvider).terms;
    final p = full.project;
    final hasLedger = full.payments.isNotEmpty || full.expenses.isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var understood = !hasLedger;
        return StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: Text('${terms.job} silinsin mi?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${p.code} · ${p.customerName}. Silme geri alınamaz.'),
                  const SizedBox(height: Space.sm),
                  Text(projectDeleteWarning(full)),
                  if (hasLedger) ...[
                    const SizedBox(height: Space.sm),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: understood,
                      onChanged: (v) => setS(() => understood = v ?? false),
                      title: const Text(
                        'Bağlı ödeme ve gider kayıtlarının da silineceğini anlıyorum.',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ctx.colors.error,
                  foregroundColor: ctx.colors.onError,
                ),
                onPressed: understood
                    ? () => Navigator.of(ctx).pop(true)
                    : null,
                child: const Text('Sil'),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    final repo = ref.read(jobsRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final pending = UndoSnackbar.deferred(
      context,
      message: '${p.code} silindi',
      onCommit: () async {
        try {
          await repo.deleteProject(p.id);
        } catch (e) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  '${p.code} silinemedi: ${AppException.from(e).message}',
                ),
              ),
            );
        }
        container.invalidate(projectsListProvider);
      },
    );
    context.pop();
    await pending;
  }

  // -------------------------------------------------------------- ekran
  @override
  Widget build(BuildContext context) {
    final access = ref.watch(jobsAccessProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    final async = ref.watch(projectFullProvider(_key));
    final full = async.value;
    return AppScaffold(
      title: full == null ? terms.job : '${terms.job}: ${full.project.code}',
      showMenuButton: false,
      actions: full == null || !access.canDeleteProject
          ? null
          : [
              PopupMenuButton<String>(
                tooltip: 'Diğer işlemler',
                onSelected: (v) {
                  if (v == 'delete') _deleteProject(full);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text('${terms.job} sil'),
                  ),
                ],
              ),
            ],
      body: AsyncValueView<ProjectFull>(
        value: async,
        onRetry: _reload,
        data: (full) {
          final tabs = [
            _PTab.overview,
            _PTab.tasks,
            if (access.showLedger) ...[_PTab.payments, _PTab.expenses],
            _PTab.documents,
          ];
          return DefaultTabController(
            key: ValueKey(tabs.length),
            length: tabs.length,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: _ProjectHeader(
                    full: full,
                    access: access,
                    busy: ref.watch(stageBusyProvider).contains(widget.id),
                    onStage: (s) => _setStage(full, s),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [for (final t in tabs) Tab(text: t.label)],
                    ),
                    context.colors.surface,
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  for (final t in tabs)
                    PullToRefresh(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(Space.lg),
                        children: [_tabBody(t, full, access, terms)],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tabBody(
    _PTab t,
    ProjectFull full,
    JobsAccess access,
    Glossary terms,
  ) {
    switch (t) {
      case _PTab.overview:
        return _overview(full, access, terms);
      case _PTab.tasks:
        return _tasks(full, access);
      case _PTab.payments:
        return _payments(full, access);
      case _PTab.expenses:
        return _expenses(full, access);
      case _PTab.documents:
        return Column(
          children: [DocumentsSection(type: 'project', id: widget.id)],
        );
    }
  }

  // -------------------------------------------------------------- Özet
  Widget _overview(ProjectFull full, JobsAccess access, Glossary terms) {
    final p = full.project;
    final x = context.xc;
    final extras = full.extras.where((e) => !_hidden.contains(e.id)).toList();
    final extrasTotal = Money.sum(extras.map((e) => e.amount));
    final contract = full.contract;
    final balance = contract == null
        ? null
        : contract + extrasTotal - full.paidTotal;
    return Column(
      children: [
        if ((p.customerPhone ?? '').isNotEmpty) ...[
          PhoneActions(phone: p.customerPhone, name: p.customerName),
          PhoneActionButtons(phone: p.customerPhone, name: p.customerName),
        ],
        AddressActions(
          address: p.address,
          lat: p.lat,
          lng: p.lng,
          showButton: true,
        ),
        const SizedBox(height: Space.sm),
        _QuickActions(project: p, onNote: () => _editNotes(p)),
        const SizedBox(height: Space.md),
        if (access.showProjectMoney && contract != null)
          SectionCard(
            title: 'Mali durum',
            trailing: access.canEditProject
                ? TextButton(
                    onPressed: () => _editMoneyAndDates(full),
                    child: const Text('Düzenle'),
                  )
                : null,
            child: Column(
              children: [
                InfoRow(label: 'Sözleşme', child: MoneyText(contract)),
                if (extrasTotal != Money.zero)
                  InfoRow(label: 'İlave işler', child: MoneyText(extrasTotal)),
                if (access.showLedger) ...[
                  InfoRow(
                    label: 'Tahsilat',
                    child: MoneyText(
                      full.paidTotal,
                      style: TextStyle(color: x.success),
                    ),
                  ),
                  const Divider(),
                  InfoRow(
                    label: 'Kalan',
                    child: MoneyText(
                      balance!,
                      colorizeNegative: true,
                      style: context.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balance.isPositive ? x.warning : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(
                      value: (contract + extrasTotal).isPositive
                          ? (full.paidTotal.kurus /
                                    (contract + extrasTotal).kurus)
                                .clamp(0.0, 1.0)
                          : 0,
                      minHeight: 8,
                      semanticsLabel: 'Tahsilat oranı',
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (access.showProjectMoney) ...[
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'İlave işler',
            trailing: access.canEditProject
                ? TextButton.icon(
                    onPressed: _addExtra,
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  )
                : null,
            child: extras.isEmpty
                ? Text(
                    'İlave iş yok.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final e in extras)
                        ListTile(
                          minTileHeight: Sizes.minTouch,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.description),
                          subtitle: e.createdAt == null
                              ? null
                              : DateText(e.createdAt),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MoneyText(e.amount, colorizeNegative: true),
                              if (access.canEditProject)
                                IconButton(
                                  tooltip: 'İlave işi sil',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteExtra(e),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Bilgiler',
          child: Column(
            children: [
              InfoRow(label: 'Başlangıç', child: DateText(p.startDate)),
              InfoRow(
                label: 'Bitiş',
                child: DateText(p.endDate, placeholder: 'Belirlenmedi'),
              ),
              if (p.daysOverdue() != null)
                InfoRow(
                  label: 'Gecikme',
                  child: Text(
                    '${p.daysOverdue()} gün',
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              if ((p.notes ?? '').isNotEmpty)
                InfoRow(label: 'Not', value: p.notes),
            ],
          ),
        ),
        if (p.offerId != null && access.canSeeOffers) ...[
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.offer(p.offerId!)),
            icon: const Icon(Icons.request_quote_outlined),
            label: Text('${terms.offer} bilgisine git'),
          ),
        ],
        const SizedBox(height: Space.md),
        if (access.canShare) SharesSection(type: 'project', id: p.id),
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Hareketler',
          child: ActivityList(type: 'project', id: p.id),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- Görevler
  Widget _tasks(ProjectFull full, JobsAccess access) {
    final tasks = full.tasks.where((t) => !_hidden.contains(t.id)).toList();
    return Column(
      children: [
        _AddTask(
          projectId: widget.id,
          canAssign: !access.isField,
          onAdded: _reload,
        ),
        const SizedBox(height: Space.md),
        if (tasks.isEmpty)
          const EmptyState(
            icon: Icons.checklist,
            title: 'Henüz görev yok',
            message: 'Yukarıdan yeni görev ekleyin.',
          )
        else
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                for (final t in tasks)
                  ListTile(
                    minTileHeight: Sizes.minTouch + Space.sm,
                    leading: IconButton(
                      tooltip: t.isDone ? 'Bekliyor yap' : 'Tamamlandı yap',
                      icon: Icon(
                        t.isDone
                            ? Icons.check_circle
                            : t.statusEnum == TaskStatus.devamEdiyor
                            ? Icons.timelapse
                            : Icons.radio_button_unchecked,
                        color: t.isDone ? context.xc.success : null,
                      ),
                      onPressed: () => _setTask(
                        t,
                        t.isDone ? TaskStatus.bekliyor : TaskStatus.tamamlandi,
                      ),
                    ),
                    title: Text(
                      t.title,
                      style: t.isDone
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip.task(t.status),
                    ),
                    onTap: () => _taskSheet(t),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------- Ödemeler / Giderler
  String _ledgerHint(JobsAccess access) =>
      access.role == UserRole.admin || access.role == UserRole.muhasebe
      ? 'İşletme defterindeki kayıtlar gösterilir.'
      : 'Yalnızca kendi defterinizdeki kayıtlar gösterilir.';

  Widget _payments(ProjectFull full, JobsAccess access) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Tahsilat',
          trailing: FilledButton.icon(
            onPressed: () async {
              final saved = await FinanceNav.addPayment(
                context,
                projectId: widget.id,
              );
              if (saved == true && mounted) _reload();
            },
            icon: const Icon(Icons.add),
            label: const Text('Tahsilat ekle'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                label: 'Toplam tahsilat',
                child: MoneyText(
                  full.paidTotal,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _ledgerHint(access),
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        if (full.payments.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'Henüz tahsilat yok',
          )
        else
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                for (final p in full.payments)
                  ListTile(
                    minTileHeight: Sizes.minTouch + Space.sm,
                    leading: const Icon(Icons.south_west),
                    title: MoneyText(p.amount, style: context.text.titleMedium),
                    subtitle: Text(
                      [
                        p.method,
                        DateText.format(p.paidAt, DateTextMode.date),
                        if (p.note != null) p.note!,
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _expenses(ProjectFull full, JobsAccess access) {
    final terms = ref.read(brandProfileProvider).terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Gider',
          trailing: FilledButton.icon(
            onPressed: () async {
              final saved = await FinanceNav.addExpense(
                context,
                projectId: widget.id,
              );
              if (saved == true && mounted) _reload();
            },
            icon: const Icon(Icons.add),
            label: const Text('Gider ekle'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                label: 'Toplam gider',
                child: MoneyText(
                  full.expensesTotal,
                  style: context.text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _ledgerHint(access),
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        if (full.expenses.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Henüz gider yok',
          )
        else
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Column(
              children: [
                for (final e in full.expenses)
                  ListTile(
                    minTileHeight: Sizes.minTouch + Space.sm,
                    leading: const Icon(Icons.north_east),
                    title: Text(terms.expenseCategoryLabel(e.category)),
                    subtitle: Text(
                      [
                        DateText.format(e.date, DateTextMode.date),
                        if (e.note != null) e.note!,
                      ].join(' · '),
                    ),
                    trailing: MoneyText(e.amount),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Başlık: müşteri, ilerleme, aşama, iletişim
// ---------------------------------------------------------------------------

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.full,
    required this.access,
    required this.busy,
    required this.onStage,
  });
  final ProjectFull full;
  final JobsAccess access;
  final bool busy;
  final ValueChanged<ProjectStage> onStage;

  @override
  Widget build(BuildContext context) {
    final p = full.project;
    final percent = (full.progress * 100).round();
    final next = nextStageOf(p.stageEnum);
    final overdue = p.daysOverdue();
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.customerName, style: context.text.titleLarge),
          if ((p.service ?? '').isNotEmpty)
            Text(
              p.service!,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(child: Text('İlerleme', style: context.text.labelLarge)),
              Text(
                '%$percent',
                key: const ValueKey('project-progress-percent'),
                style: context.text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: full.progress,
              minHeight: 10,
              semanticsLabel: 'İlerleme yüzde $percent',
            ),
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip.stage(p.stage),
              if (overdue != null)
                StatusChip(
                  label: overdue == 0 ? 'Gecikti' : '$overdue gün gecikti',
                  tone: StatusTone.danger,
                  icon: Icons.warning_amber,
                ),
            ],
          ),
          if (access.canChangeStage) ...[
            const SizedBox(height: Space.md),
            Text('Aşama', style: context.text.labelLarge),
            const SizedBox(height: Space.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in ProjectStage.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.sm),
                      child: ChoiceChip(
                        label: Text(s.label),
                        selected: p.stageEnum == s,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: busy ? null : (_) => onStage(s),
                      ),
                    ),
                ],
              ),
            ),
            if (next != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: StageNextButton(
                  next: next,
                  expand: true,
                  onPressed: busy ? null : () => onStage(next),
                ),
              ),
          ],
          const SizedBox(height: Space.sm),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.bar, this.color);
  final TabBar bar;
  final Color color;

  @override
  double get minExtent => bar.preferredSize.height;
  @override
  double get maxExtent => bar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(color: color, child: bar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate old) =>
      old.bar != bar || old.color != color;
}

// ---------------------------------------------------------------------------
// Hızlı eylemler: Fotoğraf · Not · Belge · Konum
// ---------------------------------------------------------------------------

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.project, required this.onNote});
  final Project project;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picker = ref.read(documentPickerProvider);
    final hasLocation =
        (project.lat != null && project.lng != null) ||
        (project.address ?? '').trim().isNotEmpty;
    Widget action(IconData icon, String label, VoidCallback? onTap) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: Sizes.minTouch + Space.lg,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: onTap == null ? null : context.colors.primary,
                ),
                const SizedBox(height: Space.xs),
                Text(label, style: context.text.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Row(
          children: [
            action(
              Icons.photo_camera_outlined,
              'Fotoğraf',
              () => pickAndUploadDocument(
                context: context,
                ref: ref,
                type: 'project',
                id: project.id,
                pick: picker.takePhoto,
              ),
            ),
            action(Icons.edit_note, 'Not', onNote),
            action(
              Icons.attach_file,
              'Belge',
              () => pickAndUploadDocument(
                context: context,
                ref: ref,
                type: 'project',
                id: project.id,
                pick: picker.pickFile,
              ),
            ),
            action(
              Icons.place_outlined,
              'Konum',
              hasLocation
                  ? () async {
                      final ok = await ref
                          .read(contactLauncherProvider)
                          .directions(
                            address: project.address,
                            lat: project.lat,
                            lng: project.lng,
                          );
                      if (!ok && context.mounted) {
                        showJobsInfo(context, 'Harita uygulaması açılamadı.');
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Görev ekleme satırı
// ---------------------------------------------------------------------------

class _AddTask extends ConsumerStatefulWidget {
  const _AddTask({
    required this.projectId,
    required this.canAssign,
    required this.onAdded,
  });
  final String projectId;
  final bool canAssign;
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddTask> createState() => _AddTaskState();
}

class _AddTaskState extends ConsumerState<_AddTask> {
  final _c = TextEditingController();
  String? _assignee;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final err = ProjectValidators.taskTitle(_c.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(jobsRepositoryProvider)
          .addTask(widget.projectId, _c.text, assignedUserId: _assignee);
      _c.clear();
      widget.onAdded();
    } catch (e) {
      if (mounted) showJobsError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.canAssign
        ? ref.watch(collaboratorsProvider(widget.projectId)).value
        : null;
    return SectionCard(
      title: 'Yeni görev',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: 'Görev başlığı',
                    errorText: _error,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              SizedBox(
                width: Sizes.minTouch,
                height: Sizes.minTouch + 8,
                child: IconButton.filled(
                  tooltip: 'Görevi ekle',
                  onPressed: _busy ? null : _add,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(Icons.add),
                ),
              ),
            ],
          ),
          if (people != null && people.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            DropdownButtonFormField<String?>(
              initialValue: _assignee,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Atanan (isteğe bağlı)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Kendim'),
                ),
                for (final p in people)
                  DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) => setState(() => _assignee = v),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tutar ve tarih düzenleme sayfası
// ---------------------------------------------------------------------------

class _ProjectEditSheet extends ConsumerStatefulWidget {
  const _ProjectEditSheet({
    required this.projectId,
    required this.project,
    required this.canEditAmount,
  });
  final String projectId;
  final Project project;
  final bool canEditAmount;

  @override
  ConsumerState<_ProjectEditSheet> createState() => _ProjectEditSheetState();
}

class _ProjectEditSheetState extends ConsumerState<_ProjectEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount = TextEditingController(
    text:
        widget.project.totalAmount?.format(
          symbol: false,
          hideZeroKurus: true,
        ) ??
        '',
  );
  DateTime? _start;
  DateTime? _end;
  bool _endCleared = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.project.startDate;
    _end = widget.project.endDate;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) async {
    final w = Ist.wall(current ?? Ist.now());
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(w.year, w.month, w.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return null;
    return Ist.fromWall(d.year, d.month, d.day, 12);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(jobsRepositoryProvider);
    try {
      if (widget.canEditAmount) {
        final m = Money.parseUserInput(_amount.text) ?? Money.zero;
        if (m != widget.project.totalAmount) {
          await repo.setAmount(widget.projectId, m);
        }
      }
      final startChanged = _start != widget.project.startDate;
      final endChanged = _end != widget.project.endDate;
      if (startChanged || endChanged) {
        await repo.setDates(
          widget.projectId,
          start: startChanged ? _start : null,
          end: endChanged ? _end : null,
          clearEnd: _endCleared && _end == null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppException.from(e).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Tutar ve tarihler', style: context.text.titleMedium),
              const SizedBox(height: Space.md),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.colors.error),
                  ),
                ),
              if (widget.canEditAmount)
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Sözleşme tutarı',
                    prefixText: '₺ ',
                  ),
                  validator: ProjectValidators.amount,
                ),
              const SizedBox(height: Space.md),
              ListTile(
                minTileHeight: Sizes.minTouch,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Başlangıç'),
                subtitle: DateText(_start),
                onTap: () async {
                  final d = await _pick(_start);
                  if (d != null) setState(() => _start = d);
                },
              ),
              ListTile(
                minTileHeight: Sizes.minTouch,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Bitiş'),
                subtitle: DateText(_end, placeholder: 'Belirlenmedi'),
                trailing: _end == null
                    ? null
                    : IconButton(
                        tooltip: 'Bitişi temizle',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _end = null;
                          _endCleared = true;
                        }),
                      ),
                onTap: () async {
                  final d = await _pick(_end);
                  if (d != null) {
                    setState(() {
                      _end = d;
                      _endCleared = false;
                    });
                  }
                },
              ),
              const SizedBox(height: Space.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Silme uyarısı: bağlı kayıt sayıları (ödeme/gider yalnız çağıranın defteri; sunucu hepsini siler).
String projectDeleteWarning(ProjectFull full) {
  final parts = <String>[
    if (full.tasks.isNotEmpty) '${full.tasks.length} görev',
    if (full.extras.isNotEmpty) '${full.extras.length} ilave iş',
    if (full.payments.isNotEmpty)
      '${full.payments.length} ödeme (${full.paidTotal.format(hideZeroKurus: true)})',
    if (full.expenses.isNotEmpty)
      '${full.expenses.length} gider (${full.expensesTotal.format(hideZeroKurus: true)})',
  ];
  final list = parts.isEmpty ? 'Bağlı kayıt yok' : parts.join(', ');
  return 'Birlikte silinecekler: $list; ayrıca galeri fotoğrafları, bu projeye bağlı randevular '
      've (varsa) ortakların defterindeki ödeme/gider kayıtları. Sayılar yalnız sizin gördüğünüz kayıtlardır.';
}
