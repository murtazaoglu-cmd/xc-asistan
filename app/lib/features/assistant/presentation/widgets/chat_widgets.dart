// Sohbet balonları: kullanıcı (açık mavi), asistan (+ kartlar), sayı kutuları, seçenek soruları,
// "Ne demek istediniz?" kartı, hata balonu.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/tokens.dart';
import '../../../../core/util/dates.dart';
import '../../../../core/util/json.dart';
import '../../../../core/util/money.dart';
import '../../application/chat_controller.dart';
import '../../application/chat_models.dart';
import '../../data/command_models.dart';
import 'action_card_view.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message, required this.isLast});
  final ChatMessage message;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) return UserBubble(text: message.text);
    switch (message.kind) {
      case ChatKind.card:
        return _Left(
          child: ActionCardView(
            cardId: message.cardId ?? '',
            card: message.card,
            fallbackText: message.text,
            statusHint: message.cardStatus,
          ),
        );
      case ChatKind.clarify:
        return _Left(child: ClarifyView(message: message));
      case ChatKind.options:
        return _Left(child: OptionsCard(message: message));
      case ChatKind.error:
        return _Left(child: ErrorBubble(message: message));
      case ChatKind.answer:
        return _Left(
          child: AnswerBubble(message: message, showChips: isLast),
        );
      case ChatKind.text:
        return _Left(child: AssistantTextBubble(text: message.text));
    }
  }
}

class _Left extends StatelessWidget {
  const _Left({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.92,
      ),
      child: child,
    ),
  );
}

class UserBubble extends StatelessWidget {
  const UserBubble({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        label: 'Siz: $text',
        excludeSemantics: true,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: context.colors.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Radii.card),
              topRight: Radius.circular(Radii.card),
              bottomLeft: Radius.circular(Radii.card),
              bottomRight: Radius.circular(Radii.xs),
            ),
          ),
          child: Text(
            text,
            style: context.text.bodyLarge?.copyWith(
              color: context.colors.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class AssistantTextBubble extends StatelessWidget {
  const AssistantTextBubble({
    super.key,
    required this.text,
    this.muted = false,
    this.icon,
  });
  final String text;
  final bool muted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Asistan: $text',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border.all(color: context.colors.outlineVariant),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Radii.xs),
            topRight: Radius.circular(Radii.card),
            bottomLeft: Radius.circular(Radii.card),
            bottomRight: Radius.circular(Radii.card),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: Sizes.iconSm,
                color: context.colors.onSurfaceVariant,
              ),
              const SizedBox(width: Space.sm),
            ],
            Flexible(
              child: Text(
                text,
                style: context.text.bodyLarge?.copyWith(
                  color: muted
                      ? context.colors.onSurfaceVariant
                      : context.colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ yanıt + sayı kutuları

/// Yanıt `data` alanından gösterilecek kutular (saf; testlenebilir).
class AnswerNumbers {
  const AnswerNumbers({
    this.tiles = const [],
    this.rows = const [],
    this.more = 0,
  });
  final List<({String label, String value})> tiles;
  final List<({String title, String? trailing})> rows;
  final int more;
  bool get isEmpty => tiles.isEmpty && rows.isEmpty;

  static const Map<String, String> _labels = {
    'total_kurus': 'Toplam',
    'collected_kurus': 'Tahsilat',
    'expense_kurus': 'Gider',
    'net_kurus': 'Net',
    'balance_kurus': 'Bakiye',
    'amount_kurus': 'Tutar',
    'count': 'Adet',
    'total': 'Toplam',
  };

  static String _pretty(String key) {
    final base = key.replaceAll('_kurus', '').replaceAll('_', ' ').trim();
    if (base.isEmpty) return key;
    return base[0].toUpperCase() + base.substring(1);
  }

  factory AnswerNumbers.from(JsonMap data, {int maxRows = 5}) {
    final tiles = <({String label, String value})>[];
    data.forEach((k, v) {
      if (v is! num) return;
      if (k.endsWith('_kurus')) {
        tiles.add((
          label: _labels[k] ?? _pretty(k),
          value: Money.fromKurus(v.toInt()).format(),
        ));
      } else if (k == 'count' || k == 'total') {
        tiles.add((label: _labels[k]!, value: v.toInt().toString()));
      }
    });
    final rows = <({String title, String? trailing})>[];
    final items = data.list('items');
    for (final it in items.take(maxRows)) {
      final title =
          it.strOrNull('title') ??
          it.strOrNull('name') ??
          it.strOrNull('customer_name') ??
          it.strOrNull('summary') ??
          it.strOrNull('label') ??
          it.strOrNull('text') ??
          '';
      if (title.isEmpty) continue;
      String? trailing = it.strOrNull('display');
      if (trailing == null) {
        for (final e in it.entries) {
          if (e.key.endsWith('_kurus') && e.value is num) {
            trailing = Money.fromKurus((e.value as num).toInt()).format();
            break;
          }
        }
      }
      rows.add((title: title, trailing: trailing));
    }
    return AnswerNumbers(
      tiles: tiles,
      rows: rows,
      more: items.length > maxRows ? items.length - maxRows : 0,
    );
  }
}

class AnswerBubble extends ConsumerWidget {
  const AnswerBubble({
    super.key,
    required this.message,
    required this.showChips,
  });
  final ChatMessage message;
  final bool showChips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nums = AnswerNumbers.from(message.data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AssistantTextBubble(
          text: message.text,
          muted: message.refused,
          icon: message.refused ? Icons.lock_outline : null,
        ),
        if (!nums.isEmpty) ...[
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final t in nums.tiles)
                _NumberTile(label: t.label, value: t.value),
            ],
          ),
          if (nums.rows.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: Space.sm),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.xs,
              ),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: context.colors.outlineVariant),
              ),
              child: Column(
                children: [
                  for (final r in nums.rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.title,
                              style: context.text.bodyMedium,
                            ),
                          ),
                          if (r.trailing != null)
                            Text(
                              r.trailing!,
                              style: context.text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (nums.more > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '+${nums.more} kayıt daha',
                          style: context.text.bodySmall,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (showChips && message.chips.isNotEmpty) ...[
          const SizedBox(height: Space.sm),
          CommandChips(chips: message.chips),
        ],
      ],
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.text.bodySmall),
          const SizedBox(height: Space.xs),
          Text(value, style: context.text.titleMedium),
        ],
      ),
    ),
  );
}

