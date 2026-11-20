// Fatura/KDV modülünün ortak küçük widget'ları: teyit rozeti, tarih/tutar alanları, seçiciler.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_input.dart';
import '../data/invoices_vat_models.dart';
import '../data/invoices_vat_providers.dart';

/// Doğrulanmamış oran/tarih/tevkifat için "Mali müşavire teyit edin" rozeti.
/// Dokununca nedenler gösterilir. [confirmation].needed false ise hiçbir şey çizmez.
class ConfirmBadge extends StatelessWidget {
  const ConfirmBadge(this.confirmation, {super.key, this.compact = false});
  final Confirmation confirmation;

  /// Dar alanda yalnız ikon + kısa metin.
  final bool compact;

  static const String label = 'Mali müşavire teyit edin';

  @override
  Widget build(BuildContext context) {
    if (!confirmation.needed) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        key: const Key('confirm_badge'),
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: () => showConfirmReasons(context, confirmation),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch),
          child: Center(
            widthFactor: 1,
            child: StatusChip(
              label: compact ? 'Teyit edin' : label,
              tone: StatusTone.warning,
              icon: Icons.fact_check_outlined,
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showConfirmReasons(BuildContext context, Confirmation c) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.fact_check_outlined, color: ctx.xc.warning),
      title: const Text(ConfirmBadge.label),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Bu bilgi doğrulanmamıştır. Uygulama fatura kesmez ve hukuki/mali tavsiye vermez; '
              'beyan öncesi mali müşavirinize danışın.',
            ),
            if (c.reasons.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              for (final r in c.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(child: Text(r)),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );
}

/// Yasal not şeridi (bilgilendirme, tavsiye değil).
class DisclaimerNote extends StatelessWidget {
  const DisclaimerNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.xc.warningContainer,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: Sizes.iconSm,
            color: context.xc.onWarning,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.bodySmall?.copyWith(
                color: context.xc.onWarning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const String defaultDisclaimer =
    'Uygulama fatura KESMEZ, takip eder. KDV ve tarihler tahminidir; hukuki/mali tavsiye değildir. '
    'Beyan öncesi mali müşavirinize teyit edin.';

/// Dönem çubuğu: ‹ Kasım 2026 ›
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.label,
    required this.onPrevious,
    required this.onNext,
    this.trailing,
  });
  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Önceki dönem',
          constraints: const BoxConstraints(
            minWidth: Sizes.minTouch,
            minHeight: Sizes.minTouch,
          ),
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: context.text.titleMedium,
            key: const Key('period_label'),
          ),
        ),
        IconButton(
          tooltip: 'Sonraki dönem',
          constraints: const BoxConstraints(
            minWidth: Sizes.minTouch,
            minHeight: Sizes.minTouch,
          ),
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
        ?trailing,
      ],
    );
  }
}

/// Tarih alanı: değer `YYYY-AA-GG` metni; dokununca tarih seçici.
class DayField extends StatelessWidget {
  const DayField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.errorText,
    this.firstYear = 2015,
    this.lastYear = 2100,
  });
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allowClear;
  final String? errorText;
  final int firstYear;
  final int lastYear;

  @override
  Widget build(BuildContext context) {
    final d = parseDay(value);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () async {
        final w = Ist.wall(d ?? Ist.now());
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime(w.year, w.month, w.day),
          firstDate: DateTime(firstYear),
          lastDate: DateTime(lastYear, 12, 31),
          helpText: label,
        );
        if (picked != null) onChanged(pickedKey(picked));
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            suffixIcon: allowClear && value != null
                ? IconButton(
                    tooltip: 'Temizle',
                    icon: const Icon(Icons.close),
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(d == null ? 'Seçin' : Fmt.date(d)),
        ),
      ),
    );
  }

  static String pickedKey(DateTime picked) =>
      '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
}

/// Tutar alanı: Türkçe giriş ("12.500,50"), yalnız rakam/virgül/nokta.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.onChanged,
    this.validator,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
  });
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final String? Function(Money?)? validator;
  final bool autofocus;
  final TextInputAction textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, prefixText: '₺ '),
      validator: (v) =>
          (validator ?? InvoiceRules.amount)(Money.parseUserInput(v ?? '')),
    );
  }
}

