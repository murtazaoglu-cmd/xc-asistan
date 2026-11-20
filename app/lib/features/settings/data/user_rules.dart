// Kullanıcı yönetimi kuralları ve form doğrulaması (saf mantık; testlenir).
// Asıl yetki sunucudadır; bunlar arayüzün ikinci savunması ve açıklayıcı mesajlardır.
import 'dart:convert';

import '../../../core/auth/auth_models.dart';
import 'user_models.dart';

abstract final class UserRules {
  /// Kullanıcı yönetimi: yalnız yönetici ve iş ortağı (muhasebe/personel/saha yok).
  static bool canManage(UserRole role) =>
      role == UserRole.admin || role == UserRole.ortak;

  /// Oluşturulabilecek roller: yönetici hepsi; ortak yalnız saha/personel.
  static List<UserRole> assignableRoles(UserRole actor) => switch (actor) {
    UserRole.admin => UserRole.values,
    UserRole.ortak => const [UserRole.personel, UserRole.saha],
    _ => const [],
  };

  static int adminCount(Iterable<ManagedUser> all, {bool activeOnly = false}) =>
      all.where((u) => u.isAdmin && (!activeOnly || u.active)).length;

  /// Silme engeli (mesaj) ya da null (silinebilir).
  static String? deleteBlock({
    required UserRole actor,
    required String selfId,
    required ManagedUser target,
    required Iterable<ManagedUser> all,
  }) {
    if (!canManage(actor)) return 'Kullanıcı silme yetkiniz yok.';
    if (target.id == selfId) return 'Kendi hesabınızı silemezsiniz.';
    if (target.isAdmin && adminCount(all) <= 1) {
      return 'Son yönetici silinemez. Önce başka bir yönetici ekleyin.';
    }
    if (actor == UserRole.ortak &&
        !assignableRoles(actor).contains(target.role)) {
      return 'Yalnızca kendi oluşturduğunuz kullanıcıları silebilirsiniz.';
    }
    return null;
  }

  /// Başkasının şifresini sıfırlama engeli. Kendi şifreniz için "Şifremi değiştir" kullanılır.
  static String? resetBlock({
    required UserRole actor,
    required String selfId,
    required ManagedUser target,
  }) {
    if (!canManage(actor)) return 'Şifre sıfırlama yetkiniz yok.';
    if (target.id == selfId) {
      return 'Kendi şifreniz için Ayarlar > Şifremi değiştir kullanın.';
    }
    if (actor == UserRole.ortak &&
        !assignableRoles(actor).contains(target.role)) {
      return 'Yalnızca kendi oluşturduğunuz kullanıcıların şifresini sıfırlayabilirsiniz.';
    }
    return null;
  }

  /// Rol değiştirme engeli (yalnız yönetici; kendi rolünü ve son yöneticiyi değiştiremez).
  static String? roleChangeBlock({
    required UserRole actor,
    required String selfId,
    required ManagedUser target,
    required Iterable<ManagedUser> all,
  }) {
    if (actor != UserRole.admin)
      return 'Rol değiştirmek için yönetici olmalısınız.';
    if (target.id == selfId) return 'Kendi rolünüzü değiştiremezsiniz.';
    if (target.isAdmin && adminCount(all, activeOnly: true) <= 1) {
      return 'Son yöneticinin rolü değiştirilemez.';
    }
    return null;
  }

  /// Aktif/pasif engeli (yönetici; kendini ve son aktif yöneticiyi pasifleştiremez).
  static String? activeToggleBlock({
    required UserRole actor,
    required String selfId,
    required ManagedUser target,
    required Iterable<ManagedUser> all,
  }) {
    if (actor != UserRole.admin)
      return 'Yalnızca yönetici durumu değiştirebilir.';
    if (target.id == selfId) return 'Kendi hesabınızı pasifleştiremezsiniz.';
    if (target.active &&
        target.isAdmin &&
        adminCount(all, activeOnly: true) <= 1) {
      return 'Son aktif yönetici pasifleştirilemez.';
    }
    return null;
  }
}

abstract final class UserValidators {
  /// Önerilen alt sınır (sözleşme: sunucu en az 6, mobil formda 8 önerilir).
  static const int passwordMin = 8;
  static const int passwordMaxBytes = 72;

  static const Set<String> _common = {
    '123456',
    '1234567',
    '12345678',
    '123456789',
    '1234567890',
    'password',
    'password1',
    'qwerty',
    'qwerty123',
    'qwertyuiop',
    '111111',
    '000000',
    '12341234',
    'abc12345',
    'iloveyou',
    'admin123',
    'sifre123',
    'parola123',
  };

  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  static String? name(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'Adı girin.';
    if (s.length > 100) return 'Ad en çok 100 karakter olabilir.';
    return null;
  }

  static String? email(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'E-posta adresini girin.';
    if (s.length > 200 || !_email.hasMatch(s)) {
      return 'Geçerli bir e-posta girin (örn. ad@firma.com).';
    }
    return null;
  }

  static String? password(String? raw) {
    final s = raw ?? '';
    if (s.isEmpty) return 'Şifreyi girin.';
    if (s.length < passwordMin)
      return 'Şifre en az $passwordMin karakter olmalı.';
    if (utf8.encode(s).length > passwordMaxBytes) {
      return 'Şifre çok uzun (en çok $passwordMaxBytes bayt).';
    }
    if (_common.contains(s.toLowerCase())) {
      return 'Bu şifre çok yaygın. Daha zor tahmin edilir bir şifre seçin.';
    }
    return null;
  }

  static String? confirm(String? raw, String password) {
    if ((raw ?? '').isEmpty) return 'Şifreyi tekrar girin.';
    if (raw != password) return 'Şifreler aynı değil.';
    return null;
  }

  /// Şifre değiştirme: yeni şifre eskisiyle aynı olamaz.
  static String? newPassword(String? raw, String current) {
    final e = password(raw);
    if (e != null) return e;
    if (raw == current) return 'Yeni şifre mevcut şifreyle aynı olamaz.';
    return null;
  }

  static String? currentPassword(String? raw) =>
      (raw ?? '').isEmpty ? 'Mevcut şifrenizi girin.' : null;

  static String? role(UserRole? r, UserRole actor) {
    if (r == null) return 'Bir rol seçin.';
    if (!UserRules.assignableRoles(actor).contains(r)) {
      return 'Bu rolü atama yetkiniz yok.';
    }
    return null;
  }
}

/// Rol açıklamaları (form ve liste).
abstract final class RoleInfo {
  static String describe(UserRole r) => switch (r) {
    UserRole.admin => 'Her şeyi görür ve yönetir; kullanıcı ekler.',
    UserRole.muhasebe => 'Para, fatura ve KDV; kullanıcı yönetimi yok.',
    UserRole.ortak =>
      'Ayrı firma: yalnız kendi verisini görür, kendi ekibini yönetir.',
    UserRole.personel => 'Teklif ve işler; genel gider/sabit gider yok.',
    UserRole.saha =>
      'Yalnız kendine atanan randevu ve işler; para bilgisi yok.',
  };
}
