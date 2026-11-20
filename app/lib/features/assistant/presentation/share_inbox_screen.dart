// WhatsApp yazışma içe aktarma ekranı ("Paylaş" menüsü → /assistant/share).
//   1) aydınlatma / rıza  2) yükleme  3) önizleme (sahip, müşteri eşleme, grup)  4) onay  5) öneriler
// core/share servisini DİNLER: `receivedShareProvider` (AlinanPaylasim akışı); işlenince consume().
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/share/share_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../application/access.dart';
import '../application/assistant_routes_paths.dart';
import '../application/import_flow.dart';
import '../application/import_picker.dart';
import '../data/assistant_repository.dart';
import '../data/import_models.dart';
import 'widgets/assistant_ui.dart';

class ShareInboxScreen extends ConsumerStatefulWidget {
  const ShareInboxScreen({super.key, this.customerKey});

  /// Müşteri kartından açıldıysa önceden seçili müşteri.
  final String? customerKey;

  @override
  ConsumerState<ShareInboxScreen> createState() => _ShareInboxScreenState();
}

class _ShareInboxScreenState extends ConsumerState<ShareInboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePending());
  }

  /// Bekleyen paylaşımı akışa alır (soğuk açılış dahil).
  void _takePending() {
    if (!mounted) return;
    final share = ref.read(receivedShareProvider);
    if (share == null) return;
    final src = importSourceFromShare(
      text: share.text,
      files: [
        for (final f in share.files)
          (path: f.path, name: f.name, isTextOrZip: f.isText || f.isZip),
      ],
      customerKey: widget.customerKey,
    );
    ref.read(receivedShareProvider.notifier).consume();
    if (src == null) {
      toast(
        context,
        'Bu içerik desteklenmiyor. WhatsApp sohbetini .txt ya da .zip olarak dışa aktarın.',
      );
      return;
    }
    ref.read(importFlowProvider.notifier).begin(src);
  }

  Future<void> _pickFile() async {
    try {
      final src = await ref
          .read(importFilePickerProvider)
          .pick(customerKey: widget.customerKey);
      if (src != null) await ref.read(importFlowProvider.notifier).begin(src);
    } on Object catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }

  Future<void> _pasteText() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mesajı yapıştırın'),
        content: TextField(
          controller: c,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: 'Kopyaladığınız mesaj(lar)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    c.dispose();
    if (text != null && text.trim().isNotEmpty) {
      await ref
          .read(importFlowProvider.notifier)
          .begin(
            ImportSource(text: text.trim(), customerKey: widget.customerKey),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Çalışırken yeni paylaşım gelirse alınır.
    ref.listen(receivedShareProvider, (prev, next) {
      if (next != null) _takePending();
    });
    final access = ref.watch(assistantAccessProvider);
    final flow = ref.watch(importFlowProvider);
    return AppScaffold(
      title: 'Yazışma içe aktar',
      showMenuButton: false,
      body: !access.canImport
          ? const EmptyState(
              icon: Icons.lock_outline,
              title: 'Bu bölüm sizin için kapalı',
              message: 'Yazışma içe aktarma saha hesaplarında kullanılamaz.',
            )
          : switch (flow.phase) {
              ImportPhase.idle => _IdleView(
                onPick: _pickFile,
                onPaste: _pasteText,
              ),
              ImportPhase.consent ||
              ImportPhase.uploading => ConsentView(flow: flow),
              ImportPhase.preview ||
              ImportPhase.confirming => PreviewView(flow: flow),
              ImportPhase.done => ImportDoneView(flow: flow),
            },
    );
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onPick, required this.onPaste});
  final VoidCallback onPick;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        const Icon(Icons.ios_share, size: Sizes.iconXl),
        const SizedBox(height: Space.md),
        Text(
          'WhatsApp yazışmasından not ve hatırlatma çıkarın',
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.sm),
        Text(
          'Yapay zekâ kullanılmaz; yazışma yalnız kendi sunucunuzda kurallarla işlenir. '
          'Nasıl yapılır:',
          style: context.text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.lg),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in const [
                'WhatsApp\'ta müşteriyle sohbeti açın.',
                'Üç nokta > Daha fazla > Sohbeti dışa aktar > Medyasız.',
                'Paylaşım menüsünden bu uygulamayı seçin.',
                'Ya da tek bir mesajı seçip Paylaş\'a dokunun.',
              ].indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Text(
                    '${s.$1 + 1}. ${s.$2}',
                    style: context.text.bodyMedium,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.attach_file),
          label: const Text('Dosya seç (.txt / .zip)'),
        ),
        const SizedBox(height: Space.sm),
        OutlinedButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste),
          label: const Text('Kopyaladığım mesajı yapıştır'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ rıza

class ConsentView extends ConsumerWidget {
  const ConsentView({super.key, required this.flow});
  final ImportFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(importFlowProvider.notifier);
    final src = flow.source;
    final notice = flow.notice;
    final uploading = flow.phase == ImportPhase.uploading;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        if (src != null)
          SectionCard(
            child: Row(
              children: [
                Icon(
                  src.isFile ? Icons.description_outlined : Icons.chat_outlined,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    src.isFile
                        ? (src.fileName ?? 'Sohbet dosyası')
                        : 'Yapıştırılan mesaj (${src.text?.length ?? 0} karakter)',
                    style: context.text.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: Space.md),
        if (flow.noticeLoading)
          const SkeletonBox(height: 180, radius: Radii.card)
        else if (notice == null)
          Column(
            children: [
              ErrorState(
                message: flow.error ?? 'Aydınlatma metni alınamadı.',
                onRetry: n.retryNotice,
              ),
            ],
          )
        else
          SectionCard(
            title: notice.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in notice.paragraphs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(p, style: context.text.bodyMedium),
                  ),
                const SizedBox(height: Space.sm),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: flow.consentChecked,
                  onChanged: uploading
                      ? null
                      : (v) => n.toggleConsent(v ?? false),
                  title: Text(notice.checkbox),
                ),
              ],
            ),
          ),
        if (flow.error != null && notice != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                flow.error!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: (notice == null || !flow.consentChecked || uploading)
              ? null
              : n.upload,
          icon: uploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.arrow_forward),
          label: Text(uploading ? 'Yükleniyor…' : 'Devam et'),
        ),
        TextButton(
          onPressed: uploading ? null : n.reset,
          child: const Text('Vazgeç'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ önizleme

class PreviewView extends ConsumerWidget {
  const PreviewView({super.key, required this.flow});
  final ImportFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = flow.preview!;
    final n = ref.read(importFlowProvider.notifier);
    final range = p.range;
    final confirming = flow.phase == ImportPhase.confirming;
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        SectionCard(
          title: 'Önizleme',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.fileName != null)
                Text(p.fileName!, style: context.text.bodySmall),
              const SizedBox(height: Space.sm),
              Text(
                p.singleMessage
                    ? '1 mesaj'
                    : '${p.messageCount} mesaj${range.from != null && range.to != null ? ', ${Fmt.date(range.from!)} – ${Fmt.date(range.to!)}' : ''}',
                style: context.text.titleMedium,
              ),
              if (p.participants.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    'Katılımcılar: ${p.participants.join(', ')}',
                    style: context.text.bodyMedium,
                  ),
                ),
              if (p.suggestionTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(top: Space.xs),
                  child: Text(
                    '${p.suggestionTotal} öneri çıkarılacak'
                    '${p.suggestionCounts.entries.isEmpty ? '' : ' (${[for (final e in p.suggestionCounts.entries) '${e.value} ${SuggestionKind.fromApi(e.key).label.toLowerCase()}'].join(', ')})'}.',
                    style: context.text.bodyMedium,
                  ),
                ),
              if (p.first != null) _Quote(label: 'İlk mesaj', m: p.first!),
              if (p.last != null && p.messageCount > 1)
                _Quote(label: 'Son mesaj', m: p.last!),
            ],
          ),
        ),
        if (p.alreadyImported)
          _Banner(
            icon: Icons.info_outline,
            text: 'Bu yazışma daha önce alınmış. Yalnız yeni mesajlar eklenir; aynı mesajlar çoğaltılmaz.',
          ),
        for (final w in p.warnings)
          _Banner(icon: Icons.warning_amber_rounded, text: w, warn: true),
        const SectionLabel('Siz hangisisiniz?'),
        _OwnerPicker(flow: flow),
        const SectionLabel('Müşteri'),
        _CustomerPicker(flow: flow),
        if (p.isGroup) ...[
          const SizedBox(height: Space.md),
          SectionCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Grup sohbetini de al'),
              subtitle: const Text(
                'Bu bir grup sohbeti. Gruptaki diğer kişilerin mesajları da işlenir; yalnız gerekliyse açın.',
              ),
              value: flow.includeGroup,
              onChanged: confirming ? null : n.setIncludeGroup,
            ),
          ),
        ],
        if (flow.error != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.md),
            child: Semantics(
              liveRegion: true,
              child: Text(
                flow.error!,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          ),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: flow.canConfirm ? n.confirm : null,
          icon: confirming
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.check),
          label: Text(
            confirming
                ? 'Kaydediliyor…'
                : 'Yazışmayı kaydet ve önerileri çıkar',
          ),
        ),
        TextButton(
          onPressed: confirming ? null : n.cancel,
          child: const Text('Vazgeç ve sil'),
        ),
      ],
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.label, required this.m});
  final String label;
  final PreviewMessage m;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.sm),
    child: Text(
      '$label (${m.sender}${m.sentAt == null ? '' : ', ${Fmt.dateTime(m.sentAt!)}'}): “${m.text}”',
      style: context.text.bodySmall,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.md),
    child: Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: warn ? context.xc.warningContainer : context.xc.infoContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: Sizes.iconSm, color: context.colors.onSurface),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _OwnerPicker extends ConsumerWidget {
  const _OwnerPicker({required this.flow});
  final ImportFlow flow;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = flow.preview!;
    final n = ref.read(importFlowProvider.notifier);
    final confirming = flow.phase == ImportPhase.confirming;
    if (p.participants.isEmpty) {
      return TextField(
        enabled: !confirming,
        decoration: const InputDecoration(
          labelText: 'Sizin adınız (mesajdaki gönderen adı)',
        ),
        onChanged: n.setOwner,
      );
    }
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final name in p.participants)
          ChoiceChip(
            label: Text(name),
            selected: flow.owner == name,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: confirming ? null : (_) => n.setOwner(name),
          ),
      ],
    );
  }
}

