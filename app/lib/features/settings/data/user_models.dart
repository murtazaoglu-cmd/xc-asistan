// Kullanıcı yönetimi modelleri (sözleşme §12 "Kullanıcılar"). Elle yazılmış, null-güvenli.
import 'package:flutter/foundation.dart';

import '../../../core/auth/auth_models.dart';
import '../../../core/util/json.dart';

/// `GET /users` satırı: `{id,name,email,role,created_at}`. `active`/`created_by` sunucu
/// (henüz yok, bkz. CORE-REQUESTS) eklerse okunur; yoksa aktif sayılır.
@immutable
class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.name,
    required this.email,
    required this.roleRaw,
    this.createdAt,
    this.active = true,
    this.createdBy,
  });

  final String id;
  final String name;
  final String email;

  /// Sunucudaki ham rol (bilinmeyen rol de olduğu gibi gösterilir).
  final String roleRaw;
  final DateTime? createdAt;
  final bool active;
  final String? createdBy;

  UserRole? get role => UserRole.fromApi(roleRaw);
  String get roleLabel =>
      role?.label ?? (roleRaw.isEmpty ? 'Rol yok' : roleRaw);
  bool get isAdmin => role == UserRole.admin;

  String get initial {
    final t = name.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  factory ManagedUser.fromJson(JsonMap j) => ManagedUser(
    id: j.strOr('id'),
    name: j.strOr('name'),
    email: j.strOr('email'),
    roleRaw: j.strOr('role'),
    createdAt: j.dateTime('created_at'),
    active: j.boolOr('active', true),
    createdBy: j.strOrNull('created_by'),
  );

  ManagedUser copyWith({String? name, String? roleRaw, bool? active}) =>
      ManagedUser(
        id: id,
        name: name ?? this.name,
        email: email,
        roleRaw: roleRaw ?? this.roleRaw,
        createdAt: createdAt,
        active: active ?? this.active,
        createdBy: createdBy,
      );
}

/// `POST /users` gövdesi (doğrulanmış değerler).
@immutable
class NewUserInput {
  const NewUserInput({
    required this.name,
    required this.email,
    required this.password,
    required this.role,
    this.leaderId,
  });

  final String name;
  final String email;
  final String password;
  final UserRole role;

  /// Bağlı olduğu ortak firma (sunucu desteklerse; bkz. CORE-REQUESTS backend isteği).
  final String? leaderId;

  JsonMap toJson() => {
    'name': name.trim(),
    'email': email.trim().toLowerCase(),
    'password': password,
    'role': role.api,
    if (leaderId != null && leaderId!.isNotEmpty) 'leader_id': leaderId,
  };
}

/// `PATCH /users/:id` (sunucuda HENÜZ YOK; yalnız `userEditEnabled` açıkken kullanılır).
@immutable
class UserPatch {
  const UserPatch({this.name, this.role, this.active});
  final String? name;
  final UserRole? role;
  final bool? active;

  JsonMap toJson() => {
    if (name != null) 'name': name!.trim(),
    if (role != null) 'role': role!.api,
    if (active != null) 'active': active,
  };
}
