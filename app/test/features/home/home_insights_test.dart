import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/auth/auth_models.dart';
import 'package:xc_asistan/core/config/brand_profile.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/appointments/data/appointment_models.dart';
import 'package:xc_asistan/features/home/data/home_insights.dart';
import 'package:xc_asistan/features/home/data/home_models.dart';

import 'home_models_test.dart' show contractSample;

final generic = BrandProfile.generic.terms;
final xc = BrandProfile.xControl.terms;
// 20 Kas 2026 11:00 İstanbul
final now = DateTime.utc(2026, 11, 20, 8);

Appointment appt(
  String id,
  int h, {
  String status = 'beklemede',
  String type = 'Keşif',
  String name = 'Ayşe',
}) => Appointment(
  id: id,
  type: type,
  scheduledAt: Ist.fromWall(2026, 11, 20, h),
  status: status,
  customerName: name,
);

HomeSummary base({
  List<Appointment> today = const [],
  List<Appointment> tomorrow = const [],
  int? newOffers,
  int overdue = 0,
  HomeFinance? finance,
  int low = 0,
  List<HomeReminder> remToday = const [],
  List<HomeReminder> remOverdue = const [],
  HomeOfferStats? stats,
}) => HomeSummary(
  userId: 'u',
  userName: 'Ad',
  generatedAt: now,
  today: today,
  tomorrow: tomorrow,
  newOfferCount: newOffers,
  offerStats: stats,
  overdueProjectCount: overdue,
  overdueProjects: overdue == 0
      ? const []
      : [
          HomeOverdueProject(
            id: 'p',
            customerName: 'X',
            stage: 'Üretim',
            daysOverdue: 3,
          ),
        ],
  finance: finance,
  remindersToday: remToday,
  remindersOverdue: remOverdue,
  lowStockCount: low,
);

List<String> texts(HomeSummary s, UserRole r, [Glossary? t]) => buildInsights(
  s,
  caps: AppCapabilities.forRole(r),
  terms: t ?? generic,
  now: now,
).map((l) => l.text).toList();