/// Müşteri eşleme: sunucu eşleştirdiyse onay, eşleştiremediyse sihirbaz (ara / aday seç / bağlama).
class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker({required this.flow});
  final ImportFlow flow;
  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  bool _changing = false;
  final _q = TextEditingController();
  Timer? _debounce;
  List<CustomerHit> _hits = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(v.trim()),
    );
  }

  Future<void> _search(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final r = await ref.read(assistantRepositoryProvider).searchCustomers(q);
      if (mounted) setState(() => _hits = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.flow;
    final p = flow.preview!;
    final n = ref.read(importFlowProvider.notifier);
    final wizard = flow.needsCustomerMatch || _changing;
    if (!wizard) {
      return SectionCard(
        child: Row(
          children: [
            Icon(
              flow.mode == CustomerMode.none
                  ? Icons.link_off
                  : Icons.person_outline,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                flow.customerLabel ?? 'Müşteriye bağlanmayacak',
                style: context.text.bodyLarge,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _changing = true),
              child: const Text('Değiştir'),
            ),
          ],
        ),
      );
    }
    return SectionCard(
      title: flow.needsCustomerMatch
          ? 'Müşteriyi eşleştirelim'
          : 'Müşteriyi seçin',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (flow.needsCustomerMatch)
            Text(
              'Sohbet bir müşteriyle otomatik eşleşmedi. Aşağıdan arayın ya da müşteriye bağlamadan devam edin.',
              style: context.text.bodySmall,
            ),
          if (p.candidates.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final c in p.candidates)
                  ActionChip(
                    avatar: const Icon(Icons.person_outline, size: 18),
                    label: Text(c.name),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onPressed: () {
                      n.pickCustomer(
                        CustomerHit(key: c.key, name: c.name, phone: c.phone),
                      );
                      setState(() => _changing = false);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: Space.sm),
          TextField(
            controller: _q,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              labelText: 'Müşteri ara (ad ya da telefon)',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (_searching)
            const Padding(
              padding: EdgeInsets.only(top: Space.sm),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Text(
                _error!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
          for (final h in _hits)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: Sizes.minTouch,
              leading: const Icon(Icons.person_outline),
              title: Text(h.name),
              subtitle: h.phone == null ? null : Text(h.phone!),
              onTap: () {
                n.pickCustomer(h);
                setState(() => _changing = false);
              },
            ),
          const SizedBox(height: Space.sm),
          TextButton.icon(
            onPressed: () {
              n.noCustomer();
              setState(() => _changing = false);
            },
            icon: const Icon(Icons.link_off),
            label: const Text('Müşteriye bağlama'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ sonuç

class ImportDoneView extends ConsumerWidget {
  const ImportDoneView({super.key, required this.flow});
  final ImportFlow flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = flow.result!;
    final n = ref.read(importFlowProvider.notifier);
    return ListView(
      padding: const EdgeInsets.all(Space.lg),
      children: [
        Icon(Icons.check_circle, size: Sizes.iconXl, color: context.xc.success),
        const SizedBox(height: Space.md),
        Text(
          r.already ? 'Bu yazışma zaten kayıtlıydı' : 'Yazışma kaydedildi',
          style: context.text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.sm),
        Text(
          r.already
              ? 'Yeni bir mesaj eklenmedi.'
              : '${r.inserted} mesaj eklendi'
                    '${r.duplicates > 0 ? ', ${r.duplicates} tekrar atlandı' : ''}. '
                    '${r.suggestionsCreated} öneri hazır.',
          style: context.text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.xl),
        if (r.suggestionsCreated > 0 || r.already)
          FilledButton.icon(
            onPressed: () {
              final route = AssistantPaths.suggestionsFor(
                conversationId: r.conversationId,
                customerKey: r.conversationId == null ? flow.picked?.key : null,
              );
              n.reset();
              context.pushReplacement(route);
            },
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Önerilere bak'),
          ),
        TextButton(
          onPressed: () {
            n.reset();
            context.go(AssistantPaths.root);
          },
          child: const Text('Bitti'),
        ),
      ],
    );
  }
}
