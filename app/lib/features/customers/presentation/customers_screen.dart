// Müşteriler: alfabetik gruplu liste, arama (?q=), sayfalama, ekleme.
// Tasarım: ekran 9 (arama + avatarlı satırlar + sağ altta "+" düğmesi).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/phone.dart';
import '../customers_routes.dart';
import '../data/customer_models.dart';
import '../data/customer_search.dart';
import '../data/customers_repository.dart';

/// Rol görünürlüğü: müşteriler yalnız admin/muhasebe/ortak (sözleşme §7).
abstract final class CustomersAccess {
  static bool canView(AppCapabilities? caps) =>
      caps != null && caps.showCustomers;
}

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
        ref.read(customerListProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) ref.read(customerQueryProvider.notifier).set(v);
    });
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    ref.read(customerQueryProvider.notifier).set('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final terms = ref.watch(brandProfileProvider).terms;
    final caps = ref.watch(capabilitiesProvider);
    if (!CustomersAccess.canView(caps)) {
      return AppScaffold(
        title: terms.customers,
        body: const EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
          message: 'Müşteri bilgilerini yalnızca yönetici, muhasebe ve iş ortağı görebilir.',
        ),
      );
    }
    final list = ref.watch(customerListProvider);
    final query = ref.watch(customerQueryProvider);
    final pending = ref.watch(pendingCustomerDeletesProvider);

    return AppScaffold(
      title: terms.customers,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(CustomerRoutes.create),
        icon: const Icon(Icons.add),
        label: Text('${terms.customer} ekle'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.screenH,
              Space.md,
              Space.screenH,
              Space.sm,
            ),
            child: TextField(
              controller: _search,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              inputFormatters: [LengthLimitingTextInputFormatter(100)],
              decoration: InputDecoration(
                hintText: 'Ad, telefon veya bölge ara',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Aramayı temizle',
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
              ),
            ),
          ),
          Expanded(
            child: AsyncValueView<CustomerListState>(
              value: list,
              onRetry: () => ref.invalidate(customerListProvider),
              data: (s) {
                final visible = s.items
                    .where((c) => !pending.contains(c.phoneKey))
                    .toList();
                if (visible.isEmpty) {
                  return PullToRefresh.fill(
                    onRefresh: () => ref.refresh(customerListProvider.future),
                    child: query.trim().isEmpty
                        ? EmptyState(
                            icon: Icons.people_outline,
                            title: 'Henüz ${terms.customer.toLowerCase()} yok',
                            message:
                                '${terms.customer} ekleyin ya da ${terms.offers.toLowerCase()} geldikçe burada listelenir.',
                            actionLabel:
                                'İlk ${terms.customer.toLowerCase()}yi ekle',
                            onAction: () => context.push(CustomerRoutes.create),
                          )
                        : EmptyState(
                            icon: Icons.search_off,
                            title: 'Sonuç bulunamadı',
                            message:
                                '"${query.trim()}" için eşleşen ${terms.customer.toLowerCase()} yok.',
                            actionLabel: 'Aramayı temizle',
                            onAction: _clear,
                          ),
                  );
                }
                return _CustomerListView(
                  state: s,
                  customers: visible,
                  controller: _scroll,
                  onRefresh: () => ref.refresh(customerListProvider.future),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerListView extends ConsumerWidget {
  const _CustomerListView({
    required this.state,
    required this.customers,
    required this.controller,
    required this.onRefresh,
  });

  final CustomerListState state;
  final List<Customer> customers;
  final ScrollController controller;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = CustomerSearch.group(customers);
    final rows = <Object>[
      for (final g in groups) ...[g.letter, ...g.customers],
    ];
    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: rows.length + 1,
        itemBuilder: (context, i) {
          if (i == rows.length) return _Footer(state: state);
          final r = rows[i];
          if (r is String) return _LetterHeader(letter: r);
          return _CustomerTile(customer: r as Customer);
        },
      ),
    );
  }
}

class _LetterHeader extends StatelessWidget {
  const _LetterHeader({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.screenH,
          Space.lg,
          Space.screenH,
          Space.xs,
        ),
        child: Text(
          letter,
          style: context.text.titleSmall?.copyWith(
            color: context.colors.primary,
            fontWeight: TypeTokens.bold,
          ),
        ),
      ),
    );
  }
}

class _CustomerTile extends ConsumerWidget {
  const _CustomerTile({required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = ref.watch(brandProfileProvider).terms;
    final c = customer;
    final hasPhone = (c.phone ?? '').trim().isNotEmpty;
    final stats = c.projectCount > 0
        ? '${c.projectCount} ${terms.job.toLowerCase()}'
        : (c.offerCount > 0
              ? '${c.offerCount} ${terms.offer.toLowerCase()}'
              : '');
    final subtitle = [
      if (hasPhone) PhoneUtil.formatDisplay(c.phone),
      if ((c.region ?? '').isNotEmpty) c.region!,
    ].join(' · ');
    // Eski panel gibi: sözleşme toplamı + ödenen (+ teklif sayısı proje de varsa).
    final money = [
      if (c.totalContracted.isPositive)
        'Sözleşme ${c.totalContracted.format(hideZeroKurus: true)}',
      if (c.totalContracted.isPositive || c.totalPaid.isPositive)
        'Ödenen ${c.totalPaid.format(hideZeroKurus: true)}',
      if (c.projectCount > 0 && c.offerCount > 0)
        '${c.offerCount} ${terms.offer.toLowerCase()}',
    ].join(' · ');
    return Semantics(
      button: true,
      label: '${c.displayName}. $subtitle. $stats',
      excludeSemantics: true,
      onTap: () => context.push(Routes.customer(c.phoneKey)),
      child: InkWell(
        onTap: () => context.push(Routes.customer(c.phoneKey)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.only(
              left: Space.screenH,
              right: Space.xs,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: context.colors.primaryContainer,
                  foregroundColor: context.colors.onPrimaryContainer,
                  child: Text(
                    c.initials,
                    style: context.text.labelLarge?.copyWith(
                      fontWeight: TypeTokens.bold,
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        c.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleMedium,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodyMedium?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      if (money.isNotEmpty)
                        Text(
                          money,
                          key: const Key('customer-money'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (stats.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.sm),
                    child: Text(stats, style: context.text.bodySmall),
                  ),
                if (hasPhone)
                  IconButton(
                    tooltip: '${c.displayName} ara',
                    icon: Icon(Icons.call, color: context.colors.primary),
                    onPressed: () =>
                        ref.read(contactLauncherProvider).call(c.phone!),
                  )
                else
                  const SizedBox(width: Space.md),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});
  final CustomerListState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(customerListProvider.notifier);
    Widget child;
    if (state.loadingMore) {
      child = const SizedBox(
        height: Sizes.minTouch,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (state.loadMoreError != null) {
      child = Column(
        children: [
          Text(state.loadMoreError!.message, textAlign: TextAlign.center),
          const SizedBox(height: Space.sm),
          OutlinedButton.icon(
            onPressed: n.loadMore,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar dene'),
          ),
        ],
      );
    } else if (state.hasMore) {
      child = OutlinedButton(
        onPressed: n.loadMore,
        child: Text(
          'Daha fazla yükle (${state.items.length} / ${state.total})',
        ),
      );
    } else {
      child = Text(
        '${state.total} kayıt',
        textAlign: TextAlign.center,
        style: context.text.bodySmall,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Center(child: child),
    );
  }
}
