// Yazışma geçmişi için GENİŞLETME NOKTASI. assistant ajanı bu bölümü doldurur:
//   ProviderScope override:  conversationSectionBuilderProvider.overrideWithValue(...)
// ya da bu dosyadaki varsayılan oluşturucuyu kendi widget'ıyla değiştirir.
// Müşteri kartı yalnız `ConversationSection(customer: c)` çağırır; yer tutucu burada kalır.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/customer_models.dart';

@immutable
class ConversationSectionArgs {
  const ConversationSectionArgs({required this.customer});
  final Customer customer;
}

typedef ConversationSectionBuilder = Widget Function(
  BuildContext context,
  ConversationSectionArgs args,
);

/// Varsayılan: yer tutucu. assistant ajanı gerçek yazışma listesiyle değiştirir.
final conversationSectionBuilderProvider = Provider<ConversationSectionBuilder>(
  (ref) =>
      (context, args) => ConversationPlaceholder(customer: args.customer),
);

class ConversationSection extends ConsumerWidget {
  const ConversationSection({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ref.watch(
    conversationSectionBuilderProvider,
  )(context, ConversationSectionArgs(customer: customer));
}

class ConversationPlaceholder extends StatelessWidget {
  const ConversationPlaceholder({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Yazışma geçmişi',
      child: Row(
        children: [
          Icon(Icons.forum_outlined, color: context.colors.outline),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Bu müşteriyle yapılan yazışmalar burada görünecek.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
