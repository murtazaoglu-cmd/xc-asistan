// Müşteri kartındaki "Yazışmalar" bölümü. customers modülündeki `conversationSectionBuilderProvider`
// şu şekilde bağlanır (bkz. docs/CORE-REQUESTS.md):
//   conversationSectionBuilderProvider.overrideWithValue(
//     (context, args) => AssistantConversationSection(
//         phoneKey: args.customer.phoneKey, name: args.customer.name))
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/formatters.dart';
import '../application/access.dart';
import '../application/assistant_providers.dart';
import '../application/assistant_routes_paths.dart';
import '../data/assistant_repository.dart';
import '../data/model_utils.dart';
import 'widgets/assistant_ui.dart';

class AssistantConversationSection extends ConsumerWidget {
  const AssistantConversationSection({
    super.key,
    required this.phoneKey,
    this.name,
  });

  /// Müşteri telefonu (rakamlar); asistan anahtarı son 10 haneden üretilir.
  final String phoneKey;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(assistantAccessProvider);
    if (!access.canImport) return const SizedBox.shrink();
    final key = assistantCustomerKey(phoneKey);
    final convs = ref.watch(conversationsProvider(key));
    final notes = ref.watch(customerNotesProvider(key));

    Future<void> deleteAll() async {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Tüm yazışma verisini sil',
        message:
            '${name ?? 'Bu müşteri'} için içe aktarılan yazışmalar, notlar ve öneriler kalıcı olarak silinir.',
        confirmLabel: 'Sil',
        destructive: true,
      );
      if (!ok) return;
      try {
        await ref.read(assistantRepositoryProvider).deleteCustomerData(key);
        ref.invalidate(conversationsProvider(key));
        ref.invalidate(customerNotesProvider(key));
        if (context.mounted) toast(context, 'Yazışma verisi silindi.');
      } on Object catch (e) {
        if (context.mounted) toast(context, errorText(e));
      }
    }

    Future<void> deleteOne(String id) async {
      final ok = await ConfirmDialog.show(
        context,
        title: 'Yazışmayı sil',
        message: 'Bu yazışma ve ondan çıkan öneriler silinir.',
        confirmLabel: 'Sil',
        destructive: true,
      );
      if (!ok) return;
      try {
        await ref.read(conversationsProvider(key).notifier).delete(id);
      } on Object catch (e) {
        if (context.mounted) toast(context, errorText(e));
      }
    }

    return SectionCard(
      title: 'Yazışmalar ve notlar',
      trailing: TextButton.icon(
        onPressed: () => context.push(AssistantPaths.shareForCustomer(key)),
        icon: const Icon(Icons.add),
        label: const Text('Yazışma ekle'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          convs.when(
            loading: () => const SkeletonBox(height: 56, radius: Radii.md),
            error: (e, _) => ErrorState(
              message: errorText(e),
              onRetry: () => ref.invalidate(conversationsProvider(key)),
            ),
            data: (items) => items.isEmpty
                ? Text(
                    'Henüz yazışma eklenmedi. WhatsApp sohbetini dışa aktarıp buraya paylaşın.',
                    style: context.text.bodyMedium,
                  )
                : Column(
                    children: [
                      for (final c in items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          minTileHeight: Sizes.minTouch,
                          leading: const Icon(Icons.chat_outlined),
                          title: Text(c.title),
                          subtitle: Text(
                            [
                              '${c.messageCount} mesaj',
                              if (c.lastAt != null) Fmt.date(c.lastAt!),
                              if (c.summaryText != null) c.summaryText!,
                            ].join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: 'Yazışmayı sil',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => deleteOne(c.id),
                          ),
                        ),
                    ],
                  ),
          ),
          notes.maybeWhen(
            data: (items) => items.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Notlar'),
                      for (final n in items.take(5))
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.xs),
                          child: Text(
                            '• ${n.text}${n.byRule ? ' (otomatik)' : ''}',
                            style: context.text.bodyMedium,
                          ),
                        ),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => context.push(
                  AssistantPaths.suggestionsFor(customerKey: key),
                ),
                child: const Text('Önerilere bak'),
              ),
              TextButton(
                onPressed: deleteAll,
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.error,
                ),
                child: const Text('Tüm yazışma verisini sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