void main() {
  test('sakin gün: randevu yok + sakin cümlesi', () {
    final t = texts(base(), UserRole.admin);
    expect(t, contains('Bugün randevu yok.'));
    expect(t.last, contains('Bekleyen başka bir iş'));
  });

  test('bugün sayısı, tamamlanan, sıradaki randevu (sayılar kodla)', () {
    final s = base(
      today: [
        appt('1', 9, status: 'tamamlandı'),
        appt('2', 14, type: 'Montaj', name: 'Ahmet Şahin'),
        appt('3', 16),
        appt('4', 10, status: 'iptal'), // iptal sayılmaz
      ],
      tomorrow: [appt('5', 10), appt('6', 11)],
    );
    final t = texts(s, UserRole.admin);
    expect(t[0], 'Bugün 3 randevu var (1 tamamlandı).');
    expect(t[1], 'Sıradaki: 14:00 Montaj, Ahmet Şahin.');
    expect(t, contains('Yarın 2 randevu var.'));
  });

  test('zamanı geçmiş açık randevu uyarısı', () {
    final s = base(today: [appt('1', 9)]); // 09:00 < şimdi 11:00, beklemede
    final lines = buildInsights(
      s,
      caps: AppCapabilities.forRole(UserRole.admin),
      terms: generic,
      now: now,
    );
    final late = lines.firstWhere((l) => l.kind == InsightKind.late);
    expect(late.text, '1 randevu zamanı geçti ama hâlâ açık.');
    expect(late.level, InsightLevel.urgent);
  });

  test(
    'sözlük terimleri: genel profil "fiyat teklifi", X Control "teklif"',
    () {
      final s = base(
        newOffers: 3,
        stats: const HomeOfferStats(awaitingResponse: 2),
      );
      expect(
        texts(s, UserRole.admin),
        contains('3 yeni fiyat teklifi talebi yanıt bekliyor.'),
      );
      expect(
        texts(s, UserRole.admin, xc),
        contains('3 yeni teklif talebi yanıt bekliyor.'),
      );
      expect(
        texts(s, UserRole.admin),
        contains('2 fiyat teklifi müşterinin yanıtını bekliyor.'),
      );
    },
  );

  test('geciken iş, tahsilat, hatırlatıcı, stok cümleleri', () {
    final s = base(
      overdue: 2,
      finance: HomeFinance.fromJson(
        contractSample()['finance'] as Map<String, dynamic>,
      ),
      low: 3,
      remOverdue: [
        const HomeReminder(
          id: 'r',
          title: 'x',
          status: 'bekliyor',
          overdue: true,
        ),
      ],
      remToday: [
        const HomeReminder(id: 'r2', title: 'y', status: 'bekliyor'),
        const HomeReminder(id: 'r3', title: 'z', status: 'bekliyor'),
      ],
    );
    final t = texts(s, UserRole.admin);
    expect(t, contains('2 iş bitiş tarihini geçti (en çok 3 gün).'));
    expect(t, contains('Toplam alacak ₺7.123 (4 iş).'));
    expect(t, contains('1 gecikmiş hatırlatıcı var.'));
    expect(t, contains('Bugün 2 hatırlatıcı var.'));
    expect(t, contains('3 kalem stok azaldı ya da bitti.'));
    expect(
      t.any((e) => e.contains('sakin') || e.contains('Bekleyen başka')),
      isFalse,
    );
  });

  test(
    'rol: personel finans cümlesi görmez; saha finans/teklif/iş/stok görmez',
    () {
      final fin = HomeFinance.fromJson(
        contractSample()['finance'] as Map<String, dynamic>,
      );
      final s = base(newOffers: 4, overdue: 1, finance: fin, low: 2);
      final personel = texts(s, UserRole.personel);
      expect(personel.any((e) => e.contains('alacak')), isFalse);
      expect(personel.any((e) => e.contains('talebi')), isTrue);
      expect(
        personel.any((e) => e.contains('stok')),
        isFalse,
      ); // personel stok yetkisiz
      final saha = texts(s, UserRole.saha);
      for (final k in ['alacak', 'talebi', 'bitiş tarihini', 'stok']) {
        expect(saha.any((e) => e.contains(k)), isFalse, reason: k);
      }
    },
  );

  test('sıfır sayılar için satır üretilmez', () {
    final s = base(newOffers: 0, overdue: 0, low: 0);
    final t = texts(s, UserRole.admin);
    expect(t.any((e) => e.contains('talebi')), isFalse);
    expect(t.any((e) => e.contains('bitiş')), isFalse);
  });

  test('isQuietDay', () {
    final admin = AppCapabilities.forRole(UserRole.admin);
    expect(isQuietDay(base(), admin), isTrue);
    expect(isQuietDay(base(today: [appt('1', 9)]), admin), isFalse);
    expect(
      isQuietDay(base(today: [appt('1', 9, status: 'iptal')]), admin),
      isTrue,
    );
    expect(isQuietDay(base(newOffers: 1), admin), isFalse);
    // Saha için teklif sayısı önemsiz
    expect(
      isQuietDay(base(newOffers: 1), AppCapabilities.forRole(UserRole.saha)),
      isTrue,
    );
    expect(isQuietDay(base(low: 1), admin), isFalse);
  });

  test('hatırlatıcı erteleme seçenekleri İstanbul 09:00', () {
    final c = reminderSnoozeChoices(now);
    expect(c[0].at, now.add(const Duration(hours: 1)));
    expect(c[1].at, Ist.fromWall(2026, 11, 21, 9));
    expect(c[2].at, Ist.fromWall(2026, 11, 23, 9));
    expect(c[3].at, Ist.fromWall(2026, 11, 27, 9));
  });

  test('fieldJobs iptalleri ayıklar ve saate göre sıralar', () {
    final s = base(
      today: [
        appt('b', 14),
        appt('a', 9),
        appt('c', 10, status: 'iptal'),
      ],
    );
    expect(fieldJobs(s).map((e) => e.id), ['a', 'b']);
  });
}
