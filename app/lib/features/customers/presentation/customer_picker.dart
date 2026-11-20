// "Mevcut müşteriden seç" seçicisi (yeni teklif/proje formları kullanır; yinelenen müşteriyi önler).
// Dışa açık yüz: `customers_public.dart`. Sunucu araması: GET /customers?q= (telefon ≥3 rakam dahil).
//   final c = await showCustomerPicker(context);   // seçilen Customer ya da null
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../../../core/util/phone.dart';
import '../data/customer_models.dart';
import '../data/customers_repository.dart';

Future<Customer?> showCustomerPicker(BuildContext context) =>
    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const CustomerPickerSheet(),
    );

class CustomerPickerSheet extends ConsumerStatefulWidget {
  const CustomerPickerSheet({super.key});

  @override
  ConsumerState<CustomerPickerSheet> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPickerSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<Customer> _items = const [];
  bool _loading = true;
  Object? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final my = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(customersRepositoryProvider)
          .list(query: q, limit: 30);
      if (!mounted || my != _seq) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
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
                key: const Key('customer-picker-search'),
                controller: _ctl,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Ad, telefon ya da bölge ara',
                ),
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => _load(v),
                  );
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const SkeletonList(itemCount: 5)
                  : _error != null
                  ? ErrorState(error: _error, onRetry: () => _load(_ctl.text))
                  : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.person_search_outlined,
                      title: 'Müşteri bulunamadı',
                      message: 'Aramayı değiştirin ya da yeni müşteri olarak devam edin.',
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final c = _items[i];
                        final sub = [
                          if ((c.phone ?? '').isNotEmpty)
                            PhoneUtil.formatDisplay(c.phone),
                          if ((c.region ?? '').isNotEmpty) c.region!,
                        ].join(' · ');
                        return ListTile(
                          key: Key('pick-${c.phoneKey}'),
                          minTileHeight: Sizes.minTouch + 8,
                          leading: CircleAvatar(child: Text(c.initials)),
                          title: Text(c.displayName),
                          subtitle: sub.isEmpty ? null : Text(sub),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
