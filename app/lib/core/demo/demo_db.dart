// DEMO verisi: sözleşmedeki örnek JSON biçimleriyle, bellekte, "şimdi"ye göre üretilir.
// Hizmet adları sektör nötrdür (Montaj, Bakım, Üretim...). Veri değiştirilebilir (PATCH/POST
// uçları demo rotalarında bunu günceller) ama uygulama kapanınca sıfırlanır.
import '../auth/auth_models.dart';
import '../util/dates.dart';
import '../util/json.dart';

class DemoDb {
  DemoDb({DateTime? now}) : _now = now ?? Ist.now() {
    _seed();
  }

  final DateTime _now;
  int _seq = 100;
  String nextId(String prefix) => '$prefix-${_seq++}';

  late List<JsonMap> offers;
  late List<JsonMap> projects;
  late List<JsonMap> appointments;
  late List<JsonMap> payments;
  late List<JsonMap> expenses;
  late List<JsonMap> materials;
  late List<JsonMap> reminders;

  String iso(DateTime d) => d.toUtc().toIso8601String();

  // ---- Kullanıcılar ----
  UserRole roleForEmail(String email) {
    for (final r in UserRole.values) {
      if (email.contains(r.api)) return r;
    }
    return UserRole.admin;
  }

  JsonMap userFor(UserRole role, {String? email}) => {
    'id': 'u-${role.api}',
    'name': const {
      UserRole.admin: 'Yönetici',
      UserRole.muhasebe: 'Muhasebe',
      UserRole.ortak: 'Ortak Firma',
      UserRole.personel: 'Personel',
      UserRole.saha: 'Saha Ekibi',
    }[role],
    'email': email ?? '${role.api}@demo.com',
    'role': role.api,
  };

  List<JsonMap> team(UserRole role) => role == UserRole.saha
      ? [
          {'id': 'u-admin', 'name': 'Yönetici', 'role': 'admin'},
        ]
      : [
          {'id': 'u-personel', 'name': 'Personel', 'role': 'personel'},
          {'id': 'u-saha', 'name': 'Saha Ekibi', 'role': 'saha'},
        ];

  // ---- Örnek veri ----
  DateTime _at(int dayOffset, int hour, [int minute = 0]) {
    final w = Ist.wall(_now);
    return Ist.fromWall(w.year, w.month, w.day + dayOffset, hour, minute);
  }

