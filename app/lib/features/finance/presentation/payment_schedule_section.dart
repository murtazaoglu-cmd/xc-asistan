// Vade / ödeme sözü GENİŞLETME NOKTASI. invoices_vat ajanı gerçek içeriği
// `paymentScheduleBuilderProvider`'ı override ederek verir (taksit planı, ödeme sözü tarihi).
// Şimdilik yer tutucu gösterilir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../data/finance_models.dart';

typedef PaymentScheduleBuilder = Widget Function(
  BuildContext context,
  ProjectRef project,
);

/// null → yer tutucu. invoices_vat: `paymentScheduleBuilderProvider.overrideWithValue(...)`.
final paymentScheduleBuilderProvider = Provider<PaymentScheduleBuilder?>(
  (ref) => null,
);

class PaymentScheduleSection extends ConsumerWidget {
  const PaymentScheduleSection({super.key, required this.project});
  final ProjectRef project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builder = ref.watch(paymentScheduleBuilderProvider);
    if (builder != null) return builder(context, project);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_note_outlined,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Vade ve ödeme sözü bilgisi burada gösterilecek.',
              style: context.text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
