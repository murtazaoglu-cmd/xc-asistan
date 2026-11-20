// Komut çubuğu Onay kartı: özet metin + alanlar + Onayla / Düzenle / Vazgeç; uygulandıktan sonra
// 10 dk "Geri al". Uyarılar ve belirsizlikler kartta görünür; kart durumu (bekliyor/uygulandı/
// reddedildi/süresi doldu) rozetle gösterilir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/util/dates.dart';
import '../../../../core/util/formatters.dart';
import '../../../../core/util/money.dart';
import '../../application/chat_controller.dart';
import '../../data/command_models.dart';

class ActionCardView extends ConsumerWidget {
  const ActionCardView({
    super.key,
    required this.cardId,
    required this.card,
    required this.fallbackText,
    this.statusHint,
  });

  final String cardId;

  /// Henüz yüklenmediyse (geri yükleme) null.
  final ActionCard? card;
  final String fallbackText;
  final String? statusHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final busy = chat.busyCards.contains(cardId);
    final error = chat.cardErrors[cardId];
    final c = card;
    if (c == null) {
      final status = CardStatus.fromApi(statusHint);
      return AiCard(
        kind: AiCardKind.confirm,
        title: fallbackText,
        body: status.isFinal ? status.label : 'Kart yükleniyor…',
      );
    }
    final ctrl = ref.read(chatControllerProvider.notifier);
    final expired = c.isExpired();
    final pending = c.isPending && !expired;
    final x = context.xc;

    final actions = <AiCardAction>[
      if (pending) ...[
        AiCardAction(
          'Onayla',
          busy ? null : () => ctrl.confirm(c.id),
          primary: true,
        ),
        if (c.hasEditable)
          AiCardAction('Düzenle', busy ? null : () => _edit(context, ref, c)),
        AiCardAction('Vazgeç', busy ? null : () => ctrl.reject(c.id)),
      ] else if (c.canUndo())
        AiCardAction('Geri al', busy ? null : () => ctrl.undo(c.id)),
    ];

