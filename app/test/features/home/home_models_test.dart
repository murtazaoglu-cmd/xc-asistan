import 'package:flutter_test/flutter_test.dart';
import 'package:xc_asistan/core/util/dates.dart';
import 'package:xc_asistan/features/home/data/home_models.dart';

/// Sözleşme §2 örnek yanıtı (kısaltılmış).
Map<String, dynamic> contractSample() => {
  'generatedAt': '2026-11-20T16:11:11.781Z',
  'user': {'id': 'u1', 'name': 'Admin', 'role': 'admin'},
  'appointments': {
    'today': [
      {
        'id': 'a1',
        'type': 'Keşif',
        'scheduled_at': '2026-11-20T16:41:10.435Z',
        'status': 'beklemede',
        'customer_name': 'Ayşe Yılmaz',
        'customer_phone': '0532 111 22 33',
        'address': 'Konacık Mah. 12 Sok.',
        'lat': 37.0344,
        'lng': 27.4305,
        'service': 'Pergola',
        'assigned_user_id': 'u2',
        'assigned_user_name': 'Saha1',
        'notes': null,
        'offer_id': 'o1',
        'project_id': null,
        'offer_code': 'OFR-1001',
        'project_code': null,
        'owner_id': 'u1',
      },
    ],
    'tomorrow': [],
  },
  'newOffers': {
    'count': 6,
    'latest': [
      {
        'id': 'o1',
        'code': 'OFR-1013',
        'name': 'Mehmet',
        'phone': '0533',
        'service': 'Cam',
        'region': 'Bodrum',
        'address': null,
        'status': 'Yeni',
        'created_at': '2026-11-20T10:00:00.000Z',
      },
    ],
  },
  'offerStats': {
    'awaitingQuote': 6,
    'awaitingResponse': 5,
    'accepted': 2,
    'rejected': 0,
    'byStatus': {'Yeni': 6},
  },
  'overdueProjects': {
    'count': 1,
    'items': [
      {
        'id': 'p1',
        'code': 'PRJ-503',
        'customer_name': 'Zeynep',
        'service': 'Kapı',
        'stage': 'Üretim',
        'end_date': '2026-11-17T09:00:00.000Z',
        'address': null,
        'days_overdue': 3,
      },
    ],
  },
  'finance': {
    'collectedThisWeek': 1177,
    'collectedThisMonth': 1177.5,
    'receivableTotal': 7123,
    'receivableProjectCount': 4,
    'topReceivables': [
      {'id': 'p1', 'code': 'PRJ-501', 'customer_name': 'Ali', 'balance': 5100},
    ],
  },
  'reminders': {
    'today': [
      {
        'id': 'r1',
        'title': 'Ara',
        'remind_at': '2026-11-20T14:00:00.000Z',
        'note': null,
        'status': 'bekliyor',
        'project_id': null,
        'customer_name': null,
        'project_code': null,
        'overdue': false,
      },
    ],
    'overdue': [
      {
        'id': 'r2',
        'title': 'Geç',
        'remind_at': '2026-11-18T14:00:00.000Z',
        'status': 'bekliyor',
        'overdue': true,
      },
    ],
  },
  'lowStock': {
    'count': 2,
    'items': [
      {
        'id': 'm1',
        'name': 'Profil 40x40',
        'unit': 'adet',
        'stock_quantity': 2,
        'min_stock': 5,
        'low_stock_threshold': 5,
      },
    ],
  },
};

void main() {
  test('sözleşme §2 örneğini okur', () {
    final s = HomeSummary.fromJson(contractSample());
    expect(s.userName, 'Admin');
    expect(s.userId, 'u1');
    expect(s.generatedAt, DateTime.utc(2026, 11, 20, 16, 11, 11, 781));
    expect(s.today.single.displayName, 'Ayşe Yılmaz');
    expect(s.today.single.assignedUserName, 'Saha1');
    expect(s.tomorrow, isEmpty);
    expect(s.newOfferCount, 6);
    expect(s.newOffers.single.code, 'OFR-1013');
    expect(s.offerStats!.awaitingResponse, 5);
    expect(s.overdueProjectCount, 1);
    expect(s.overdueProjects.single.daysOverdue, 3);
    expect(s.overdueProjects.single.endDate, DateTime.utc(2026, 11, 17, 9));
    expect(s.finance!.receivableTotal.kurus, 712300);
    expect(s.finance!.collectedThisMonth.kurus, 117750);
    expect(s.finance!.receivableProjectCount, 4);
    expect(s.finance!.topReceivables.single.balance.kurus, 510000);
    expect(s.remindersToday.single.title, 'Ara');
    expect(s.remindersOverdue.single.overdue, isTrue);
    expect(s.reminderCount, 2);
    expect(s.lowStockCount, 2);
    expect(s.lowStock.single.minStock, 5);
  });

  test('saha: newOffers/offerStats/finance null → alanlar null', () {
    final j = contractSample()
      ..['newOffers'] = null
      ..['offerStats'] = null
      ..['finance'] = null;
    final s = HomeSummary.fromJson(j);
    expect(s.newOfferCount, isNull);
    expect(s.offerStats, isNull);
    expect(s.finance, isNull);
    expect(s.newOffers, isEmpty);
  });

  test('boş/eksik gövdede çökmez, sıfır değerler', () {
    final s = HomeSummary.fromJson(const {});
    expect(s.userName, '');
    expect(s.today, isEmpty);
    expect(s.overdueProjectCount, 0);
    expect(s.lowStockCount, 0);
    expect(s.reminderCount, 0);
    expect(s.finance, isNull);
  });

  test('yanlış tipli bölümler yok sayılır', () {
    final s = HomeSummary.fromJson({
      'appointments': 'x',
      'reminders': [1, 2],
      'lowStock': {'count': 'üç', 'items': 'yok'},
      'overdueProjects': {
        'items': [
          1,
          null,
          {'id': 'p'},
        ],
      },
    });
    expect(s.today, isEmpty);
    expect(s.lowStockCount, 0);
    expect(s.overdueProjects.single.id, 'p');
    expect(s.overdueProjectCount, 1);
  });

  test('stok: min_stock yoksa low_stock_threshold kullanılır', () {
    final it = HomeLowStockItem.fromJson({
      'id': 'm',
      'name': 'Boya',
      'stock_quantity': '1.5',
      'low_stock_threshold': 5,
    });
    expect(it.stockQuantity, 1.5);
    expect(it.minStock, 5);
    expect(it.unit, 'adet');
  });

  test('hatırlatıcı başlıksızsa varsayılan başlık', () {
    final r = HomeReminder.fromJson({'id': 'x'});
    expect(r.title, 'Hatırlatıcı');
    expect(r.status, 'bekliyor');
    expect(r.remindAt, isNull);
  });

  test('copyWith yalnız hatırlatıcıları değiştirir', () {
    final s = HomeSummary.fromJson(contractSample());
    final c = s.copyWith(remindersToday: const [], remindersOverdue: const []);
    expect(c.reminderCount, 0);
    expect(c.today, s.today);
    expect(c.finance, same(s.finance));
    expect(Ist.wall(s.generatedAt!).hour, 19); // İstanbul +3
  });
}
