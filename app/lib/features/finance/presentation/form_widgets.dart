// Para formlarının ortak parçaları: tutar alanı, tarih çipleri, seçenek çipleri, proje alanı.
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/util/dates.dart';
import '../../../core/util/formatters.dart';
import '../../../core/util/money.dart';
import '../data/finance_input.dart';
import '../data/finance_models.dart';

/// Form bölümü başlığı + içerik.
class FormBlock extends StatelessWidget {
  const FormBlock({super.key, required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.titleSmall),
          const SizedBox(height: Space.sm),
          child,
        ],
      ),
    );
  }
}

/// Büyük tutar alanı: sayı klavyesi, yalnız rakam/virgül/nokta, kuruş doğrulaması.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.onChanged,
    this.autofocus = false,
    this.label = 'Tutar',
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: context.text.headlineSmall,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₺ ',
        hintText: '0,00',
      ),
      validator: (v) => FinanceValidators.amount(v).error,
      onChanged: onChanged,
    );
  }
}

/// Bugün / Dün / Seç… tarih çipleri. [value] bir an (İstanbul günü).
class DateChips extends StatelessWidget {
  const DateChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.lastDate,
  });

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  /// En ileri seçilebilir gün (varsayılan bugün).
  final DateTime? lastDate;

  static DateTime _dayAt(int offsetDays) {
    final w = Ist.wall(Ist.now());
    return Ist.fromWall(w.year, w.month, w.day + offsetDays, 12);
  }

  @override
  Widget build(BuildContext context) {
    final today = _dayAt(0);
    final yesterday = _dayAt(-1);
    final isToday = Ist.isSameDay(value, today);
    final isYesterday = Ist.isSameDay(value, yesterday);
    final custom = !isToday && !isYesterday;
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Bugün'),
          selected: isToday,
          onSelected: (_) => onChanged(today),
        ),
        ChoiceChip(
          label: const Text('Dün'),
          selected: isYesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(custom ? Fmt.date(value) : 'Tarih seç'),
          selected: custom,
          onSelected: (_) async {
            final w = Ist.wall(value);
            final last = Ist.wall(lastDate ?? today);
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(w.year, w.month, w.day),
              firstDate: DateTime(2000),
              lastDate: DateTime(last.year, last.month, last.day),
              helpText: 'Tarih seçin',
              cancelText: 'Vazgeç',
              confirmText: 'Tamam',
            );
            if (picked != null) {
              onChanged(
                Ist.fromWall(picked.year, picked.month, picked.day, 12),
              );
            }
          },
        ),
      ],
    );
  }
}

/// Tek seçimli çip grubu (yöntem, kapsam...). Dokunma hedefi ≥ 48.
class OptionChips<T> extends StatelessWidget {
  const OptionChips({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelOf,
    this.iconOf,
  });

  final List<T> options;
  final T? value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final o in options)
          ChoiceChip(
            avatar: iconOf?.call(o) == null ? null : Icon(iconOf!(o), size: 18),
            label: Text(labelOf(o)),
            selected: o == value,
            onSelected: (_) => onChanged(o),
          ),
      ],
    );
  }
}

/// Seçili proje satırı (dokununca seçici açılır). ASLA ham UUID göstermez.
class ProjectField extends StatelessWidget {
  const ProjectField({
    super.key,
    required this.project,
    required this.onTap,
    this.placeholder = 'Proje seçin',
    this.errorText,
    this.loading = false,
    this.readOnlyLabel,
    this.onClear,
  });

  final ProjectRef? project;
  final String placeholder;
  final String? errorText;
  final bool loading;

  /// Düzenlemede proje değiştirilemez: yalnız etiket gösterilir.
  final String? readOnlyLabel;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final label = readOnlyLabel ?? project?.displayLabel;
    final remaining = project?.remaining;
    final hasError = errorText != null;
    return Semantics(
      button: onTap != null,
      label: 'Proje: ${label ?? placeholder}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md),
              side: BorderSide(
                color: hasError ? scheme.error : scheme.outlineVariant,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: readOnlyLabel != null ? null : onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Sizes.minTouch + 8,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.work_outline,
                        color: scheme.onSurfaceVariant,
                        size: Sizes.iconMd,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: loading
                            ? const Text('Yükleniyor…')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label ?? placeholder,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.bodyLarge?.copyWith(
                                      color: label == null
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface,
                                    ),
                                  ),
                                  if (project != null &&
                                      (project!.service ?? '').isNotEmpty)
                                    Text(
                                      remaining != null && remaining.isPositive
                                          ? '${project!.service} · Kalan ${remaining.format(hideZeroKurus: true)}'
                                          : project!.service!,
                                      style: context.text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      if (onClear != null && project != null)
                        IconButton(
                          tooltip: 'Projeyi kaldır',
                          icon: const Icon(Icons.close),
                          onPressed: onClear,
                        )
                      else if (readOnlyLabel == null)
                        Icon(Icons.expand_more, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs, left: Space.md),
              child: Text(
                errorText!,
                style: context.text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sunucu/ağ hatası şeridi (formun üstünde, ekran okuyucuya duyurulur).
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.lg),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uyarı satırı (kalandan fazla vb.). Renk + ikon + metin.
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: Sizes.iconSm, color: x.warning),
          const SizedBox(width: Space.sm),
          Expanded(child: Text(message, style: context.text.bodySmall)),
        ],
      ),
    );
  }
}

/// "₺12.500,00" (simgesiz) → alan metni.
String amountFieldText(Money m) => m.format(symbol: false);
