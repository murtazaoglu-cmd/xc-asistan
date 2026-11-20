// Küçük, gizli olmayan kullanıcı tercihleri (shared_preferences). Jeton BURAYA yazılmaz.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode, TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';

/// Tipli anahtarlar. Yeni tercih eklerken buraya ekleyin.
class AppPrefs {
  AppPrefs(this._p);
  final SharedPreferences _p;

  static const _kBiometric = 'pref.biometric_lock';
  static const _kTheme = 'pref.theme_mode';
  static const _kLastEmail = 'pref.last_email';
  static const _kMorningOn = 'pref.notif.morning.on';
  static const _kMorningAt = 'pref.notif.morning.at';
  static const _kEveningOn = 'pref.notif.evening.on';
  static const _kEveningAt = 'pref.notif.evening.at';
  static const _kNotifAsked = 'pref.notif.permission_asked';

  bool get biometricLock => _p.getBool(_kBiometric) ?? false;
  Future<void> setBiometricLock(bool v) => _p.setBool(_kBiometric, v);

  ThemeMode get themeMode {
    switch (_p.getString(_kTheme)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode m) => _p.setString(_kTheme, m.name);

  String? get lastEmail => _p.getString(_kLastEmail);
  Future<void> setLastEmail(String? v) =>
      v == null ? _p.remove(_kLastEmail) : _p.setString(_kLastEmail, v);

  // Günlük bildirimler (varsayılan: sabah 08:00, akşam 19:00, ikisi de açık).
  bool get morningEnabled => _p.getBool(_kMorningOn) ?? true;
  Future<void> setMorningEnabled(bool v) => _p.setBool(_kMorningOn, v);
  TimeOfDay get morningTime =>
      _readTime(_kMorningAt, const TimeOfDay(hour: 8, minute: 0));
  Future<void> setMorningTime(TimeOfDay t) => _writeTime(_kMorningAt, t);

  bool get eveningEnabled => _p.getBool(_kEveningOn) ?? true;
  Future<void> setEveningEnabled(bool v) => _p.setBool(_kEveningOn, v);
  TimeOfDay get eveningTime =>
      _readTime(_kEveningAt, const TimeOfDay(hour: 19, minute: 0));
  Future<void> setEveningTime(TimeOfDay t) => _writeTime(_kEveningAt, t);

  /// Bildirim izni ilk girişte bir kez istenir.
  bool get notificationPermissionAsked => _p.getBool(_kNotifAsked) ?? false;
  Future<void> setNotificationPermissionAsked(bool v) =>
      _p.setBool(_kNotifAsked, v);

  TimeOfDay _readTime(String key, TimeOfDay fallback) {
    final v = _p.getString(key);
    if (v == null) return fallback;
    final parts = v.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59)
      return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _writeTime(String key, TimeOfDay t) =>
      _p.setString(key, '${t.hour}:${t.minute}');

  /// Çıkışta kullanıcıya özel tercihleri temizlemek için (cihaz tercihleri kalır).
  @visibleForTesting
  SharedPreferences get raw => _p;
}
