// KDV sekmesi: dönem kartı (hesaplanan / indirilecek / devreden / ödenecek), dönem değiştirici,
// dönem kilitleme (onaylı), "Mali müşavire gönder" (CSV/XLSX + sistem paylaş menüsü + özet metni).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import '../data/invoices_vat_services.dart';
import '../data/vat_summary_text.dart';
import 'inv_widgets.dart';

class VatTab extends ConsumerWidget {
  const VatTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sel = ref.watch(vatSelectionProvider);
    final n = ref.read(vatSelectionProvider.notifier);
    final async = ref.watch(vatPeriodProvider(sel.key));
    final access = ref.watch(invoicesVatAccessProvider);

    final bar = Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
      child: Column(
        children: [
          PeriodBar(
            label: sel.label,
            onPrevious: () => n.step(-1),
            onNext: () => n.step(1),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: Space.sm,
              children: [
                ChoiceChip(
                  key: const Key('vat_monthly'),
                  label: const Text('Aylık'),
                  selected: !sel.quarterly,
                  onSelected: (_) => n.setQuarterly(false),
                ),
                ChoiceChip(
                  key: const Key('vat_quarterly'),
                  label: const Text('3 aylık'),
                  selected: sel.quarterly,
                  onSelected: (_) => n.setQuarterly(true),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return PullToRefresh(
      onRefresh: () async {
        ref.invalidate(vatPeriodProvider);
        try {
          await ref.read(vatPeriodProvider(sel.key).future);
        } catch (_) {}
      },
      child: async.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            bar,
            const Padding(
              padding: EdgeInsets.all(Space.lg),
              child: SkeletonBox(height: 220, radius: Radii.card),
            ),
          ],
        ),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            bar,
            SizedBox(
              height: 320,
              child: ErrorState(
                error: e,
                onRetry: () => ref.invalidate(vatPeriodProvider(sel.key)),
              ),
            ),
          ],
        ),
        data: (p) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            bar,
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                0,
              ),
              child: _PeriodBody(
                period: p,
                selection: sel,
                canLock: access?.canLockPeriod ?? false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBody extends ConsumerStatefulWidget {
  const _PeriodBody({
    required this.period,
    required this.selection,
    required this.canLock,
  });
  final VatPeriod period;
  final VatSelection selection;
  final bool canLock;

  @override
  ConsumerState<_PeriodBody> createState() => _PeriodBodyState();
}

class _PeriodBodyState extends ConsumerState<_PeriodBody> {
  bool _busy = false;
  VatPeriod get p => widget.period;

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _run(Future<void> Function() job, InvoicesVatOp op) async {
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(vatPeriodProvider);
    } catch (e) {
      _snack(InvoicesVatErrors.message(e, op));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLock() async {
    final repo = ref.read(invoicesVatRepositoryProvider);
    final lock = !p.locked;
    final go = await ConfirmDialog.show(
      context,
      title: lock ? 'Dönem kilitlensin mi?' : 'Dönemin kilidi açılsın mı?',
      message: lock
          ? '${widget.selection.label} kilitlenince bu dönemi etkileyen fatura değişiklikleri yapılamaz. '
                'Beyanı mali müşavirinizle kontrol ettikten sonra kilitleyin.'
          : 'Kilit açılınca bu dönemdeki faturalar yeniden değiştirilebilir ve tutarlar değişebilir.',
      confirmLabel: lock ? 'Kilitle' : 'Kilidi aç',
      destructive: !lock,
    );
    if (!go) return;
    await _run(
      () => lock ? repo.lockVatPeriod(p.key) : repo.unlockVatPeriod(p.key),
      InvoicesVatOp.lock,
    );
  }

  Future<void> _recalc() => _run(() async {
    await ref.read(invoicesVatRepositoryProvider).calculateVatPeriod(p.key);
  }, InvoicesVatOp.load);

  Future<void> _editCarry() async {
    final c = TextEditingController(
      text: p.oncekiDevreden.toApiString().replaceAll('.', ','),
    );
    final form = GlobalKey<FormState>();
    final result = await showDialog<Money>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Önceki dönemden devreden'),
        content: Form(
          key: form,
          child: MoneyField(
            controller: c,
            label: 'Devreden KDV',
            validator: (m) =>
                (m == null || m.isNegative) ? 'Geçerli bir tutar girin.' : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(Money.parseUserInput(c.text));
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    c.dispose();
    if (result == null) return;
    await _run(() async {
      await ref
          .read(invoicesVatRepositoryProvider)
          .updateVatPeriod(p.key, manualCarryIn: result);
    }, InvoicesVatOp.save);
  }

  @override
  Widget build(BuildContext context) {
    final due = p.dueDate;
    final days = due == null ? null : Ist.dayDiff(Ist.now(), due);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) const LinearProgressIndicator(),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (p.estimated)
              const StatusChip(
                label: 'Tahmini',
                tone: StatusTone.neutral,
                icon: Icons.calculate_outlined,
              ),
            if (p.locked)
              const StatusChip(
                label: 'Kilitli',
                tone: StatusTone.info,
                icon: Icons.lock_outline,
              ),
            ConfirmBadge(p.confirmation),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: MetricBox(
                label: 'Hesaplanan KDV',
                value: p.hesaplanan.format(),
                hint: 'Satışlardan',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: MetricBox(
                label: 'İndirilecek KDV',
                value: p.indirilecek.format(),
                hint: 'Alımlardan',
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            Expanded(
              child: MetricBox(
                label: 'Devreden KDV',
                value: p.devreden.format(),
                hint: 'Sonraki döneme',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: MetricBox(
                key: const Key('vat_odenecek'),
                label: 'Ödenecek KDV',
                value: p.odenecek.format(),
                hint: 'Tahmini',
                color: p.odenecek.isPositive ? context.colors.primary : null,
              ),
            ),
          ],
        ),
        if (due != null) ...[
          const SizedBox(height: Space.md),
          _DueCard(due: due, days: days!),
        ],
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Dönem ayrıntısı',
          child: Column(
            children: [
              KeyValueRow('Belge sayısı', '${p.documentCount}'),
              KeyValueRow(
                'Önceki dönemden devreden',
                p.oncekiDevreden.format(),
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.oncekiDevreden.format()),
                    if (widget.canLock && !p.locked)
                      IconButton(
                        key: const Key('edit_carry'),
                        tooltip: 'Devredeni düzelt',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _busy ? null : _editCarry,
                      ),
                  ],
                ),
              ),
              if (!p.hesaplananToplam.isZero && !p.tevkifatGiden.isZero) ...[
                KeyValueRow(
                  'Hesaplanan (tevkifat öncesi)',
                  p.hesaplananToplam.format(),
                ),
                KeyValueRow('Giden tevkifat', '−${p.tevkifatGiden.format()}'),
              ],
              if (!p.indirilemeyen.isZero)
                KeyValueRow('İndirilemeyen KDV', p.indirilemeyen.format()),
              if (!p.kdv2.isZero)
                KeyValueRow('KDV-2 (tevkifat)', p.kdv2.format()),
              KeyValueRow('Net', p.net.format(), bold: true),
            ],
          ),
        ),
        if (p.breakdown.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Oran kırılımı (giden)',
            child: Column(
              children: [
                for (final r in p.breakdown)
                  KeyValueRow(
                    '%${formatPercent(r.percent)} · matrah ${r.matrah.format()}',
                    'KDV ${r.kdv.format()}',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.md),
        const DisclaimerNote(defaultDisclaimer),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          key: const Key('send_accountant'),
          onPressed: _busy
              ? null
              : () => showAccountantSheet(context, p, widget.selection),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Mali müşavire gönder'),
        ),
        const SizedBox(height: Space.sm),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            OutlinedButton.icon(
              key: const Key('recalc'),
              onPressed: _busy ? null : _recalc,
              icon: const Icon(Icons.refresh),
              label: const Text('Yeniden hesapla'),
            ),
            if (widget.canLock)
              OutlinedButton.icon(
                key: const Key('toggle_lock'),
                onPressed: _busy ? null : _toggleLock,
                icon: Icon(p.locked ? Icons.lock_open : Icons.lock_outline),
                label: Text(p.locked ? 'Kilidi aç' : 'Dönemi kilitle'),
              ),
          ],
        ),
      ],
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({required this.due, required this.days});
  final DateTime due;
  final int days;

  @override
  Widget build(BuildContext context) {
    final urgent = days <= 3;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: context.xc.aiContainer,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_outlined, color: context.xc.onAiContainer),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'KDV beyan ve ödeme',
                  style: context.text.titleMedium?.copyWith(
                    color: context.xc.onAiContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            'Son tarih: ${DateText.format(due, DateTextMode.date)}',
            style: context.text.titleSmall?.copyWith(
              color: context.xc.onAiContainer,
            ),
          ),
          Text(
            '${countdownText(days)}. Belgeleri muhasebecinle kontrol etmeyi unutma.',
            key: const Key('vat_due_text'),
            style: context.text.bodyMedium?.copyWith(
              color: context.xc.onAiContainer,
              fontWeight: urgent ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================ Mali müşavire gönder

Future<void> showAccountantSheet(
  BuildContext context,
  VatPeriod p,
  VatSelection sel,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AccountantSheet(period: p, selection: sel),
  );
}

class AccountantSheet extends ConsumerStatefulWidget {
  const AccountantSheet({
    super.key,
    required this.period,
    required this.selection,
  });
  final VatPeriod period;
  final VatSelection selection;

  @override
  ConsumerState<AccountantSheet> createState() => _AccountantSheetState();
}

class _AccountantSheetState extends ConsumerState<AccountantSheet> {
  String? _busyKey;
  String? _message;
  bool _includeAll = false;

  Future<void> _export(String key, Future<ExportFile> Function() fetch) async {
    setState(() {
      _busyKey = key;
      _message = null;
    });
    try {
      final f = await fetch();
      final d = await ref.read(exportSharerProvider).deliver(f);
      if (!mounted) return;
      setState(() {
        _busyKey = null;
        _message = d.shared
            ? '${f.filename} paylaşım menüsüne gönderildi.'
            : '${f.filename} kaydedildi: ${d.path}'
                  '${f.needsConfirmation ? '\nDosyada teyit gerektiren belgeler var.' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busyKey = null;
        _message = e is UnsupportedError
            ? 'Bu cihazda dosya kaydedilemiyor.'
            : InvoicesVatErrors.message(e, InvoicesVatOp.export);
      });
    }
  }

  String get _summary => VatSummaryText.build(
    widget.period,
    companyName: context.brand.companyName,
    label: widget.selection.label,
  );

  Future<void> _shareText(Uri Function(String text) build) async {
    final ok = await ref.read(linkLauncherProvider).open(build(_summary));
    if (!ok && mounted)
      setState(
        () => _message = 'Uygulama açılamadı. Metni kopyalayabilirsiniz.',
      );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(invoicesVatRepositoryProvider);
    final key = widget.selection.key;
    Widget tile(
      String id,
      IconData icon,
      String title,
      String sub,
      Future<ExportFile> Function() fetch,
    ) => ListTile(
      key: Key('export_$id'),
      minVerticalPadding: Space.md,
      leading: _busyKey == id
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(icon),
      title: Text(title),
      subtitle: Text(sub),
      enabled: _busyKey == null,
      onTap: () => _export(id, fetch),
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text('Mali müşavire gönder', style: context.text.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              Space.xs,
              Space.lg,
              Space.sm,
            ),
            child: Text(
              '${widget.selection.label}. Dosya indirilir; ardından paylaşabilirsiniz.',
              style: context.text.bodyMedium,
            ),
          ),
          SwitchListTile(
            title: const Text('Taslak ve iptal belgeleri de ekle'),
            value: _includeAll,
            onChanged: _busyKey == null
                ? (v) => setState(() => _includeAll = v)
                : null,
          ),
          tile(
            'inv_csv',
            Icons.table_chart_outlined,
            'Fatura listesi (CSV)',
            'Muhasebe programları için; Excel\'de açılır',
            () => repo.exportInvoices(
              period: key,
              format: 'csv',
              includeAll: _includeAll,
            ),
          ),
          tile(
            'inv_xlsx',
            Icons.grid_on,
            'Fatura listesi (XLSX)',
            'Excel çalışma kitabı',
            () => repo.exportInvoices(
              period: key,
              format: 'xlsx',
              includeAll: _includeAll,
            ),
          ),
          tile(
            'vat_csv',
            Icons.summarize_outlined,
            'KDV dönem özeti (CSV)',
            'Hesaplanan, indirilecek, ödenecek',
            () => repo.exportVatPeriod(key, format: 'csv'),
          ),
          tile(
            'vat_xlsx',
            Icons.summarize,
            'KDV dönem özeti (XLSX)',
            'Excel çalışma kitabı',
            () => repo.exportVatPeriod(key, format: 'xlsx'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              'KDV özetini metin olarak paylaş',
              style: context.text.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: context.colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Text(
                _summary,
                key: const Key('vat_summary_text'),
                style: context.text.bodySmall,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                OutlinedButton.icon(
                  key: const Key('share_whatsapp'),
                  onPressed: () =>
                      _shareText((t) => Uri.https('wa.me', '/', {'text': t})),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('WhatsApp'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _shareText(
                    (t) => Uri(
                      scheme: 'mailto',
                      query:
                          'subject=${Uri.encodeComponent('KDV özeti ${widget.selection.label}')}&body=${Uri.encodeComponent(t)}',
                    ),
                  ),
                  icon: const Icon(Icons.mail_outline),
                  label: const Text('E-posta'),
                ),
                OutlinedButton.icon(
                  key: const Key('copy_summary'),
                  onPressed: () async {
                    await ref.read(linkLauncherProvider).copy(_summary);
                    if (mounted) setState(() => _message = 'Özet kopyalandı.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Kopyala'),
                ),
              ],
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  key: const Key('export_message'),
                  style: context.text.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
