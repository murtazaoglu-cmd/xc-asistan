// SAHİBİ: home ajanı. Bugün ekranının durumu: ilk yükleme, çekip yenileme, ARKA PLANDA sessiz
// yenileme (veri ekranda kalır, hata yalnız uyarı şeridi olur) ve hatırlatıcı eylemleri
// (tamamla / yeniden aç / ertele; iyimser güncelleme + hata olursa geri alma).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session.dart';
import '../../../core/util/dates.dart';
import '../../appointments/application/appointment_providers.dart';
import '../data/home_models.dart';
import '../data/home_repository.dart';

@immutable
class HomeData {
  const HomeData(this.summary, this.fetchedAt, {this.refreshError});
  final HomeSummary summary;
  final DateTime fetchedAt;

  /// Son yenileme başarısızsa neden (eski veri hâlâ gösterilir).
  final Object? refreshError;

  HomeData withSummary(HomeSummary s) =>
      HomeData(s, fetchedAt, refreshError: refreshError);
  HomeData withError(Object e) => HomeData(summary, fetchedAt, refreshError: e);
}

/// Arka plan yenileme aralığı (testte null).
final homeAutoRefreshProvider = Provider<Duration?>(
  (ref) => const Duration(minutes: 3),
);

class HomeController extends AsyncNotifier<HomeData> {
  Future<void>? _inFlight;

  HomeRepository get _repo => ref.read(homeRepositoryProvider);

  @override
  Future<HomeData> build() async {
    // Kullanıcı değişirse (çıkış/giriş) yeniden kur: eski kullanıcının verisi kalmasın.
    ref.watch(currentUserProvider.select((u) => u?.id));
    // Randevu ekranlarından gelen her yazma, özeti sessizce yeniler.
    ref.listen(appointmentsMutationProvider, (_, _) => refresh(silent: true));
    final s = await _repo.fetch();
    return HomeData(s, Ist.now());
  }

  /// [silent]: arka plan; başarısızlıkta veri korunur ve `refreshError` işaretlenir.
  /// Aynı anda tek istek çalışır.
  Future<void> refresh({bool silent = false}) {
    final running = _inFlight;
    if (running != null) return running;
    final f = _refresh().whenComplete(() => _inFlight = null);
    return _inFlight = f;
  }

  Future<void> _refresh() async {
    final prev = state.value;
    if (prev == null && state.isLoading) return; // ilk yükleme sürüyor
    try {
      final s = await _repo.fetch();
      if (!ref.mounted) return;
      state = AsyncData(HomeData(s, Ist.now()));
    } catch (e, st) {
      if (!ref.mounted) return;
      state = prev == null ? AsyncError(e, st) : AsyncData(prev.withError(e));
    }
  }

  // ---------------- hatırlatıcılar ----------------

  void _setSummary(HomeSummary s) {
    final cur = state.value;
    if (cur != null) state = AsyncData(cur.withSummary(s));
  }

  HomeSummary _without(HomeSummary s, String id) => s.copyWith(
    remindersToday: s.remindersToday.where((r) => r.id != id).toList(),
    remindersOverdue: s.remindersOverdue.where((r) => r.id != id).toList(),
  );

  /// Hatırlatıcıyı tamamla. Hata olursa liste eski haline döner ve hata yeniden fırlatılır.
  Future<void> completeReminder(HomeReminder r) async {
    final prev = state.value?.summary;
    if (prev == null) return;
    _setSummary(_without(prev, r.id));
    try {
      await _repo.setReminderStatus(r.id, 'tamamlandi');
    } catch (_) {
      if (ref.mounted) _setSummary(prev);
      rethrow;
    }
    unawaited(refresh(silent: true));
  }

  /// "Geri al": tamamlanan hatırlatıcıyı yeniden bekliyor yapar.
  Future<void> reopenReminder(String id) async {
    await _repo.setReminderStatus(id, 'bekliyor');
    await refresh(silent: true);
  }

  /// Ertele: aynı başlıkla yeni hatırlatıcı açar, eskisini tamamlar (sözleşmede `remind_at` PATCH yok).
  Future<void> snoozeReminder(HomeReminder r, DateTime to) async {
    final prev = state.value?.summary;
    if (prev == null) return;
    _setSummary(_without(prev, r.id));
    try {
      await _repo.createReminder(
        title: r.title,
        remindAt: to,
        projectId: r.projectId,
        note: r.note,
      );
      await _repo.setReminderStatus(r.id, 'tamamlandi');
    } catch (_) {
      if (ref.mounted) _setSummary(prev);
      rethrow;
    } finally {
      unawaited(refresh(silent: true));
    }
  }
}

final homeControllerProvider =
    AsyncNotifierProvider.autoDispose<HomeController, HomeData>(
      HomeController.new,
      retry: noProviderRetry,
    );
