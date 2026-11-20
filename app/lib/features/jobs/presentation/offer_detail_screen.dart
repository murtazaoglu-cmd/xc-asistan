// SAHİBİ: jobs ajanı. Teklif detayı (tasarım ekran 6): müşteri, durum, kalemler, KDV'li toplam,
// gönderim (200/207/502 dürüst), WhatsApp'ta aç, projeye çevir, geçmiş.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../data/jobs_access.dart';
import '../data/jobs_logic.dart';
import '../data/jobs_models.dart';
import '../data/jobs_repository.dart';
import '../jobs_paths.dart';
import 'jobs_common.dart';
import 'jobs_lists.dart';
import 'resource_sections.dart';
import 'send_result_view.dart';

/// Kalem adedi gösterimi: 2 → "2", 1.5 → "1,5".
String qtyText(num q) {
  if (q == q.roundToDouble()) return q.toInt().toString();
  return q.toString().replaceAll('.', ',');
}

class OfferDetailScreen extends ConsumerStatefulWidget {
  const OfferDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends ConsumerState<OfferDetailScreen> {
  int _tab = 0;
  QuoteSendResult? _lastSend;
  DateTime? _lastSendAt;
  bool _busy = false;

  /// İmzalı PDF bağlantısı 10 dk geçerli: 9 dk sonra "eski" sayılır.
  static const Duration _pdfFresh = Duration(minutes: 9);

  void _reload() => ref.invalidate(offerProvider(widget.id));

  Future<void> _refresh() async {
    try {
      ref.invalidate(offerProvider(widget.id));
      await ref.read(offerProvider(widget.id).future);
    } catch (e) {
      if (mounted) showJobsError(context, e);
    }
  }

  // ------------------------------------------------------------------ gönderim
  Future<void> _send(Offer o, {bool confirm = true}) async {
    if (_busy) return;
    final terms = ref.read(brandProfileProvider).terms;
    if (confirm) {
      final hasEmail = (o.email ?? '').isNotEmpty;
      final ok = await ConfirmDialog.show(
        context,
        title: '${terms.offer} gönderilsin mi?',
        message:
            'PDF, ${o.name} kişisine WhatsApp${hasEmail ? ' ve e-posta' : ''} ile gönderilecek.'
            '${hasEmail ? '' : '\nKayıtlı e-posta adresi olmadığından yalnız WhatsApp denenir.'}',
        confirmLabel: 'Gönder',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    QuoteSendResult result;
    try {
      result = await ref.read(jobsRepositoryProvider).sendQuote(o.id);
    } catch (e) {
      final ex = AppException.from(e);
      // Ağ hatasında istek sunucuya ulaşmış olabilir: sonucu kullanıcıya DÜRÜSTÇE söyle.
      result = QuoteSendResult.failure(
        ex.isNetwork
            ? '${ex.message} Müşteriye gidip gitmediğini ${terms.offer.toLowerCase()} durumundan kontrol edin.'
            : ex.message,
        httpStatus: ex.statusCode ?? 0,
      );
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lastSend = result;
      _lastSendAt = Ist.now();
    });
    _reload(); // quote.last_send_status sunucudan taze gelsin
    final action = await showSendResultSheet(
      context,
      result,
      hasPhone: (o.phone ?? '').trim().isNotEmpty,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case SendResultAction.retry:
        await _send(o, confirm: false);
      case SendResultAction.whatsapp:
        await _openWhatsApp(o);
      case SendResultAction.openPdf:
        await _openPdf();
      case SendResultAction.copyPdf:
        final url = result.pdfUrl;
        if (url != null) {
          await ref.read(linkLauncherProvider).copy(url);
          if (mounted)
            showJobsInfo(context, 'PDF bağlantısı kopyalandı (10 dk geçerli).');
        }
    }
  }

  bool get _hasFreshPdf {
    final at = _lastSendAt;
    return _lastSend?.pdfUrl != null &&
        at != null &&
        Ist.now().difference(at) < _pdfFresh;
  }

  Future<void> _openPdf() async {
    if (!_hasFreshPdf) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('PDF bağlantısı yok'),
          content: const Text(
            'PDF, teklif gönderilirken üretilir ve bağlantısı 10 dakika geçerlidir. '
            'Güncel bir PDF bağlantısı için teklifi gönderin.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await ref
        .read(linkLauncherProvider)
        .open(Uri.parse(_lastSend!.pdfUrl!));
    if (!ok && mounted) showJobsInfo(context, 'PDF açılamadı.');
  }

  Future<void> _openWhatsApp(Offer o) async {
    final phone = (o.phone ?? '').trim();
    if (phone.isEmpty) {
      showJobsInfo(context, 'Müşterinin telefon numarası yok.');
      return;
    }
    final terms = ref.read(brandProfileProvider).terms;
    final company = ref.read(brandProfileProvider).companyName;
    bool ok;
    final serverUrl = _lastSend?.whatsappUrl;
    if (serverUrl != null && serverUrl.isNotEmpty) {
      // Sunucu bağlantısı müşterinin takip sayfasını içerir.
      ok = await ref.read(linkLauncherProvider).open(Uri.parse(serverUrl));
    } else {
      ok = await ref
          .read(contactLauncherProvider)
          .whatsapp(
            phone,
            text: quoteWhatsAppText(
              companyName: company,
              offerTerm: terms.offer,
              offer: o,
              trackingBase: ref.read(trackingBaseUrlProvider),
            ),
          );
    }
    if (!ok && mounted) showJobsInfo(context, 'WhatsApp açılamadı.');
  }

  // ------------------------------------------------------------------ diğer eylemler
  Future<void> _toProject(Offer o) async {
    if (_busy) return;
    final terms = ref.read(brandProfileProvider).terms;
    if (!o.isAccepted) {
      final amount = o.amount;
      final ok = await ConfirmDialog.show(
        context,
        title: '${dative(terms.job)} çevrilsin mi?',
        message:
            '${terms.offer} "Kabul Edildi" olur ve ${terms.job.toLowerCase()} oluşturulur'
            '${amount == null ? '' : ' (${amount.format()})'}.',
        confirmLabel: 'Çevir',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    await openOfferProject(context, ref, o);
    if (mounted) {
      setState(() => _busy = false);
      _reload();
    }
  }

  Future<void> _delete(Offer o) async {
    final terms = ref.read(brandProfileProvider).terms;
    final ok = await ConfirmDialog.show(
      context,
      title: '${terms.offer} silinsin mi?',
      message: '${o.code} · ${o.name}. Silme geri alınamaz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final repo = ref.read(jobsRepositoryProvider);
    final container = ProviderScope.containerOf(context);
    // Gerçek DELETE 8 sn geciktirilir (silme geri alınamaz).
    final pending = UndoSnackbar.deferred(
      context,
      message: '${o.code} silindi',
      onCommit: () async {
        try {
          await repo.deleteOffer(o.id);
        } catch (_) {
          // Sessiz: liste yenilenince kayıt geri görünür.
        }
        container.invalidate(offersListProvider);
      },
    );
    context.pop();
    await pending;
  }

  Future<void> _edit(Offer o) async {
    await context.push(JobsPaths.editOffer(o.id));
    if (mounted) _reload();
  }

  Future<void> _openQuoteEditor() async {
    await context.push(JobsPaths.quote(widget.id));
    if (mounted) {
      _reload();
      ref.invalidate(activityProvider((type: 'offer', id: widget.id)));
    }
  }

  void _preview(Offer o) {
    final q = o.quote;
    if (q == null) {
      showJobsInfo(
        context,
        'Önce ${ref.read(brandProfileProvider).terms.offer.toLowerCase()} hazırlayın.',
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
          child: _QuoteTable(offer: o, quote: q),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ ekran
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(offerProvider(widget.id));
    final terms = ref.watch(brandProfileProvider).terms;
    final access = ref.watch(jobsAccessProvider);
    final o = async.value;

    return AppScaffold(
      title: o == null ? terms.offer : '${terms.offer}: ${o.code}',
      showMenuButton: false,
      actions: o == null
          ? null
          : [
              PopupMenuButton<String>(
                tooltip: 'Diğer işlemler',
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      _edit(o);
                    case 'refresh':
                      _reload();
                    case 'delete':
                      _delete(o);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Bilgileri düzenle'),
                  ),
                  const PopupMenuItem(value: 'refresh', child: Text('Yenile')),
                  if (access.canDeleteOffer)
                    const PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
            ],
      body: AsyncValueView<Offer>(
        value: async,
        onRetry: _reload,
        data: (o) => PullToRefresh(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Space.lg),
            children: [
              _Header(offer: o),
              const SizedBox(height: Space.md),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  minimumSize: const Size(0, Sizes.minTouch),
                ),
                segments: [
                  const ButtonSegment(value: 0, label: Text('Genel')),
                  ButtonSegment(
                    value: 1,
                    label: Text('Kalemler (${o.quote?.items.length ?? 0})'),
                  ),
                  const ButtonSegment(value: 2, label: Text('Geçmiş')),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: Space.md),
              switch (_tab) {
                0 => _general(o, terms, access),
                1 => _items(o, terms, access),
                _ => _history(o, terms),
              },
            ],
          ),
        ),
      ),
    );
  }

  Widget _general(Offer o, Glossary terms, JobsAccess access) {
    final x = context.xc;
    final quote = o.quote;
    return Column(
      children: [
        SectionCard(
          title: 'Durum',
          child: Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (final s in OfferStatus.values)
                ChoiceChip(
                  label: Text(s.label),
                  selected: o.statusEnum == s,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => changeOfferStatus(
                    context,
                    ref,
                    o,
                    s,
                    onApplied: (_) {
                      if (mounted) _reload();
                    },
                  ),
                ),
              if (o.statusEnum == null)
                StatusChip.offer(o.status), // bilinmeyen durum ham metinle
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SectionCard(
          title: terms.offer,
          child: quote == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Henüz ${terms.offer.toLowerCase()} hazırlanmadı.',
                      style: context.text.bodyLarge,
                    ),
                    if (access.canPrepareQuote) ...[
                      const SizedBox(height: Space.md),
                      FilledButton.icon(
                        onPressed: _openQuoteEditor,
                        icon: const Icon(Icons.edit_note),
                        label: Text('${terms.offer} hazırla'),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoRow(
                      label: '${terms.offer} tutarı',
                      child: MoneyText(quote.subtotal),
                    ),
                    InfoRow(
                      label: 'KDV (%${QuoteMath.vatPercent})',
                      child: MoneyText(quote.tax),
                    ),
                    const Divider(),
                    InfoRow(
                      label: 'Toplam',
                      child: MoneyText(
                        quote.total,
                        style: context.text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    Wrap(
                      spacing: Space.md,
                      runSpacing: Space.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip.send(quote.lastSendStatus),
                        if (quote.lastSendAt != null)
                          DateText(
                            quote.lastSendAt,
                            mode: DateTextMode.relativeDateTime,
                            style: context.text.bodySmall,
                          ),
                      ],
                    ),
                    if ((quote.lastSendError ?? '').isNotEmpty &&
                        quote.sendStatus != SendStatus.gonderildi) ...[
                      const SizedBox(height: Space.sm),
                      Text(
                        quote.lastSendError!,
                        style: context.text.bodyMedium?.copyWith(
                          color: quote.sendStatus == SendStatus.basarisiz
                              ? context.colors.error
                              : x.warning,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Bilgiler',
          child: Column(
            children: [
              InfoRow(
                label: 'Oluşturma tarihi',
                child: DateText(o.createdAt, mode: DateTextMode.dateTime),
              ),
              if (o.waitingSince != null)
                InfoRow(
                  label: 'Bekleme',
                  child: Text(
                    waitingLabel(o) ?? '-',
                    style: context.text.bodyLarge?.copyWith(
                      color: isWaitingStale(o) ? x.warning : null,
                      fontWeight: isWaitingStale(o) ? FontWeight.w600 : null,
                    ),
                  ),
                ),
              if ((o.message ?? '').isNotEmpty)
                InfoRow(label: '${terms.customer} mesajı', value: o.message),
              if ((o.notes ?? '').isNotEmpty)
                InfoRow(label: 'Not', value: o.notes),
              if ((o.trackingCode ?? '').isNotEmpty)
                InfoRow(label: 'Takip kodu', value: o.trackingCode),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        _actions(o, terms, access),
        const SizedBox(height: Space.md),
        DocumentsSection(type: 'offer', id: o.id),
        const SizedBox(height: Space.md),
        if (access.canShare) SharesSection(type: 'offer', id: o.id),
      ],
    );
  }

  Widget _actions(Offer o, Glossary terms, JobsAccess access) {
    final x = context.xc;
    final hasPhone = (o.phone ?? '').trim().isNotEmpty;
    final quote = o.quote;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (access.canPrepareQuote) ...[
            FilledButton.icon(
              onPressed: quote == null || _busy ? null : () => _send(o),
              icon: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send),
              label: Text(_busy ? 'Gönderiliyor…' : 'Gönder'),
            ),
            if (quote == null)
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Text(
                  'Göndermek için önce ${terms.offer.toLowerCase()} hazırlayın.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: Space.sm),
          ],
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: x.success,
              foregroundColor: x.onSuccess,
            ),
            onPressed: hasPhone ? () => _openWhatsApp(o) : null,
            icon: const Icon(Icons.chat),
            label: const Text('WhatsApp\'ta Aç'),
          ),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlinedButton.icon(
                onPressed: () => _preview(o),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Önizle'),
              ),
              OutlinedButton.icon(
                onPressed: _openPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('PDF'),
              ),
              if (access.canPrepareQuote)
                OutlinedButton.icon(
                  onPressed: _openQuoteEditor,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Düzenle'),
                ),
            ],
          ),
          if (access.canEditProject) ...[
            const SizedBox(height: Space.sm),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _toProject(o),
              icon: const Icon(Icons.construction_outlined),
              label: Text(
                o.isAccepted ? '${terms.job} aç' : '${dative(terms.job)} Çevir',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _items(Offer o, Glossary terms, JobsAccess access) {
    final q = o.quote;
    if (q == null) {
      return SectionCard(
        child: Column(
          children: [
            const Text('Kalem yok.'),
            if (access.canPrepareQuote)
              Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: FilledButton.icon(
                  onPressed: _openQuoteEditor,
                  icon: const Icon(Icons.add),
                  label: Text('${terms.offer} hazırla'),
                ),
              ),
          ],
        ),
      );
    }
    return Column(
      children: [
        SectionCard(
          title: 'Kalemler (${q.items.length})',
          child: _QuoteTable(offer: o, quote: q),
        ),
        if (access.canPrepareQuote) ...[
          const SizedBox(height: Space.md),
          OutlinedButton.icon(
            onPressed: _openQuoteEditor,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Kalemleri düzenle'),
          ),
        ],
      ],
    );
  }

  Widget _history(Offer o, Glossary terms) {
    final q = o.quote;
    return Column(
      children: [
        SectionCard(
          title: '${terms.offer} geçmişi',
          child: Column(
            children: [
              InfoRow(
                label: 'Talep geldi',
                child: DateText(o.createdAt, mode: DateTextMode.dateTime),
              ),
              if (q?.createdAt != null)
                InfoRow(
                  label: 'Hazırlandı',
                  child: DateText(q!.createdAt, mode: DateTextMode.dateTime),
                ),
              if (q?.sentViaWhatsappAt != null)
                InfoRow(
                  label: 'WhatsApp ile gitti',
                  child: DateText(
                    q!.sentViaWhatsappAt,
                    mode: DateTextMode.dateTime,
                  ),
                ),
              if (q?.sentViaEmailAt != null)
                InfoRow(
                  label: 'E-posta ile gitti',
                  child: DateText(
                    q!.sentViaEmailAt,
                    mode: DateTextMode.dateTime,
                  ),
                ),
              if (q?.lastSendAt != null)
                InfoRow(
                  label: 'Son gönderim denemesi',
                  child: DateText(q!.lastSendAt, mode: DateTextMode.dateTime),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
        SectionCard(
          title: 'Hareketler',
          child: ActivityList(type: 'offer', id: o.id),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.offer});
  final Offer offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final sub = [
      if ((o.service ?? '').isNotEmpty) o.service!,
      if ((o.region ?? '').isNotEmpty) o.region!,
    ].join(' · ');
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                child: Text(
                  o.name.trim().isEmpty ? '?' : o.name.trim()[0].toUpperCase(),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.name, style: context.text.titleLarge),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              StatusChip.offer(o.status),
            ],
          ),
          const SizedBox(height: Space.sm),
          PhoneActions(phone: o.phone, name: o.name),
          PhoneActionButtons(phone: o.phone, name: o.name),
          if ((o.email ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: Sizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: SelectableText(o.email!)),
                ],
              ),
            ),
          AddressActions(
            address: o.address,
            lat: o.lat,
            lng: o.lng,
            showButton: true,
          ),
          if (o.photoUrls.isNotEmpty) _Photos(urls: o.photoUrls),
        ],
      ),
    );
  }
}

class _Photos extends ConsumerWidget {
  const _Photos({required this.urls});
  final List<String> urls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.md),
      child: SizedBox(
        height: 72,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
          itemBuilder: (_, i) => Semantics(
            button: true,
            label: 'Müşteri fotoğrafı ${i + 1}',
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.xs),
              onTap: () =>
                  ref.read(linkLauncherProvider).open(Uri.parse(urls[i])),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.xs),
                child: Image.network(
                  urls[i],
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 72,
                    height: 72,
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kalem tablosu + KDV'li toplam (hesap `QuoteMath`; sunucu `computeTotals` ile aynı).
class _QuoteTable extends StatelessWidget {
  const _QuoteTable({required this.offer, required this.quote});
  final Offer offer;
  final OfferQuote quote;

  @override
  Widget build(BuildContext context) {
    final t = quote.items.isEmpty
        ? QuoteTotals(quote.subtotal, quote.tax, quote.total)
        : quote.computed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in quote.items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.desc, style: context.text.bodyLarge),
                      Text(
                        '${qtyText(it.qty)} × ${it.price.format()}'
                        '${it.vatIncluded ? ' (KDV dahil)' : ' + KDV'}',
                        style: context.text.bodySmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                MoneyText(it.lineGross),
              ],
            ),
          ),
        const Divider(),
        InfoRow(label: 'Ara toplam', child: MoneyText(t.subtotal)),
        InfoRow(
          label: 'KDV (%${QuoteMath.vatPercent})',
          child: MoneyText(t.tax),
        ),
        InfoRow(
          label: 'Toplam',
          child: MoneyText(
            t.total,
            style: context.text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
