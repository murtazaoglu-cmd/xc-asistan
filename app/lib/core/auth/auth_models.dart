// Oturum modelleri (elle yazılmış, null-güvenli). Sözleşme §1.
import 'package:flutter/foundation.dart';

import '../util/json.dart';

enum UserRole {
  admin('admin', 'Yönetici'),
  muhasebe('muhasebe', 'Muhasebe'),
  ortak('ortak', 'İş ortağı'),
  personel('personel', 'Personel'),
  saha('saha', 'Saha');

  const UserRole(this.api, this.label);
  final String api;
  final String label;

  static UserRole? fromApi(String? v) {
    for (final r in values) {
      if (r.api == v) return r;
    }
    return null;
  }
}

@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;

  /// Bilinmeyen rol gelirse en kısıtlı rol (saha) varsayılır: güvenli taraf.
  final UserRole role;

  factory AuthUser.fromJson(JsonMap j) => AuthUser(
    id: j.strOr('id'),
    name: j.strOr('name'),
    email: j.strOr('email'),
    role: UserRole.fromApi(j.str('role')) ?? UserRole.saha,
  );

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'role': role.api,
  };
}

/// Lider / ekip üyesi (kısa kullanıcı bilgisi).
@immutable
class UserRef {
  const UserRef({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final String role;

  factory UserRef.fromJson(JsonMap j) =>
      UserRef(id: j.strOr('id'), name: j.strOr('name'), role: j.strOr('role'));

  JsonMap toJson() => {'id': id, 'name': name, 'role': role};
}

/// Sunucunun `capabilities` alanı: YALNIZCA menü göstermek içindir; yetki her
/// uçta sunucuda denetlenir. Eksik gelirse role göre güvenli varsayılan kullanılır.
@immutable
class AppCapabilities {
  const AppCapabilities({
    required this.role,
    this.offers = false,
    this.quotes = false,
    this.projects = false,
    this.customers = false,
    this.finance = false,
    this.homeFinance = false,
    this.materials = false,
    this.manageUsers = false,
    this.appointmentsCreate = false,
  });

  final UserRole role;
  final bool offers;
  final bool quotes;
  final bool projects;
  final bool customers;
  final bool finance;
  final bool homeFinance;
  final bool materials;
  final bool manageUsers;
  final bool appointmentsCreate;

  /// Saha rolü: SADE kabuk (yalnız Bugün + Randevular).
  bool get isField => role == UserRole.saha;

  // ---- Menü görünürlüğü (tek doğruluk kaynağı: nav_items.dart ve router korumaları bunu okur) ----
  bool get showJobs => !isField && (offers || projects);
  bool get showAssistant => !isField;
  bool get showCustomers => !isField && customers;
  bool get showFinance => !isField && finance;
  bool get showStock => !isField && materials;
  bool get showReports => !isField;

  /// Kullanıcı yönetimi: yalnız yönetici ve iş ortağı (sunucu `manageUsers` ile birlikte).
  bool get showUsers =>
      manageUsers && (role == UserRole.admin || role == UserRole.ortak);
  bool get showInvoicesVat => !isField && finance && role != UserRole.personel;

  factory AppCapabilities.fromJson(JsonMap? j, UserRole role) {
    if (j == null) return AppCapabilities.forRole(role);
    return AppCapabilities(
      role: role,
      offers: j.boolOr('offers'),
      quotes: j.boolOr('quotes'),
      projects: j.boolOr('projects'),
      customers: j.boolOr('customers'),
      finance: j.boolOr('finance'),
      homeFinance: j.boolOr('homeFinance'),
      materials: j.boolOr('materials'),
      manageUsers: j.boolOr('manageUsers'),
      appointmentsCreate: j.boolOr('appointmentsCreate'),
    );
  }

  /// Sunucu `capabilities` göndermezse (ör. çevrimdışı önbellek eskiyse) rol varsayılanı.
  factory AppCapabilities.forRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.ortak:
      case UserRole.muhasebe:
        return AppCapabilities(
          role: role,
          offers: true,
          quotes: true,
          projects: true,
          customers: true,
          finance: true,
          homeFinance: true,
          materials: true,
          manageUsers: role != UserRole.muhasebe,
          appointmentsCreate: true,
        );
      case UserRole.personel:
        return const AppCapabilities(
          role: UserRole.personel,
          offers: true,
          projects: true,
          finance: true,
          appointmentsCreate: true,
        );
      case UserRole.saha:
        return const AppCapabilities(role: UserRole.saha);
    }
  }

  JsonMap toJson() => {
    'offers': offers,
    'quotes': quotes,
    'projects': projects,
    'customers': customers,
    'finance': finance,
    'homeFinance': homeFinance,
    'materials': materials,
    'manageUsers': manageUsers,
    'appointmentsCreate': appointmentsCreate,
  };
}

/// `GET /auth/me` yanıtı.
@immutable
class MeResponse {
  const MeResponse({
    required this.user,
    required this.capabilities,
    this.leader,
    this.team = const [],
    this.sessionClient,
    this.sessionExpiresAt,
  });

  final AuthUser user;
  final AppCapabilities capabilities;
  final UserRef? leader;
  final List<UserRef> team;
  final String? sessionClient;
  final DateTime? sessionExpiresAt;

  factory MeResponse.fromJson(JsonMap j) {
    final user = AuthUser.fromJson(asJsonMap(j['user']));
    final leader = j.mapOrNull('leader');
    final session = j.mapOrNull('session');
    return MeResponse(
      user: user,
      capabilities: AppCapabilities.fromJson(
        j.mapOrNull('capabilities'),
        user.role,
      ),
      leader: leader == null ? null : UserRef.fromJson(leader),
      team: j.list('team').map(UserRef.fromJson).toList(),
      sessionClient: session?.str('client'),
      sessionExpiresAt: session?.dateTime('expiresAt'),
    );
  }

  /// Girişten hemen sonra /auth/me alınamazsa kullanıcıdan türetilir.
  factory MeResponse.fromUser(AuthUser user, {DateTime? expiresAt}) =>
      MeResponse(
        user: user,
        capabilities: AppCapabilities.forRole(user.role),
        sessionExpiresAt: expiresAt,
      );

  JsonMap toJson() => {
    'user': user.toJson(),
    'leader': leader?.toJson(),
    'team': team.map((e) => e.toJson()).toList(),
    'capabilities': capabilities.toJson(),
    'session': {
      'client': sessionClient,
      'expiresAt': sessionExpiresAt?.toIso8601String(),
    },
  };
}

/// `POST /auth/login` ve `POST /auth/refresh` yanıtı.
@immutable
class TokenResult {
  const TokenResult({required this.token, this.expiresAt, this.user});
  final String token;
  final DateTime? expiresAt;
  final AuthUser? user;

  factory TokenResult.fromJson(JsonMap j) {
    final u = j.mapOrNull('user');
    return TokenResult(
      token: j.strOr('token'),
      expiresAt: j.dateTime('expiresAt'),
      user: u == null ? null : AuthUser.fromJson(u),
    );
  }
}
