// Hızlı git / komut paleti: `/` ya da Ctrl+K (Mac: Cmd+K) ile açılır. Ekran adı yazıp Enter'a basın;
// yukarı/aşağı oklarla seçin, Esc kapatır. Mobilde de çalışır (donanım klavyesi varsa).
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

class PaletteEntry {
  const PaletteEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.onSelect,
    this.hint = '',
    this.keywords = '',
  });
  final String id;
  final String label;
  final String hint;
  final IconData icon;

  /// Arama için ek sözcükler.
  final String keywords;
  final VoidCallback onSelect;
}

String _fold(String s) => s
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ç', 'c')
    .replaceAll('ğ', 'g')
    .replaceAll('ö', 'o')
    .replaceAll('ş', 's')
    .replaceAll('ü', 'u')
    .replaceAll('i̇', 'i');

/// Arama süzgeci (Türkçe harf duyarsız; saf, testlenir).
List<PaletteEntry> filterPalette(List<PaletteEntry> all, String query) {
  final q = _fold(query.trim());
  if (q.isEmpty) return all;
  return [
    for (final e in all)
      if (_fold('${e.label} ${e.keywords} ${e.hint}').contains(q)) e,
  ];
}

Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteEntry> entries,
) => showDialog<void>(
  context: context,
  barrierLabel: 'Hızlı git',
  builder: (_) => _PaletteDialog(entries: entries),
);

class _PaletteDialog extends StatefulWidget {
  const _PaletteDialog({required this.entries});
  final List<PaletteEntry> entries;

  @override
  State<_PaletteDialog> createState() => _PaletteDialogState();
}

class _PaletteDialogState extends State<_PaletteDialog> {
  final _ctrl = TextEditingController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<PaletteEntry> get _shown => filterPalette(widget.entries, _ctrl.text);

  void _run(PaletteEntry e) {
    Navigator.of(context).pop();
    e.onSelect();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (_index >= shown.length) _index = shown.isEmpty ? 0 : shown.length - 1;
    final c = context.colors;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      insetPadding: const EdgeInsets.all(Space.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 480),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(
              () => _index = shown.isEmpty ? 0 : (_index + 1) % shown.length,
            ),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(
              () => _index = shown.isEmpty
                  ? 0
                  : (_index - 1 + shown.length) % shown.length,
            ),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: TextField(
                  key: const ValueKey('palette-input'),
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.go,
                  decoration: const InputDecoration(
                    hintText: 'Nereye gitmek istiyorsunuz?',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() => _index = 0),
                  onSubmitted: (_) {
                    if (shown.isNotEmpty) _run(shown[_index]);
                  },
                ),
              ),
              Flexible(
                child: shown.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          'Eşleşen ekran yok.',
                          style: context.text.bodyMedium?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: shown.length,
                        itemBuilder: (context, i) {
                          final e = shown[i];
                          return ListTile(
                            key: ValueKey('palette-${e.id}'),
                            selected: i == _index,
                            selectedTileColor: c.primaryContainer.withValues(
                              alpha: 0.5,
                            ),
                            leading: Icon(e.icon),
                            title: Text(e.label),
                            subtitle: e.hint.isEmpty ? null : Text(e.hint),
                            onTap: () => _run(e),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.xs,
                  Space.lg,
                  Space.md,
                ),
                child: Row(
                  children: [
                    Text(
                      '↑↓ seç · Enter aç · Esc kapat',
                      style: context.text.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