    return AiCard(
      kind: AiCardKind.confirm,
      title: c.title,
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBadge(status: expired ? CardStatus.suresiDoldu : c.status),
          if (c.fields.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            for (final f in c.fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(
                        f.label,
                        style: context.text.bodySmall?.copyWith(
                          color: x.onAiContainer,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        f.shownValue.isEmpty ? '-' : f.shownValue,
                        style: context.text.bodyMedium?.copyWith(
                          color: x.onAiContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (f.editable && pending)
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: x.onAiContainer,
                      ),
                  ],
                ),
              ),
          ],
          for (final w in c.ambiguities)
            _Note(icon: Icons.help_outline, text: w),
          for (final w in c.warnings)
            _Note(icon: Icons.warning_amber_rounded, text: w, warn: true),
          if (c.status == CardStatus.hata && (c.error ?? '').isNotEmpty)
            _Note(icon: Icons.error_outline, text: c.error!, warn: true),
          if (c.status == CardStatus.uygulandi && c.canUndo())
            _Note(
              icon: Icons.undo,
              text: c.undo.until == null
                  ? 'Geri alabilirsiniz.'
                  : '${Fmt.time(c.undo.until!)} saatine kadar geri alabilirsiniz.',
            ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: Space.sm),
              child: LinearProgressIndicator(),
            ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: Text(
                  error,
                  style: context.text.bodySmall?.copyWith(
                    color: context.colors.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ActionCard c) async {
    final edits = await showCardEditSheet(context, c);
    if (edits == null || edits.isEmpty) return;
    await ref.read(chatControllerProvider.notifier).editCard(c.id, edits);
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.warn = false});
  final IconData icon;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: warn ? x.warning : x.onAiContainer),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.bodySmall?.copyWith(color: x.onAiContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final CardStatus status;

  @override
  Widget build(BuildContext context) {
    final x = context.xc;
    final (icon, bg, fg) = switch (status) {
      CardStatus.onerildi || CardStatus.onaylandi => (
        Icons.hourglass_top,
        x.warningContainer,
        x.onWarning,
      ),
      CardStatus.uygulandi => (
        Icons.check_circle_outline,
        x.successContainer,
        context.colors.onSurface,
      ),
      CardStatus.reddedildi => (
        Icons.cancel_outlined,
        context.colors.errorContainer,
        context.colors.onErrorContainer,
      ),
      CardStatus.hata => (
        Icons.error_outline,
        context.colors.errorContainer,
        context.colors.onErrorContainer,
      ),
      CardStatus.geriAlindi => (
        Icons.undo,
        x.neutralContainer,
        context.colors.onSurface,
      ),
      CardStatus.suresiDoldu => (
        Icons.timer_off_outlined,
        x.neutralContainer,
        context.colors.onSurface,
      ),
      CardStatus.bilinmiyor => (
        Icons.help_outline,
        x.neutralContainer,
        context.colors.onSurface,
      ),
    };
    return Semantics(
      label: 'Kart durumu: ${status.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: Space.xs),
            Text(
              status.label,
              style: context.text.labelMedium?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Düzenlenebilir alanları değiştirme sayfası. Yalnız DEĞİŞEN alanlar döner (sunucu biçiminde).
Future<Map<String, Object?>?> showCardEditSheet(
  BuildContext context,
  ActionCard card,
) {
  return showModalBottomSheet<Map<String, Object?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => CardEditSheet(card: card),
  );
}

class CardEditSheet extends StatefulWidget {
  const CardEditSheet({super.key, required this.card});
  final ActionCard card;

  @override
  State<CardEditSheet> createState() => _CardEditSheetState();
}

class _CardEditSheetState extends State<CardEditSheet> {
  late final Map<String, Object?> _values = {};
  late final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _errors = {};

  List<CardField> get _fields =>
      widget.card.fields.where((f) => f.editable).toList();

  @override
  void initState() {
    super.initState();
    for (final f in _fields) {
      if (_isText(f)) {
        _ctrls[f.key] = TextEditingController(
          text: f.value == null ? '' : _initialText(f),
        );
      }
    }
  }

  bool _isText(CardField f) =>
      !{'choice', 'date', 'time', 'datetime'}.contains(f.type) ||
      (f.type == 'choice' && f.options.isEmpty);

  String _initialText(CardField f) {
    if (f.type == 'money') {
      final m = Money.tryFromJson(f.value);
      return m == null ? '${f.value}' : m.format(symbol: false);
    }
    return '${f.value}';
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? _current(CardField f) => _values[f.key] is DateTime
      ? _values[f.key] as DateTime
      : Ist.tryParse(f.value?.toString());

  Future<void> _pickDate(CardField f) async {
    final cur = _current(f) ?? Ist.now();
    final w = Ist.wall(cur);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(w.year, w.month, w.day),
      firstDate: DateTime(w.year - 1),
      lastDate: DateTime(w.year + 3),
    );
    if (picked == null) return;
    final next = Ist.fromWall(
      picked.year,
      picked.month,
      picked.day,
      w.hour,
      w.minute,
    );
    setState(() => _values[f.key] = next);
  }

  Future<void> _pickTime(CardField f) async {
    final cur = _current(f) ?? Ist.now();
    final w = Ist.wall(cur);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: w.hour, minute: w.minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final next = Ist.fromWall(
      w.year,
      w.month,
      w.day,
      picked.hour,
      picked.minute,
    );
    setState(() => _values[f.key] = next);
  }

  /// Sunucuya gidecek değerler (yalnız değişenler). Geçersizse null + hata metni.
  Map<String, Object?>? _collect() {
    final out = <String, Object?>{};
    _errors.clear();
    var ok = true;
    for (final f in _fields) {
      if (_isText(f)) {
        final text = _ctrls[f.key]!.text.trim();
        final orig = f.value == null ? '' : _initialText(f).trim();
        if (text == orig) continue;
        if (f.type == 'money') {
          final m = Money.parseUserInput(text);
          if (m == null || !m.isPositive) {
            _errors[f.key] = 'Geçerli bir tutar girin.';
            ok = false;
            continue;
          }
          out[f.key] = m.toApiString();
        } else if (f.type == 'number') {
          final n = num.tryParse(text.replaceAll(',', '.'));
          if (n == null) {
            _errors[f.key] = 'Sayı girin.';
            ok = false;
            continue;
          }
          out[f.key] = n;
        } else {
          if (text.isEmpty) {
            _errors[f.key] = 'Boş bırakılamaz.';
            ok = false;
            continue;
          }
          out[f.key] = text;
        }
      } else if (_values.containsKey(f.key)) {
        final v = _values[f.key];
        if (v is DateTime) {
          out[f.key] = switch (f.type) {
            'date' => Ist.toApiIso(v).substring(0, 10),
            'time' => Ist.toApiIso(v).substring(11, 16),
            _ => Ist.toApiIso(v),
          };
        } else if (v != null && v.toString() != (f.value?.toString() ?? '')) {
          out[f.key] = v;
        }
      }
    }
    return ok ? out : null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: Space.lg,
        right: Space.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Kartı düzenle', style: context.text.titleMedium),
            const SizedBox(height: Space.xs),
            Text(widget.card.title, style: context.text.bodySmall),
            const SizedBox(height: Space.lg),
            for (final f in _fields) ...[
              _fieldWidget(f),
              const SizedBox(height: Space.md),
            ],
            const SizedBox(height: Space.sm),
            Row(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgeç'),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final r = _collect();
                      if (r == null) {
                        setState(() {});
                        return;
                      }
                      Navigator.of(context).pop(r);
                    },
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldWidget(CardField f) {
    switch (f.type) {
      case 'choice' when f.options.isNotEmpty:
        final cur = (_values[f.key] ?? f.value)?.toString();
        return DropdownButtonFormField<String>(
          initialValue: f.options.any((o) => o.value == cur) ? cur : null,
          decoration: InputDecoration(labelText: f.label),
          items: [
            for (final o in f.options)
              DropdownMenuItem(value: o.value, child: Text(o.label)),
          ],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case 'date':
      case 'time':
      case 'datetime':
        final d = _current(f);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label, style: context.text.labelLarge),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                if (f.type != 'time')
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(f),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(d == null ? 'Tarih seç' : Fmt.date(d)),
                  ),
                if (f.type != 'date')
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(f),
                    icon: const Icon(Icons.schedule),
                    label: Text(d == null ? 'Saat seç' : Fmt.time(d)),
                  ),
              ],
            ),
          ],
        );
      default:
        return TextField(
          controller: _ctrls[f.key],
          keyboardType: (f.type == 'money' || f.type == 'number')
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: f.label,
            prefixText: f.type == 'money' ? '₺ ' : null,
            errorText: _errors[f.key],
          ),
        );
    }
  }
}

/// Sohbet geçmişinde yeniden kullanılan kısa durum metni.
String cardStatusSentence(ActionCard c) => switch (c.status) {
  CardStatus.uygulandi => 'Uygulandı.',
  CardStatus.reddedildi => 'Vazgeçildi.',
  CardStatus.geriAlindi => 'Geri alındı.',
  CardStatus.suresiDoldu => 'Süresi doldu.',
  CardStatus.hata => 'Uygulanamadı.',
  _ => 'Onayınızı bekliyor.',
};

/// Servis ve test erişimi için: kartın şu an üzerinde işlem yapılabilir mi?
bool cardIsActionable(ActionCard c) => c.isPending && !c.isExpired();

/// `maxCommandLength` yeniden dışa açılır (giriş alanı sınırı).
const int commandLimit = maxCommandLength;
