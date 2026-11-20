// DIŞA AÇILAN bileşen: finance "Para" ekranındaki PaymentScheduleSection genişletme noktasına takılır.
// Proje başına taksit/vade/çek-senet satırlarını gösterir; "Plan oluştur" sihirbazını açar.
// Bağlama: docs/CORE-REQUESTS.md ("invoices_vat → finance bağlantısı") ve docs/ARCHITECTURE.md §7.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/money.dart';
import '../data/invoices_vat_providers.dart';
import 'schedule_widgets.dart';

class PaymentScheduleSection extends ConsumerWidget {
  const PaymentScheduleSection({
    super.key,
    required this.projectId,
    this.projectCode,
    this.customerName,
    this.remaining,
    this.maxRows = 5,
  });

  /// Projenin kimliği (ham UUID ekranda gösterilmez).
  final String projectId;
  final String? projectCode;
  final String? customerName;

  /// Projede kalan bakiye (sihirbaza varsayılan toplam olarak taşınır).
  final Money? remaining;
  final int maxRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(invoicesVatAccessProvider);
    // personel/saha: bu uçlar 403 → bölüm hiç çizilmez.
    if (access == null || !access.canView) return const SizedBox.shrink();
    final async = ref.watch(
      scheduleProvider(ScheduleFilter(projectId: projectId)),
    );
    final label = [projectCode, customerName].whereType<String>().join(' · ');

    return Column(
      key: const Key('payment_schedule_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vade ve ödeme planı',
                style: context.text.titleSmall,
              ),
            ),
            TextButton.icon(
              key: const Key('section_new_plan'),
              onPressed: () => context.push(
                Uri(
                  path: '${Routes.invoicesVat}/plan/new',
                  queryParameters: {
                    'projectId': projectId,
                    if (label.isNotEmpty) 'label': label,
                    if (remaining != null && remaining!.isPositive)
                      'total': '${remaining!.kurus}',
                  },
                ).toString(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Plan oluştur'),
            ),
          ],
        ),
        async.when(
          loading: () => const SkeletonBox(height: 72, radius: Radii.md),
          error: (e, _) => Row(
            children: [
              Expanded(
                child: Text('Plan alınamadı.', style: context.text.bodySmall),
              ),
              TextButton(
                onPressed: () => ref.invalidate(scheduleProvider),
                child: const Text('Tekrar dene'),
              ),
            ],
          ),
          data: (items) {
            final open = items.where((s) => !s.isCancelled).toList()
              ..sort((a, b) {
                if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
                final x = a.dueDate, y = b.dueDate;
                if (x == null || y == null) return x == null ? 1 : -1;
                return x.compareTo(y);
              });
            if (open.isEmpty) {
              return Text(
                'Bu iş için vade/taksit planı yok. "Plan oluştur" ile taksit, çek veya senet ekleyin.',
                style: context.text.bodySmall,
              );
            }
            final shown = open.take(maxRows).toList();
            return Column(
              children: [
                for (final s in shown) ScheduleRowTile(item: s),
                if (open.length > shown.length)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push(Routes.invoicesVat),
                      child: Text('Tümünü gör (${open.length})'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