/// Dokununca komut olarak gönderilen öneri çipleri.
class CommandChips extends ConsumerWidget {
  const CommandChips({super.key, required this.chips});
  final List<String> chips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final c in chips)
          ActionChip(
            label: Text(c),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onPressed: sending
                ? null
                : () => ref.read(chatControllerProvider.notifier).send(c),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ "Ne demek istediniz?"

class OptionsCard extends StatelessWidget {
  const OptionsCard({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: Sizes.iconSm,
                color: context.colors.primary,
              ),
              const SizedBox(width: Space.sm),
              Text('Ne demek istediniz?', style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(message.text, style: context.text.bodyMedium),
          const SizedBox(height: Space.md),
          CommandChips(chips: message.chips),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ seçenek soruları

class ClarifyView extends ConsumerStatefulWidget {
  const ClarifyView({super.key, required this.message});
  final ChatMessage message;

  @override
  ConsumerState<ClarifyView> createState() => _ClarifyViewState();
}

class _ClarifyViewState extends ConsumerState<ClarifyView> {
  final Map<String, TextEditingController> _text = {};

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _answer(String field, String value, {String? label}) => ref
      .read(chatControllerProvider.notifier)
      .answerClarify(widget.message.id, field, value, label: label);

  Future<void> _pickDate(ClarifyQuestion q) async {
    final now = Ist.wall(Ist.now());
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    final iso = Ist.toApiIso(Ist.fromWall(d.year, d.month, d.day))
        .substring(0, 10);
    _answer(q.field, iso, label: '${d.day}.${d.month}.${d.year}');
  }

  Future<void> _pickTime(ClarifyQuestion q) async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    _answer(q.field, hhmm, label: hhmm);
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: Sizes.iconSm,
                color: context.colors.primary,
              ),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(m.text, style: context.text.titleSmall)),
            ],
          ),
          for (final q in m.questions) ...[
            const SizedBox(height: Space.md),
            Text(q.label, style: context.text.labelLarge),
            const SizedBox(height: Space.sm),
            switch (q.type) {
              'date' => OutlinedButton.icon(
                onPressed: (m.resolved || sending) ? null : () => _pickDate(q),
                icon: const Icon(Icons.event_outlined),
                label: Text(m.answers[q.field] ?? 'Tarih seç'),
              ),
              'time' => OutlinedButton.icon(
                onPressed: (m.resolved || sending) ? null : () => _pickTime(q),
                icon: const Icon(Icons.schedule),
                label: Text(m.answers[q.field] ?? 'Saat seç'),
              ),
              'text' => Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text.putIfAbsent(
                        q.field,
                        TextEditingController.new,
                      ),
                      enabled: !m.resolved && !sending,
                      decoration: InputDecoration(hintText: q.label),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (v) {
                        if (v.trim().isNotEmpty) _answer(q.field, v.trim());
                      },
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  IconButton.filled(
                    tooltip: 'Gönder',
                    onPressed: (m.resolved || sending)
                        ? null
                        : () {
                            final v = _text[q.field]?.text.trim() ?? '';
                            if (v.isNotEmpty) _answer(q.field, v);
                          },
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
              _ => Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final o in q.options)
                    ChoiceChip(
                      label: Text(o.label),
                      selected: m.answers[q.field] == o.value,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: (m.resolved || sending)
                          ? null
                          : (_) => _answer(q.field, o.value, label: o.label),
                    ),
                ],
              ),
            },
          ],
        ],
      ),
    );
  }
}

class ErrorBubble extends ConsumerWidget {
  const ErrorBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: context.colors.errorContainer,
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: context.colors.onErrorContainer,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    message.text,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.colors.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (message.retryText != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: TextButton.icon(
                  onPressed: () =>
                      ref.read(chatControllerProvider.notifier).retry(message),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar dene'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
