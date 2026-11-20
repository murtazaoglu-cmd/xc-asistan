// Yazışmadan çıkarılan kural tabanlı öneriler (not / hatırlatma / randevu). Her öneri kaynak mesaja bağlı;
// Kabul / Düzenle / Reddet. Randevu kabulü sunucudan bir ONAY KARTI döndürür; kart Asistan sohbetine eklenir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../application/chat_controller.dart';
import '../data/import_models.dart';
import 'widgets/assistant_ui.dart';

class SuggestionsScreen extends ConsumerWidget {
  const SuggestionsScreen({super.key, this.conversationId, this.customerKey});
  final String? conversationId;
  final String? customerKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = (conversationId: conversationId, customerKey: customerKey);
    final async = ref.watch(suggestionsProvider(q));
    return AppScaffold(
      title: 'Yazışma önerileri',
      showMenuButton: false,
      body: async.when(
        loading: () => const SkeletonList(),
        error: (e, _) => FillRefresh(
          onRefresh: () => ref.refresh(suggestionsProvider(q).future),
          child: ErrorState(
            message: errorText(e),
            onRetry: () => ref.invalidate(suggestionsProvider(q)),
          ),
        ),
        data: (items) => items.isEmpty
            ? FillRefresh(
                onRefresh: () => ref.refresh(suggestionsProvider(q).future),
                child: const EmptyState(
                  icon: Icons.lightbulb_outline,
                  title: 'Bekleyen öneri yok',
                  message: 'Yazışmalardan çıkan not, hatırlatma ve randevu önerileri burada görünür.',
                ),
              )
            : PullToRefresh(
                onRefresh: () => ref.refresh(suggestionsProvider(q).future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(Space.lg),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.md),
                  itemBuilder: (_, i) =>
                      SuggestionCardView(suggestion: items[i], query: q),
                ),
              ),
      ),
    );
  }
}

const _fieldLabels = {
  'text': 'Metin',
  'title': 'Başlık',
  'date': 'Tarih',
  'time': 'Saat',
  'when': 'Zaman',
  'remind_at': 'Hatırlatma zamanı',
  'note': 'Not',
  'type': 'Tür',
};

class SuggestionCardView extends ConsumerStatefulWidget {
  const SuggestionCardView({
    super.key,
    required this.suggestion,
    required this.query,
  });
  final Suggestion suggestion;
  final SuggestionQuery query;

  @override
  ConsumerState<SuggestionCardView> createState() => _SuggestionCardViewState();
}

class _SuggestionCardViewState extends ConsumerState<SuggestionCardView> {
  bool _busy = false;

  Future<void> _decide(String status, {Map<String, String>? fields}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final d = await ref
          .read(suggestionsProvider(widget.query).notifier)
          .decide(widget.suggestion.id, status, fields: fields);
      final card = d.card;
      if (card != null) {
        ref.read(chatControllerProvider.notifier).addExternalCard(card);
        messenger
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: const Text(
                'Randevu onay kartı hazır. Asistan sohbetinde onaylayın.',
              ),
              action: SnackBarAction(
                label: 'Aç',
                onPressed: () => router.go(AssistantPaths.root),
              ),
            ),
          );
      } else if (status == 'kabul') {
        messenger
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(content: Text('Kaydedildi.')));
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, errorText(e));
      }
    }
  }

  Future<void> _edit() async {
    final s = widget.suggestion;
    final keys = s.fields.isEmpty ? ['text'] : s.fields.keys.toList();
    final ctrls = {
      for (final k in keys)
        k: TextEditingController(
          text: s.fields[k] ?? (k == 'text' ? s.text : ''),
        ),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.kind.label} önerisini düzenle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final k in keys)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: TextField(
                    controller: ctrls[k],
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _fieldLabels[k] ?? k,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kabul et'),
          ),
        ],
      ),
    );
    final values = {for (final e in ctrls.entries) e.key: e.value.text.trim()};
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (ok != true) return;
    final changed = {
      for (final e in values.entries)
        if (e.value != (s.fields[e.key] ?? (e.key == 'text' ? s.text : '')))
          e.key: e.value,
    };
    await _decide('kabul', fields: changed.isEmpty ? null : changed);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final src = s.sourceText;
    return AiCard(
      kind: AiCardKind.noteSuggestion,
      title: '${s.kind.label}: ${s.title ?? s.text}',
      body: s.title == null || s.title == s.text ? null : s.text,
      actions: [
        AiCardAction(
          'Kabul et',
          _busy ? null : () => _decide('kabul'),
          primary: true,
        ),
        AiCardAction('Düzenle', _busy ? null : _edit),
        AiCardAction('Reddet', _busy ? null : () => _decide('red')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in s.fields.entries)
            Text(
              '${_fieldLabels[e.key] ?? e.key}: ${e.value}',
              style: context.text.bodyMedium,
            ),
          if (src != null && src.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.sm),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        'Kaynak mesaj',
                        if (s.sourceSender != null) s.sourceSender!,
                        if (s.sourceAt != null) Fmt.dateTime(s.sourceAt!),
                      ].join(' · '),
                      style: context.text.labelSmall,
                    ),
                    const SizedBox(height: Space.xs),
                    Text('“$src”', style: context.text.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
