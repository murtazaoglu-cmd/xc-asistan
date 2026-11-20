import 'package:material_ui/material_ui.dart';

/// Aşağı çekip yenileme kalıbı.
/// - Kaydırılabilir [child] (ListView vb.) için: `PullToRefresh(onRefresh: ..., child: ListView(...))`.
/// - Boş/hata gibi kaydırılamayan durumlar için `PullToRefresh.fill(...)`: içerik her zaman
///   kaydırılabilir olur, böylece boş ekranda da çekip yenilenebilir.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  factory PullToRefresh.fill({
    Key? key,
    required Future<void> Function() onRefresh,
    required Widget child,
  }) => PullToRefresh(
    key: key,
    onRefresh: onRefresh,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
    ),
  );

  @override
  Widget build(BuildContext context) =>
      RefreshIndicator(onRefresh: onRefresh, child: child);
}
