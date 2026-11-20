// Kullanıcı işlemleri: alt sayfa + onay diyalogları. Engeller (kendini silme, son yönetici...)
// düğmeyi pasifleştirir ve nedenini altyazıda yazar; sunucu yine her şeyi denetler.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/ui.dart';
import '../data/settings_repository.dart';
import '../data/user_models.dart';
import '../data/user_rules.dart';
import 'password_field.dart';

enum UserAction { resetPassword, changeRole, toggleActive, delete }

Future<void> showUserActions(
  BuildContext context,
  WidgetRef ref, {
  required ManagedUser user,
  required List<ManagedUser> all,
  required UserRole actor,
  required String selfId,
}) async {
  final edit = ref.read(userEditEnabledProvider);
  final resetBlock = UserRules.resetBlock(
    actor: actor,
    selfId: selfId,
    target: user,
  );
  final deleteBlock = UserRules.deleteBlock(
    actor: actor,
    selfId: selfId,
    target: user,
    all: all,
  );
  final roleBlock = UserRules.roleChangeBlock(
    actor: actor,
    selfId: selfId,
    target: user,
    all: all,
  );
  final activeBlock = UserRules.activeToggleBlock(
    actor: actor,
    selfId: selfId,
    target: user,
    all: all,
  );

  final action = await showModalBottomSheet<UserAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.name, style: ctx.text.titleMedium),
                  Text(
                    '${user.email} · ${user.roleLabel}',
                    style: ctx.text.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.sm),
            _tile(
              ctx,
              Icons.lock_reset,
              'Şifreyi sıfırla',
              resetBlock,
              UserAction.resetPassword,
            ),
            if (edit && actor == UserRole.admin) ...[
              _tile(
                ctx,
                Icons.swap_horiz,
                'Rolü değiştir',
                roleBlock,
                UserAction.changeRole,
              ),
              _tile(
                ctx,
                user.active
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                user.active ? 'Pasifleştir' : 'Aktifleştir',
                activeBlock,
                UserAction.toggleActive,
              ),
            ],
            _tile(
              ctx,
              Icons.delete_outline,
              'Kullanıcıyı sil',
              deleteBlock,
              UserAction.delete,
              destructive: true,
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case UserAction.resetPassword:
      await _resetPassword(context, ref, user);
    case UserAction.changeRole:
      await _changeRole(context, ref, user, all, actor);
    case UserAction.toggleActive:
      await _toggleActive(context, ref, user);
    case UserAction.delete:
      await _delete(context, ref, user);
  }
}

Widget _tile(
  BuildContext ctx,
  IconData icon,
  String title,
  String? block,
  UserAction action, {
  bool destructive = false,
}) {
  final color = block != null
      ? ctx.colors.onSurface.withValues(alpha: 0.38)
      : (destructive ? ctx.colors.error : null);
  return ListTile(
    key: Key('action-${action.name}'),
    enabled: block == null,
    minTileHeight: Sizes.minTouch,
    leading: Icon(icon, color: color),
    title: Text(title, style: TextStyle(color: color)),
    subtitle: block == null ? null : Text(block),
    onTap: block == null ? () => Navigator.of(ctx).pop(action) : null,
  );
}

Future<void> _delete(
  BuildContext context,
  WidgetRef ref,
  ManagedUser user,
) async {
  final ok = await ConfirmDialog.show(
    context,
    title: '${user.name} silinsin mi?',
    message: 'Hesap kalıcı olarak silinir ve oturumları kapanır. Kullanıcının finans kayıtları size devredilir. Bu işlem geri alınamaz.',
    confirmLabel: 'Sil',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(settingsRepositoryProvider).deleteUser(user.id);
    ref.invalidate(usersProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${user.name} silindi.')));
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(UserErrors.message(e, op: 'delete'))),
      );
  }
}

Future<void> _toggleActive(
  BuildContext context,
  WidgetRef ref,
  ManagedUser user,
) async {
  final next = !user.active;
  final ok = await ConfirmDialog.show(
    context,
    title: next
        ? '${user.name} aktifleştirilsin mi?'
        : '${user.name} pasifleştirilsin mi?',
    message: next ? 'Kullanıcı yeniden giriş yapabilir.' : 'Kullanıcı giriş yapamaz ve açık oturumları kapanır. Kayıtları silinmez.',
    confirmLabel: next ? 'Aktifleştir' : 'Pasifleştir',
    destructive: !next,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(settingsRepositoryProvider)
        .updateUser(user.id, UserPatch(active: next));
    ref.invalidate(usersProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            next ? 'Kullanıcı aktif.' : 'Kullanıcı pasifleştirildi.',
          ),
        ),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(UserErrors.message(e, op: 'edit-unsupported'))),
      );
  }
}

Future<void> _changeRole(
  BuildContext context,
  WidgetRef ref,
  ManagedUser user,
  List<ManagedUser> all,
  UserRole actor,
) async {
  final roles = UserRules.assignableRoles(actor);
  final picked = await showDialog<UserRole>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('${user.name} için rol'),
      children: [
        for (final r in roles)
          SimpleDialogOption(
            key: Key('pick-role-${r.api}'),
            onPressed: () => Navigator.of(ctx).pop(r),
            child: Row(
              children: [
                Icon(
                  r == user.role
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                const SizedBox(width: Space.md),
                Expanded(child: Text(r.label)),
              ],
            ),
          ),
      ],
    ),
  );
  if (picked == null || picked == user.role || !context.mounted) return;
  final ok = await ConfirmDialog.show(
    context,
    title: 'Rol ${picked.label} olarak değişsin mi?',
    message:
        '${user.name} yeni rolün yetkileriyle çalışır; değişiklik hemen yansır.',
    confirmLabel: 'Değiştir',
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(settingsRepositoryProvider)
        .updateUser(user.id, UserPatch(role: picked));
    ref.invalidate(usersProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Rol güncellendi: ${picked.label}.')),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(UserErrors.message(e, op: 'edit-unsupported'))),
      );
  }
}

Future<void> _resetPassword(
  BuildContext context,
  WidgetRef ref,
  ManagedUser user,
) async {
  final pwd = await showDialog<String>(
    context: context,
    builder: (_) => _ResetPasswordDialog(user: user),
  );
  if (pwd == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(settingsRepositoryProvider).resetPassword(user.id, pwd);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${user.name} için şifre sıfırlandı; açık oturumları kapandı.',
          ),
        ),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(UserErrors.message(e))));
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.user});
  final ManagedUser user;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _pwd = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _pwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.user.name}: şifreyi sıfırla'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Yeni şifre kaydedilir ve kullanıcının tüm oturumları kapanır.',
            ),
            const SizedBox(height: Space.md),
            PasswordField(
              key: const Key('reset-password'),
              controller: _pwd,
              label: 'Yeni şifre',
              autofocus: true,
              validator: UserValidators.password,
            ),
            const SizedBox(height: Space.md),
            PasswordField(
              key: const Key('reset-confirm'),
              controller: _confirm,
              label: 'Yeni şifre (tekrar)',
              textInputAction: TextInputAction.done,
              validator: (v) => UserValidators.confirm(v, _pwd.text),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        key: const Key('reset-submit'),
        onPressed: () {
          if (_form.currentState?.validate() ?? false) {
            Navigator.of(context).pop(_pwd.text);
          }
        },
        child: const Text('Şifreyi sıfırla'),
      ),
    ],
  );
}