  void _seed() {
    JsonMap quote(String offerId, num total) => {
      'id': 'q-$offerId',
      'offer_id': offerId,
      'items': [
        {
          'desc': 'Hizmet bedeli',
          'qty': 1,
          'price': total / 1.2,
          'vatIncluded': false,
        },
      ],
      'subtotal': total / 1.2,
      'tax': total - total / 1.2,
      'total': total,
      'created_at': iso(_at(-2, 11)),
      'sent_via_whatsapp_at': null,
      'sent_via_email_at': iso(_at(-2, 12)),
      'last_send_status': 'kismen',
      'last_send_at': iso(_at(-2, 12)),
      'last_send_error': 'WhatsApp: 24 saat kuralı',
    };

    JsonMap offer(
      int n,
      String name,
      String phone,
      String service,
      String status, {
      num? total,
      String? address,
      double? lat,
      double? lng,
      int ageDays = 1,
    }) {
      final id = 'off-$n';
      final created = _at(-ageDays, 10);
      return {
        'id': id,
        'code': 'OFR-${1000 + n}',
        'tracking_code': 'XCY-DEMO$n',
        'name': name,
        'phone': phone,
        'email': null,
        'service': service,
        'region': 'Bodrum',
        'message': null,
        'notes': null,
        'photo_urls': <String>[],
        'status': status,
        'source': 'website',
        'source_site': 'controlx',
        'owner_id': null,
        'address': address,
        'lat': lat,
        'lng': lng,
        'created_at': iso(created),
        'updated_at': iso(created),
        'quote': total == null ? null : quote(id, total),
        'quote_items': null,
        'quote_total': total,
      };
    }

    offers = [
      offer(
        1,
        'Ayşe Yılmaz',
        '0532 111 22 33',
        'Montaj',
        'Yeni',
        address: 'Konacık Mah. 12 Sok.',
        lat: 37.0344,
        lng: 27.4305,
        ageDays: 0,
      ),
      offer(2, 'Mehmet Kaya', '0533 222 33 44', 'Bakım', 'Yeni', ageDays: 1),
      offer(
        3,
        'Fatma Demir',
        '0534 333 44 55',
        'Üretim',
        'Keşif Planlandı',
        address: 'Yalıkavak Cd. 5',
        ageDays: 2,
      ),
      offer(
        4,
        'Ali Çelik',
        '0535 444 55 66',
        'Montaj',
        'Teklif Verildi',
        total: 12000,
        ageDays: 3,
      ),
      offer(
        5,
        'Zeynep Arslan',
        '0536 555 66 77',
        'Onarım',
        'Kabul Edildi',
        total: 8500,
        ageDays: 6,
      ),
      offer(
        6,
        'Hasan Öztürk',
        '0537 666 77 88',
        'Bakım',
        'Reddedildi',
        total: 3000,
        ageDays: 9,
      ),
    ];

    JsonMap project(
      int n,
      String customer,
      String service,
      String stage,
      num total,
      num paid, {
      int endOffset = 5,
      String? address,
      double? lat,
      double? lng,
    }) {
      return {
        'id': 'prj-$n',
        'code': 'PRJ-${500 + n}',
        'offer_id': n == 1 ? 'off-5' : null,
        'customer_name': customer,
        'customer_phone': '0532 111 22 3$n',
        'service': service,
        'stage': stage,
        'total_amount': total,
        'assigned_team': null,
        'start_date': iso(_at(-10, 12)),
        'end_date': iso(_at(endOffset, 12)),
        'notes': null,
        'owner_id': 'u-admin',
        'address': address,
        'lat': lat,
        'lng': lng,
        'paid_amount': paid,
      };
    }

    projects = [
      project(
        1,
        'Zeynep Arslan',
        'Onarım',
        'Üretim',
        8500,
        4000,
        endOffset: -3,
        address: 'Gümbet Mah. 8 Sok.',
        lat: 37.0301,
        lng: 27.4101,
      ),
      project(
        2,
        'Ahmet Şahin',
        'Montaj',
        'Montaj',
        26000,
        6000,
        address: 'Türkbükü Cd. 3',
        lat: 37.1011,
        lng: 27.4802,
      ),
      project(3, 'Elif Koç', 'Üretim', 'Malzeme Temini', 15000, 0),
      project(
        4,
        'Burak Aydın',
        'Bakım',
        'Tamamlandı',
        2500,
        2500,
        endOffset: -1,
      ),
    ];

    JsonMap appt(
      int n,
      String type,
      DateTime at,
      String status, {
      String? customer,
      String? phone,
      String? address,
      double? lat,
      double? lng,
      String? service,
      String? assigned,
      String? offerId,
      String? projectId,
    }) {
      return {
        'id': 'apt-$n',
        'offer_id': offerId,
        'project_id': projectId,
        'type': type,
        'scheduled_at': iso(at),
        'assigned_user_id': assigned,
        'assigned_user_name': assigned == 'u-saha' ? 'Saha Ekibi' : null,
        'notes': null,
        'status': status,
        'owner_id': 'u-admin',
        'customer_name': customer,
        'customer_phone': phone,
        'address': address,
        'lat': lat,
        'lng': lng,
        'service': service,
        'offer_code': offerId == null ? null : 'OFR-1001',
        'project_code': projectId == null ? null : 'PRJ-501',
        'offer_name': customer,
        'offer_phone': phone,
        'offer_service': service,
        'project_customer': null,
      };
    }

    appointments = [
      appt(
        1,
        'Keşif',
        _at(0, 9, 30),
        'tamamlandı',
        customer: 'Ayşe Yılmaz',
        phone: '0532 111 22 33',
        address: 'Konacık Mah. 12 Sok.',
        lat: 37.0344,
        lng: 27.4305,
        service: 'Montaj',
        assigned: 'u-saha',
        offerId: 'off-1',
      ),
      appt(
        2,
        'Montaj',
        _at(0, 14),
        'beklemede',
        customer: 'Ahmet Şahin',
        phone: '0533 222 33 44',
        address: 'Türkbükü Cd. 3',
        lat: 37.1011,
        lng: 27.4802,
        service: 'Montaj',
        assigned: 'u-saha',
        projectId: 'prj-2',
      ),
      appt(
        3,
        'Bakım',
        _at(0, 16, 30),
        'onaylandı',
        customer: 'Mehmet Kaya',
        phone: '0533 222 33 44',
        address: 'Yalıkavak Cd. 5',
        service: 'Bakım',
        assigned: 'u-admin',
      ),
      appt(
        4,
        'Keşif',
        _at(1, 10),
        'beklemede',
        customer: 'Fatma Demir',
        phone: '0534 333 44 55',
        address: 'Yalıkavak Cd. 5',
        service: 'Üretim',
        assigned: 'u-saha',
        offerId: 'off-3',
      ),
      appt(
        5,
        'Teslim',
        _at(1, 15),
        'beklemede',
        customer: 'Zeynep Arslan',
        phone: '0536 555 66 77',
        service: 'Onarım',
        assigned: 'u-admin',
        projectId: 'prj-1',
      ),
      appt(
        6,
        'Keşif',
        _at(3, 11),
        'beklemede',
        customer: 'Elif Koç',
        phone: '0538 777 88 99',
        service: 'Üretim',
        assigned: 'u-saha',
      ),
      appt(
        7,
        'Montaj',
        _at(-2, 13),
        'tamamlandı',
        customer: 'Burak Aydın',
        phone: '0539 888 99 00',
        service: 'Bakım',
        assigned: 'u-saha',
      ),
    ];

    payments = [
      {
        'id': 'pay-1',
        'project_id': 'prj-1',
        'amount': 4000,
        'method': 'Havale',
        'note': null,
        'paid_at': iso(_at(-8, 12)),
        'owner_id': 'u-admin',
        'customer_name': 'Zeynep Arslan',
        'project_code': 'PRJ-501',
      },
      {
        'id': 'pay-2',
        'project_id': 'prj-2',
        'amount': 6000,
        'method': 'Nakit',
        'note': 'Avans',
        'paid_at': iso(_at(-3, 12)),
        'owner_id': 'u-admin',
        'customer_name': 'Ahmet Şahin',
        'project_code': 'PRJ-502',
      },
      {
        'id': 'pay-3',
        'project_id': 'prj-4',
        'amount': 2500,
        'method': 'Kredi Kartı',
        'note': null,
        'paid_at': iso(_at(-1, 12)),
        'owner_id': 'u-admin',
        'customer_name': 'Burak Aydın',
        'project_code': 'PRJ-504',
      },
    ];

    expenses = [
      {
        'id': 'exp-1',
        'project_id': null,
        'category': 'Dükkan Kirası',
        'amount': 15000,
        'note': null,
        'created_at': iso(_at(-5, 9)),
        'expense_date': iso(_at(-5, 12)),
        'scope': 'dukkan',
        'owner_id': 'u-admin',
        'customer_name': null,
        'project_code': null,
      },
      {
        'id': 'exp-2',
        'project_id': 'prj-2',
        'category': 'Malzeme',
        'amount': 3200.5,
        'note': 'Profil',
        'created_at': iso(_at(-4, 9)),
        'expense_date': iso(_at(-4, 12)),
        'scope': 'genel',
        'owner_id': 'u-admin',
        'customer_name': 'Ahmet Şahin',
        'project_code': 'PRJ-502',
      },
      {
        'id': 'exp-3',
        'project_id': null,
        'category': 'Yakıt',
        'amount': 850,
        'note': null,
        'created_at': iso(_at(-2, 9)),
        'expense_date': iso(_at(-2, 12)),
        'scope': 'genel',
        'owner_id': 'u-admin',
        'customer_name': null,
        'project_code': null,
      },
      {
        'id': 'exp-4',
        'project_id': null,
        'category': 'Ev Kirası',
        'amount': 12000,
        'note': null,
        'created_at': iso(_at(-6, 9)),
        'expense_date': iso(_at(-6, 12)),
        'scope': 'ev',
        'owner_id': 'u-admin',
        'customer_name': null,
        'project_code': null,
      },
    ];

    materials = [
      {
        'id': 'mat-1',
        'name': 'Profil 40x40',
        'unit': 'adet',
        'stock_quantity': 2,
        'low_stock_threshold': 5,
        'note': null,
        'updated_at': iso(_at(-1, 9)),
        'owner_id': 'u-admin',
      },
      {
        'id': 'mat-2',
        'name': 'Vida seti',
        'unit': 'kutu',
        'stock_quantity': 40,
        'low_stock_threshold': 10,
        'note': null,
        'updated_at': iso(_at(-3, 9)),
        'owner_id': 'u-admin',
      },
      {
        'id': 'mat-3',
        'name': 'Boya',
        'unit': 'kg',
        'stock_quantity': 4,
        'low_stock_threshold': 5,
        'note': null,
        'updated_at': iso(_at(-2, 9)),
        'owner_id': 'u-admin',
      },
      {
        'id': 'mat-4',
        'name': 'Conta',
        'unit': 'metre',
        'stock_quantity': 120,
        'low_stock_threshold': 20,
        'note': null,
        'updated_at': iso(_at(-7, 9)),
        'owner_id': 'u-admin',
      },
    ];

    reminders = [
      {
        'id': 'rem-1',
        'project_id': null,
        'title': 'Fatma Hanım\'ı ara',
        'remind_at': iso(_at(0, 17)),
        'note': null,
        'status': 'bekliyor',
        'created_at': iso(_at(-1, 9)),
        'owner_id': 'u-admin',
        'customer_name': null,
        'project_service': null,
        'project_code': null,
        'overdue': false,
      },
      {
        'id': 'rem-2',
        'project_id': 'prj-1',
        'title': 'Teslim öncesi kontrol',
        'remind_at': iso(_at(-1, 10)),
        'note': null,
        'status': 'bekliyor',
        'created_at': iso(_at(-3, 9)),
        'owner_id': 'u-admin',
        'customer_name': 'Zeynep Arslan',
        'project_service': 'Onarım',
        'project_code': 'PRJ-501',
        'overdue': true,
      },
    ];
  }