/// Başlıklı satır: sol etiket, sağ değer.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow(
    this.label,
    this.value, {
    super.key,
    this.bold = false,
    this.valueWidget,
  });
  final String label;
  final String? value;
  final bool bold;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    final style = bold ? context.text.titleSmall : context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: style?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            flex: 5,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  valueWidget ??
                  Text(value ?? '-', style: style, textAlign: TextAlign.right),
            ),
          ),
        ],
      ),
    );
  }
}

/// Metrik kutusu (KDV dönem kartı): uzun tutarda küçülür, taşmaz.
class MetricBox extends StatelessWidget {
  const MetricBox({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.color,
  });
  final String label;
  final String value;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTouch + 24),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: context.text.bodySmall, maxLines: 2),
            const SizedBox(height: Space.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: context.text.titleLarge?.copyWith(color: color),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fatura durumu rozeti.
StatusChip invoiceStatusChip(Invoice i) {
  switch (i.status) {
    case InvoiceStatus.taslak:
      return const StatusChip(label: 'Taslak', icon: Icons.edit_note);
    case InvoiceStatus.kesildi:
      return const StatusChip(
        label: 'Kesildi',
        tone: StatusTone.info,
        icon: Icons.receipt_long_outlined,
      );
    case InvoiceStatus.gonderildi:
      return const StatusChip(
        label: 'Gönderildi',
        tone: StatusTone.info,
        icon: Icons.send_outlined,
      );
    case InvoiceStatus.odendi:
      return const StatusChip(
        label: 'Ödendi',
        tone: StatusTone.success,
        icon: Icons.check_circle_outline,
      );
    case InvoiceStatus.iptal:
      return const StatusChip(
        label: 'İptal',
        tone: StatusTone.danger,
        icon: Icons.block,
      );
    case null:
      return StatusChip(label: i.statusRaw.isEmpty ? '-' : i.statusRaw);
  }
}

// ---------------------------------------------------------------- Seçici (proje)

/// Bağlı proje/müşteri seçici alanı. Seçim `RefItem` (id + görünen ad); ham UUID gösterilmez.
class RefPickerField extends StatelessWidget {
  const RefPickerField({
    super.key,
    required this.label,
    required this.kind,
    required this.selectedLabel,
    required this.onChanged,
    this.hasValue = false,
  });
  final String label;
  final RefKind kind;
  final String? selectedLabel;
  final bool hasValue;
  final void Function(RefItem? item) onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () async {
        final r = await showModalBottomSheet<RefItem?>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _RefPickerSheet(kind: kind, title: label),
        );
        if (r != null) onChanged(r.id.isEmpty ? null : r);
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Sizes.minTouch),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: hasValue
                ? IconButton(
                    tooltip: 'Bağlantıyı kaldır',
                    icon: const Icon(Icons.close),
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.search),
          ),
          child: Text(selectedLabel ?? 'Seçin (isteğe bağlı)'),
        ),
      ),
    );
  }
}

class _RefPickerSheet extends ConsumerStatefulWidget {
  const _RefPickerSheet({required this.kind, required this.title});
  final RefKind kind;
  final String title;

  @override
  ConsumerState<_RefPickerSheet> createState() => _RefPickerSheetState();
}

class _RefPickerSheetState extends ConsumerState<_RefPickerSheet> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final res = ref.watch(refSearchProvider((kind: widget.kind, q: _q)));
    final h = MediaQuery.sizeOf(context).height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: h,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: TextField(
                controller: _c,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: '${widget.title} ara',
                  prefixIcon: const Icon(Icons.search),
                ),
                onSubmitted: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Expanded(
              child: AsyncValueView<List<RefItem>>(
                value: res,
                onRetry: () => ref.invalidate(refSearchProvider),
                isEmpty: (d) => d.isEmpty,
                empty: const EmptyState(
                  title: 'Sonuç bulunamadı',
                  icon: Icons.search_off,
                ),
                data: (items) => ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    return ListTile(
                      minVerticalPadding: Space.md,
                      title: Text(it.label),
                      subtitle: it.sub == null ? null : Text(it.sub!),
                      onTap: () => Navigator.of(context).pop(it),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
