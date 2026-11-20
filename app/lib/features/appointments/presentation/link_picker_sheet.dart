// SAHİBİ: appointments ajanı. Randevu formundaki "Kime?" seçicisi: teklif / proje / müşteri
// araması (sözleşme §6: ?q ≤100 karakter, ?limit). Sorgu 350 ms beklenip gönderilir.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/session.dart';
import '../../../core/config/brand_profile.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../application/appointment_providers.dart';
import '../data/appointment_models.dart';
import '../data/appointments_repository.dart';

@immutable
class LinkSearch {
  const LinkSearch(this.kind, this.query);
  final LinkKind kind;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is LinkSearch && other.kind == kind && other.query == query;
  @override
  int get hashCode => Object.hash(kind, query);
}

final linkSearchProvider = FutureProvider.autoDispose
    .family<List<LinkCandidate>, LinkSearch>(
      (ref, s) =>
          ref.watch(appointmentsRepositoryProvider).search(s.kind, s.query),
      retry: noProviderRetry,
    );

class LinkPickerSheet extends ConsumerStatefulWidget {
  const LinkPickerSheet({super.key});

  static Future<LinkCandidate?> show(BuildContext context) =>
      showModalBottomSheet<LinkCandidate>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => const LinkPickerSheet(),
      );

  @override
  ConsumerState<LinkPickerSheet> createState() => _LinkPickerSheetState();
}

class _LinkPickerSheetState extends ConsumerState<LinkPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _q = '';
  LinkKind? _kind;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _q = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    final terms = ref.watch(brandProfileProvider).terms;
    final kinds = <(LinkKind, String, IconData)>[
      if (caps?.offers ?? false)
        (LinkKind.offer, terms.offer, Icons.request_quote_outlined),
      if (caps?.projects ?? false)
        (LinkKind.project, terms.job, Icons.work_outline),
      if (caps?.customers ?? false)
        (LinkKind.customer, terms.customer, Icons.person_outline),
    ];
    final kind = _kind ?? (kinds.isEmpty ? null : kinds.first.$1);
    final height = MediaQuery.sizeOf(context).height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Ad, telefon ya da kod ile ara',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Temizle',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _q = '');
                          },
                        ),
                ),
              ),
            ),
            if (kinds.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: Space.sm,
                    children: [
                      for (final k in kinds)
                        ChoiceChip(
                          avatar: Icon(k.$3, size: Sizes.iconSm),
                          label: Text(k.$2),
                          selected: kind == k.$1,
                          onSelected: (_) => setState(() => _kind = k.$1),
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: Space.sm),
            Expanded(
              child: kind == null
                  ? const EmptyState(
                      title: 'Seçilecek kayıt yok',
                      message: 'Bu rol için arama kapalı. Ad ve telefonu elle girebilirsiniz.',
                    )
                  : _results(kind),
            ),
          ],
        ),
      ),
    );
  }

  Widget _results(LinkKind kind) {
    final search = LinkSearch(kind, _q);
    final value = ref.watch(linkSearchProvider(search));
    return value.when(
      loading: () => const SkeletonList(itemCount: 5, itemHeight: 56),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(linkSearchProvider(search)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.search_off,
            title: 'Sonuç bulunamadı',
            message: _q.isEmpty
                ? 'Henüz kayıt yok.'
                : 'Başka bir ad, telefon ya da kod deneyin.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(bottom: Space.xl),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final c = items[i];
            return ListTile(
              minTileHeight: Sizes.minTouch + 8,
              leading: Icon(switch (c.kind) {
                LinkKind.offer => Icons.request_quote_outlined,
                LinkKind.project => Icons.work_outline,
                LinkKind.customer => Icons.person_outline,
              }),
              title: Text(c.title),
              subtitle: c.subtitle == null ? null : Text(c.subtitle!),
              onTap: () => Navigator.of(context).pop(c),
            );
          },
        );
      },
    );
  }
}
