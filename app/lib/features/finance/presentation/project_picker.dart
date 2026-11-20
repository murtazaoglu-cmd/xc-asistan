// Aramalı proje seçici (alt sayfa). Satırda proje kodu + müşteri adı görünür; ham UUID ASLA.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/finance_models.dart';
import '../data/finance_providers.dart';

/// Seçici sonucu: [project] null ise "projeye bağlı değil" seçildi.
class ProjectPick {
  const ProjectPick(this.project);
  final ProjectRef? project;
}

Future<ProjectPick?> showProjectPicker(
  BuildContext context, {
  bool allowNone = false,
  String noneLabel = 'Projeye bağlı değil',
  String title = 'Proje seçin',
}) {
  return showModalBottomSheet<ProjectPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _ProjectPickerSheet(
      allowNone: allowNone,
      noneLabel: noneLabel,
      title: title,
    ),
  );
}

class _ProjectPickerSheet extends ConsumerStatefulWidget {
  const _ProjectPickerSheet({
    required this.allowNone,
    required this.noneLabel,
    required this.title,
  });
  final bool allowNone;
  final String noneLabel;
  final String title;

  @override
  ConsumerState<_ProjectPickerSheet> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_ProjectPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  /// Boş aramada kalan bakiyesi olanlar üstte.
  List<ProjectRef> _order(List<ProjectRef> l) {
    if (_query.isNotEmpty) return l;
    final withBalance = l.where((p) => p.remaining.isPositive).toList()
      ..sort((a, b) => b.remaining.compareTo(a.remaining));
    final rest = l.where((p) => !p.remaining.isPositive);
    return [...withBalance, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(projectSearchProvider(_query));
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                0,
                Space.lg,
                Space.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: context.text.titleLarge),
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: _ctrl,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    decoration: InputDecoration(
                      hintText: 'Proje kodu veya müşteri adı ara',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _ctrl.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Aramayı temizle',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _ctrl.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.allowNone)
              ListTile(
                minTileHeight: Sizes.minTouch + 8,
                leading: const Icon(Icons.link_off),
                title: Text(widget.noneLabel),
                onTap: () => Navigator.of(context).pop(const ProjectPick(null)),
              ),
            Expanded(
              child: AsyncValueView<List<ProjectRef>>(
                value: async,
                onRetry: () => ref.invalidate(projectSearchProvider),
                loading: const SkeletonList(itemCount: 5, itemHeight: 64),
                isEmpty: (l) => l.isEmpty,
                empty: EmptyState(
                  icon: Icons.search_off,
                  title: _query.isEmpty
                      ? 'Henüz proje yok'
                      : 'Eşleşen proje bulunamadı',
                  message: _query.isEmpty
                      ? null
                      : 'Başka bir kod ya da ad deneyin.',
                ),
                data: (list) {
                  final items = _order(list);
                  return ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _ProjectTile(
                      project: items[i],
                      onTap: () =>
                          Navigator.of(context).pop(ProjectPick(items[i])),
                    ),
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

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.onTap});
  final ProjectRef project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = project.remaining;
    return ListTile(
      minTileHeight: Sizes.minTouch + 12,
      title: Text(project.displayLabel, maxLines: 2),
      subtitle: (project.service ?? '').isEmpty ? null : Text(project.service!),
      trailing: remaining.isPositive
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Kalan', style: context.text.bodySmall),
                MoneyText(
                  remaining,
                  hideZeroKurus: true,
                  style: context.text.titleSmall,
                ),
              ],
            )
          : Text(
              'Ödendi',
              style: context.text.bodySmall?.copyWith(
                color: context.xc.success,
              ),
            ),
      onTap: onTap,
    );
  }
}
