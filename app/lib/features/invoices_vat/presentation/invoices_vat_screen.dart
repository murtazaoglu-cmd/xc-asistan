// Fatura ve KDV: Faturalar · KDV · Vergi Takvimi · Ödeme Planı. Erişim: admin/muhasebe tam,
// ortak kendi defteri; personel/saha YOK (menüde gizli, rota korumalı, burada da denetlenir).
// Uygulama fatura KESMEZ, takip eder; hukuki/mali tavsiye vermez.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/invoices_vat_providers.dart';
import 'invoices_tab.dart';
import 'payment_plan_tab.dart';
import 'tax_calendar_tab.dart';
import 'vat_tab.dart';

class InvoicesVatScreen extends ConsumerStatefulWidget {
  const InvoicesVatScreen({super.key, this.initialTab = 0});

  /// 0 Faturalar · 1 KDV · 2 Vergi Takvimi · 3 Ödeme Planı
  final int initialTab;

  @override
  ConsumerState<InvoicesVatScreen> createState() => _InvoicesVatScreenState();
}

class _InvoicesVatScreenState extends ConsumerState<InvoicesVatScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(
        length: 4,
        vsync: this,
        initialIndex: widget.initialTab.clamp(0, 3),
      )..addListener(() {
        if (mounted) setState(() {});
      });

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(invoicesVatAccessProvider);
    if (access == null || !access.canView) {
      return AppScaffold(
        title: 'Fatura ve KDV',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüme erişim yetkiniz yok',
          message: 'Fatura ve KDV yalnızca yönetici, muhasebe ve iş ortağı hesaplarına açıktır.',
          actionLabel: 'Bugün\'e dön',
          onAction: () => context.go(Routes.today),
        ),
      );
    }

    Widget? fab;
    switch (_tabs.index) {
      case 0:
        fab = FloatingActionButton.extended(
          key: const Key('fab_invoice'),
          onPressed: () => context.push('${Routes.invoicesVat}/new'),
          icon: const Icon(Icons.add),
          label: const Text('Fatura ekle'),
        );
      case 2:
        if (access.canEditTaxCalendar) {
          fab = FloatingActionButton.extended(
            key: const Key('fab_tax'),
            onPressed: () => showTaxItemDialog(context, ref),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Hatırlatma ekle'),
          );
        }
      case 3:
        fab = FloatingActionButton.extended(
          key: const Key('fab_plan'),
          onPressed: () => context.push('${Routes.invoicesVat}/plan/new'),
          icon: const Icon(Icons.add),
          label: const Text('Taksit planı'),
        );
    }

    return AppScaffold(
      title: 'Fatura ve KDV',
      wideLayout: true,
      floatingActionButton: fab,
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Faturalar'),
          Tab(text: 'KDV'),
          Tab(text: 'Vergi Takvimi'),
          Tab(text: 'Ödeme Planı'),
        ],
      ),
      body: Column(
        children: [
          if (access.ownLedgerOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.sm,
                Space.lg,
                0,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: Sizes.iconSm,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      'Yalnızca kendi defteriniz gösterilir.',
                      style: context.text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: const [
                InvoicesTab(),
                VatTab(),
                TaxCalendarTab(),
                PaymentPlanTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
