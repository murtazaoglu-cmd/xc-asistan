// Kullanıcılar (yalnız yönetici / iş ortağı). Liste + arama + rol süzgeci; dokun → işlemler:
// şifre sıfırla, (sunucu desteklerse) rol değiştir / pasifleştir, sil. Her yıkıcı işlem onay ister.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/auth/session.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/settings_repository.dart';
import '../data/user_models.dart';
import 'user_actions.dart';

/// Arama + rol süzgeci (saf; testlenir).
List<ManagedUser> filterUsers(
  List<ManagedUser> all, {
  String query = '',
  UserRole? role,
}) {
  final q = query.trim().toLowerCase();
  return all.where((u) {
    if (role != null && u.role != role) return false;
    if (q.isEmpty) return true;
    return u.name.toLowerCase().contains(q) ||
        u.email.toLowerCase().contains(q);
  }).toList();
}

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  UserRole? _role;

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    if (caps == null || !caps.showUsers) {
      return const AppScaffold(
        title: 'Kullanıcılar',
        body: EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüm için yetkiniz yok',
          message: 'Kullanıcıları yalnızca yönetici ve iş ortağı yönetebilir.',
        ),
      );
    }
    final selfId = ref.watch(currentUserProvider)?.id ?? '';
    final async = ref.watch(usersProvider);
    return AppScaffold(
      title: 'Kullanıcılar',
      wideLayout: true,
      actions: [
        IconButton(
          tooltip: 'Yeni kullanıcı',
          icon: const Icon(Icons.person_add_alt_1_outlined),
          onPressed: () => context.push('${Routes.users}/new'),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-user'),
        onPressed: () => context.push('${Routes.users}/new'),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Yeni kullanıcı'),
      ),
      body: PullToRefresh(
        onRefresh: () async {
          ref.invalidate(usersProvider);
          try {
            await ref.read(usersProvider.future);
          } catch (_) {}
        },
        child: AsyncValueView<List<ManagedUser>>(
          value: async,
          onRetry: () => ref.invalidate(usersProvider),
          isEmpty: (l) => l.isEmpty,
          empty: EmptyState(
            icon: Icons.group_outlined,
            title: 'Henüz kullanıcı yok',
            message: 'Personel, saha ya da ortak hesabı ekleyin.',
            actionLabel: 'Yeni kullanıcı',
            onAction: () => context.push('${Routes.users}/new'),
          ),
          data: (all) {
            final roles = [
              for (final r in UserRole.values)
                if (all.any((u) => u.role == r)) r,
            ];
            final shown = filterUsers(all, query: _query, role: _role);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.lg,
                Space.lg,
                96,
              ),
              children: [
                TextField(
                  key: const Key('users-search'),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Ad veya e-posta ara',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                if (roles.length > 1) ...[
                  const SizedBox(height: Space.md),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      ChoiceChip(
                        label: Text('Tümü (${all.length})'),
                        selected: _role == null,
                        onSelected: (_) => setState(() => _role = null),
                      ),
                      for (final r in roles)
                        ChoiceChip(
                          label: Text(r.label),
                          selected: _role == r,
                          onSelected: (_) => setState(() => _role = r),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: Space.md),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(Space.xl),
                    child: Center(child: Text('Aramaya uyan kullanıcı yok.')),
                  )
                else if (ShellController.maybeOf(context)?.wide ?? false)
                  DataTableView<ManagedUser>(
                    key: const Key('users-table'),
                    items: shown,
                    title: 'Kullanıcılar',
                    fileName: 'kullanicilar',
                    initialSort: 0,
                    rowSemanticLabel: (u) => '${u.name}, ${u.roleLabel}',
                    onRowTap: (u) => showUserActions(
                      context,
                      ref,
                      user: u,
                      all: all,
                      actor: caps.role,
                      selfId: selfId,
                    ),
                    columns: [
                      DataColumnSpec<ManagedUser>(
                        label: 'Ad',
                        flex: 2,
                        text: (u) =>
                            u.id == selfId ? '${u.name} (Siz)' : u.name,
                        sortKey: (u) => u.name,
                      ),
                      DataColumnSpec<ManagedUser>(
                        label: 'E-posta',
                        flex: 3,
                        text: (u) => u.email,
                        sortKey: (u) => u.email,
                      ),
                      DataColumnSpec<ManagedUser>(
                        label: 'Rol',
                        width: 150,
                        text: (u) => u.roleLabel,
                        sortKey: (u) => u.roleLabel,
                        cell: (context, u) => StatusChip(
                          label: u.roleLabel,
                          tone: u.isAdmin
                              ? StatusTone.accent
                              : StatusTone.neutral,
                          icon: Icons.badge_outlined,
                        ),
                      ),
                      DataColumnSpec<ManagedUser>(
                        label: 'Durum',
                        width: 110,
                        text: (u) => u.active ? 'Aktif' : 'Pasif',
                        sortKey: (u) => u.active,
                      ),
                      DataColumnSpec<ManagedUser>(
                        label: 'Katılım',
                        width: 120,
                        text: (u) => u.createdAt == null
                            ? ''
                            : _UserTile._date(u.createdAt!),
                        sortKey: (u) => u.createdAt,
                      ),
                    ],
                    trailingBuilder: (context, u) =>
                        const Icon(Icons.more_vert, size: Sizes.iconSm),
                    trailingWidth: 40,
                  )
                else
                  for (final u in shown)
                    _UserTile(
                      user: u,
                      isSelf: u.id == selfId,
                      onTap: () => showUserActions(
                        context,
                        ref,
                        user: u,
                        all: all,
                        actor: caps.role,
                        selfId: selfId,
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.isSelf,
    required this.onTap,
  });
  final ManagedUser user;
  final bool isSelf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Sizes.minTouch + 16),
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    user.initial,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSelf ? '${user.name} (Siz)' : user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.titleSmall,
                      ),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (user.createdAt != null)
                        Text(
                          'Katılım: ${_date(user.createdAt!)}',
                          style: context.text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: Space.xs),
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.xs,
                        children: [
                          StatusChip(
                            label: user.roleLabel,
                            tone: user.isAdmin
                                ? StatusTone.accent
                                : StatusTone.neutral,
                            icon: Icons.badge_outlined,
                          ),
                          if (!user.active)
                            const StatusChip(
                              label: 'Pasif',
                              tone: StatusTone.warning,
                              icon: Icons.pause_circle_outline,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_vert),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}.${l.month.toString().padLeft(2, '0')}.${l.year}';
  }
}