  // ---- Rol kapsamı ----
  List<JsonMap> appointmentsFor(UserRole role) => role == UserRole.saha
      ? appointments.where((a) => a['assigned_user_id'] == 'u-saha').toList()
      : List.of(appointments);

  /// GET /mobile/home (sözleşme §2): saha → newOffers/offerStats/finance null; personel → finance null.
  JsonMap mobileHome(UserRole? roleOrNull) {
    final role = roleOrNull ?? UserRole.admin;
    final today = Ist.today(_now);
    final tomorrow = Ist.tomorrow(_now);
    bool inRange(JsonMap a, InstantRange r) {
      final t = Ist.tryParse(a['scheduled_at'] as String?);
      return t != null &&
          r.contains(t) &&
          !(a['status'] as String).toLowerCase().startsWith('iptal');
    }

    final all = appointmentsFor(role);
    final todayList = all.where((a) => inRange(a, today)).toList()
      ..sort(
        (a, b) => (a['scheduled_at'] as String).compareTo(
          b['scheduled_at'] as String,
        ),
      );
    final tomorrowList = all.where((a) => inRange(a, tomorrow)).toList()
      ..sort(
        (a, b) => (a['scheduled_at'] as String).compareTo(
          b['scheduled_at'] as String,
        ),
      );

    final newOffers = offers.where((o) => o['status'] == 'Yeni').toList();
    final byStatus = <String, int>{};
    for (final o in offers) {
      byStatus.update(o['status'] as String, (v) => v + 1, ifAbsent: () => 1);
    }
    final overdue = projects.where((p) {
      final end = Ist.tryParse(p['end_date'] as String?);
      return end != null &&
          end.isBefore(today.start) &&
          p['stage'] != 'Tamamlandı';
    }).toList();
    final totalPaid = payments.fold<num>(0, (s, p) => s + (p['amount'] as num));
    final receivable = projects.fold<num>(
      0,
      (s, p) =>
          s +
          ((p['total_amount'] as num) - (p['paid_amount'] as num)).clamp(
            0,
            double.infinity,
          ),
    );
    final low = materials
        .where(
          (m) =>
              (m['stock_quantity'] as num) <= (m['low_stock_threshold'] as num),
        )
        .toList();

    final seesFinance =
        role == UserRole.admin ||
        role == UserRole.muhasebe ||
        role == UserRole.ortak;
    final seesOffers = role != UserRole.saha;
    return {
      'generatedAt': iso(_now),
      'user': {
        'id': 'u-${role.api}',
        'name': userFor(role)['name'],
        'role': role.api,
      },
      'appointments': {'today': todayList, 'tomorrow': tomorrowList},
      'newOffers': seesOffers
          ? {
              'count': newOffers.length,
              'latest': newOffers
                  .take(5)
                  .map(
                    (o) => {
                      for (final k in [
                        'id',
                        'code',
                        'name',
                        'phone',
                        'service',
                        'region',
                        'address',
                        'status',
                        'created_at',
                      ])
                        k: o[k],
                    },
                  )
                  .toList(),
            }
          : null,
      'offerStats': seesOffers
          ? {
              'awaitingQuote':
                  (byStatus['Yeni'] ?? 0) +
                  (byStatus['İncelendi'] ?? 0) +
                  (byStatus['Keşif Planlandı'] ?? 0),
              'awaitingResponse': byStatus['Teklif Verildi'] ?? 0,
              'accepted': byStatus['Kabul Edildi'] ?? 0,
              'rejected': byStatus['Reddedildi'] ?? 0,
              'byStatus': byStatus,
            }
          : null,
      'overdueProjects': {
        'count': overdue.length,
        'items': overdue
            .map(
              (p) => {
                'id': p['id'],
                'code': p['code'],
                'customer_name': p['customer_name'],
                'service': p['service'],
                'stage': p['stage'],
                'end_date': p['end_date'],
                'address': p['address'],
                'days_overdue': Ist.dayDiff(
                  Ist.tryParse(p['end_date'] as String)!,
                  _now,
                ),
              },
            )
            .toList(),
      },
      'finance': seesFinance
          ? {
              'collectedThisWeek': totalPaid,
              'collectedThisMonth': totalPaid,
              'receivableTotal': receivable,
              'receivableProjectCount': projects
                  .where(
                    (p) =>
                        (p['total_amount'] as num) > (p['paid_amount'] as num),
                  )
                  .length,
              'topReceivables': projects
                  .where(
                    (p) =>
                        (p['total_amount'] as num) > (p['paid_amount'] as num),
                  )
                  .map(
                    (p) => {
                      'id': p['id'],
                      'code': p['code'],
                      'customer_name': p['customer_name'],
                      'balance':
                          (p['total_amount'] as num) -
                          (p['paid_amount'] as num),
                    },
                  )
                  .toList(),
            }
          : null,
      'reminders': {
        'today': reminders.where((r) => r['overdue'] != true).toList(),
        'overdue': reminders.where((r) => r['overdue'] == true).toList(),
      },
      'lowStock': {
        'count': low.length,
        'items': low
            .map(
              (m) => {
                'id': m['id'],
                'name': m['name'],
                'unit': m['unit'],
                'stock_quantity': m['stock_quantity'],
                'min_stock': m['low_stock_threshold'],
                'low_stock_threshold': m['low_stock_threshold'],
              },
            )
            .toList(),
      },
    };
  }
}
