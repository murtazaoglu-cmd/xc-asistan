// Fatura ayrıntısı: tutarlar, ekler (kamera/dosya, güvenli URL ile görüntüleme), "Ödendi işaretle",
// WhatsApp hatırlatma, düzenle/sil. Ekler 10 dk geçerli İMZALI URL ile açılır: her açılışta fatura
// yeniden çekilir, URL saklanmaz/paylaşılmaz.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../data/invoices_vat_errors.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';
import '../data/invoices_vat_repository.dart';
import '../data/invoices_vat_services.dart';
import 'inv_widgets.dart';
import 'invoices_actions.dart';

class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(invoiceDetailProvider(invoiceId));
    return AppScaffold(
      title: 'Fatura',
      showMenuButton: false,
      body: AsyncValueView<Invoice>(
        value: async,
        onRetry: () => ref.invalidate(invoiceDetailProvider(invoiceId)),
        data: (i) => _Body(invoice: i),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  Invoice get i => widget.invoice;

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _refresh() async {
    invalidateInvoicesVatW(ref);
  }

  Future<void> _markPaid() async {
    final repo = ref.read(invoicesVatRepositoryProvider);
    final ok = await showMarkPaidSheet(
      context,
      title: i.title,
      amount: i.odenecek,
      canCreatePayment:
          i.direction == InvoiceDirection.giden && i.projectId != null,
      onConfirm: (date, method, createPayment) async {
        final r = await repo.markInvoicePaid(
          i.id,
          paidAt: date,
          method: method,
          createPayment: createPayment,
        );
        if (r.scheduleItemsClosed > 0 && mounted) {
          _snack('${r.scheduleItemsClosed} plan satırı da kapandı.');
        }
      },
    );
    if (ok) {
      await _refresh();
      if (mounted) _snack('Ödendi olarak işaretlendi.');
    }
  }

  Future<void> _delete() async {
    final go = await ConfirmDialog.show(
      context,
      title: 'Fatura silinsin mi?',
      message: 'Bu işlem geri alınamaz.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!go || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(invoicesVatRepositoryProvider).deleteInvoice(i.id);
      invalidateInvoicesVatW(ref);
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(InvoicesVatErrors.message(e, InvoicesVatOp.delete));
    }
  }

  Future<void> _addFile(
    Future<PickedAttachment?> Function(AttachmentPicker) pick,
  ) async {
    if (i.files.length >= attachmentMaxCount) {
      _snack('En çok $attachmentMaxCount dosya eklenebilir.');
      return;
    }
    PickedAttachment? a;
    try {
      a = await pick(ref.read(attachmentPickerProvider));
    } catch (_) {
      _snack('Dosya seçilemedi. İzinleri kontrol edin.');
      return;
    }
    if (a == null) return;
    if (!isAllowedAttachmentName(a.name)) {
      _snack('Bu dosya türü eklenemez (PDF ya da fotoğraf seçin).');
      return;
    }
    final size = await attachmentSizeOf(a.path);
    if (size != null && size > attachmentMaxBytes) {
      _snack('Dosya çok büyük (en çok 15 MB).');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(invoicesVatRepositoryProvider)
          .uploadInvoiceFile(i.id, a.path, fileName: a.name);
      await _refresh();
      _snack('Ek yüklendi.');
    } catch (e) {
      _snack(InvoicesVatErrors.message(e, InvoicesVatOp.upload));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// İmzalı URL kısa ömürlüdür: açmadan hemen önce faturayı yeniden çek.
  Future<void> _openFile(InvoiceFile f) async {
    setState(() => _busy = true);
    try {
      final fresh = await ref.read(invoicesVatRepositoryProvider).invoice(i.id);
      final url = fresh.files.where((x) => x.id == f.id).firstOrNull?.url;
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https') {
        _snack('Dosya bağlantısı alınamadı. Yenileyip tekrar deneyin.');
        return;
      }
      final ok = await ref.read(linkLauncherProvider).open(uri);
      if (!ok) _snack('Dosya açılamadı.');
    } catch (e) {
      _snack(InvoicesVatErrors.message(e, InvoicesVatOp.upload));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFile(InvoiceFile f) async {
    final go = await ConfirmDialog.show(
      context,
      title: 'Ek silinsin mi?',
      message: f.name,
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!go) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(invoicesVatRepositoryProvider)
          .deleteInvoiceFile(i.id, f.id);
      await _refresh();
    } catch (e) {
      _snack(InvoicesVatErrors.message(e, InvoicesVatOp.delete));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final giden = i.direction == InvoiceDirection.giden;
    return PullToRefresh(
      onRefresh: () async => ref.invalidate(invoiceDetailProvider(i.id)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Space.lg),
        children: [
          if (_busy) const LinearProgressIndicator(),
          Text(i.title, style: context.text.titleLarge),
          const SizedBox(height: Space.xs),
          Text(
            '${giden ? 'Giden' : 'Gelen'} · ${i.typeLabel}',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              invoiceStatusChip(i),
              if (i.overdue)
                const StatusChip(
                  label: 'Vadesi geçti',
                  tone: StatusTone.danger,
                  icon: Icons.warning_amber,
                ),
              ConfirmBadge(i.confirmation),
            ],
          ),
          const SizedBox(height: Space.lg),
          SectionCard(
            title: 'Tutarlar',
            child: Column(
              children: [
                KeyValueRow('Matrah (KDV hariç)', i.matrah.format()),
                KeyValueRow(
                  i.kdvOran == null
                      ? 'KDV'
                      : 'KDV (%${formatPercent(i.kdvOran!)})',
                  i.kdv.format(),
                ),
                if (!i.tevkifat.isZero)
                  KeyValueRow(
                    i.withholding == null
                        ? 'Tevkifat'
                        : 'Tevkifat (${i.withholding!.label})',
                    '−${i.tevkifat.format()}',
                  ),
                KeyValueRow('Genel toplam', i.tutar.format(), bold: true),
                if (!i.tevkifat.isZero)
                  KeyValueRow('Ödenecek', i.odenecek.format(), bold: true),
                if (i.direction == InvoiceDirection.gelen)
                  KeyValueRow(
                    'KDV indirilebilir',
                    i.kdvDeductible ? 'Evet' : 'Hayır',
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          SectionCard(
            title: 'Belge bilgileri',
            child: Column(
              children: [
                KeyValueRow(
                  'Fatura tarihi',
                  DateText.format(i.issueDate, DateTextMode.date),
                ),
                KeyValueRow(
                  'Vade',
                  DateText.format(i.dueDate, DateTextMode.date),
                ),
                if (i.isPaid)
                  KeyValueRow(
                    'Ödeme tarihi',
                    DateText.format(i.paidAt, DateTextMode.date),
                  ),
                KeyValueRow('Karşı taraf', i.counterparty),
                if (i.counterpartyTaxId != null)
                  KeyValueRow('VKN / TCKN', i.counterpartyTaxId),
                if (i.ettn != null) KeyValueRow('ETTN', i.ettn),
                if (i.projectCode != null || i.projectId != null)
                  KeyValueRow('Proje', i.projectCode ?? 'Bağlı proje'),
                if (i.customerName != null)
                  KeyValueRow('Müşteri', i.customerName),
                if (i.period != null) KeyValueRow('KDV dönemi', i.period),
                if (i.note != null) KeyValueRow('Not', i.note),
              ],
            ),
          ),
          if (i.warnings.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            for (final w in i.warnings) DisclaimerNote(w.message),
          ],
          const SizedBox(height: Space.md),
          _Attachments(
            invoice: i,
            onCamera: () => _addFile((p) => p.takePhoto()),
            onGallery: () => _addFile((p) => p.pickPhoto()),
            onFile: () => _addFile((p) => p.pickFile()),
            onOpen: _openFile,
            onDelete: _deleteFile,
          ),
          const SizedBox(height: Space.lg),
          if (i.canMarkPaid)
            FilledButton.icon(
              key: const Key('mark_paid'),
              onPressed: _busy ? null : _markPaid,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Ödendi işaretle'),
            ),
          if (giden && i.canMarkPaid) ...[
            const SizedBox(height: Space.sm),
            OutlinedButton.icon(
              key: const Key('remind_invoice'),
              onPressed: () => showReminderSheet(
                context,
                invoiceId: i.id,
                name: i.counterparty,
                daysOverdue: i.overdue && i.dueDate != null
                    ? _daysOverdue()
                    : 0,
              ),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp\'ta hatırlat'),
            ),
          ],
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            key: const Key('edit_invoice'),
            onPressed: _busy
                ? null
                : () => context.push('${Routes.invoicesVat}/${i.id}/edit'),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Düzenle'),
          ),
          if (i.status?.deletable ?? false) ...[
            const SizedBox(height: Space.sm),
            TextButton.icon(
              key: const Key('delete_invoice'),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
              onPressed: _busy ? null : _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Sil'),
            ),
          ],
          const SizedBox(height: Space.xl),
        ],
      ),
    );
  }

  int _daysOverdue() {
    final d = -Ist.dayDiff(Ist.now(), i.dueDate!);
    return d < 0 ? 0 : d;
  }
}

class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.invoice,
    required this.onCamera,
    required this.onGallery,
    required this.onFile,
    required this.onOpen,
    required this.onDelete,
  });
  final Invoice invoice;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onFile;
  final ValueChanged<InvoiceFile> onOpen;
  final ValueChanged<InvoiceFile> onDelete;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Ekler (${invoice.files.length}/$attachmentMaxCount)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (invoice.files.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Text(
                'Henüz ek yok. Fatura fotoğrafını ya da PDF\'ini ekleyin.',
                style: context.text.bodyMedium,
              ),
            ),
          for (final f in invoice.files)
            ListTile(
              key: Key('file_${f.id}'),
              contentPadding: EdgeInsets.zero,
              minVerticalPadding: Space.sm,
              leading: Icon(
                f.isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              ),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Görüntülemek için dokunun'),
              onTap: () => onOpen(f),
              trailing: IconButton(
                tooltip: 'Eki sil',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(f),
              ),
            ),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              OutlinedButton.icon(
                key: const Key('add_photo'),
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Fotoğraf çek'),
              ),
              OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeri'),
              ),
              OutlinedButton.icon(
                onPressed: onFile,
                icon: const Icon(Icons.attach_file),
                label: const Text('Dosya'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
