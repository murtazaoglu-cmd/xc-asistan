// SAHİBİ: home ajanı. GET /mobile/home yanıtının (sözleşme §2) elle yazılmış, null-güvenli modeli.
// Rol kapsamı: saha için newOffers/offerStats/finance null; personel için finance null.
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import '../../appointments/data/appointment_models.dart';

/// Bugün/Yarın bölümlerindeki randevu satırı, randevular özelliğinin modelidir.
typedef HomeAppointment = Appointment;

@immutable
class HomeNewOffer {
  const HomeNewOffer({
    required this.id,
    required this.name,
    required this.status,
    this.code,
    this.phone,
    this.service,
    this.region,
    this.address,
    this.createdAt,
  });
  final String id;
  final String name;
  final String status;
  final String? code;
  final String? phone;
  final String? service;
  final String? region;
  final String? address;
  final DateTime? createdAt;

  factory HomeNewOffer.fromJson(JsonMap j) => HomeNewOffer(
    id: j.strOr('id'),
    name: j.strOrNull('name') ?? '-',
    status: j.strOr('status', 'Yeni'),
    code: j.strOrNull('code'),
    phone: j.strOrNull('phone'),
    service: j.strOrNull('service'),
    region: j.strOrNull('region'),
    address: j.strOrNull('address'),
    createdAt: j.dateTime('created_at'),
  );
}

@immutable
class HomeOverdueProject {
  const HomeOverdueProject({
    required this.id,
    required this.customerName,
    required this.stage,
    this.code,
    this.service,
    this.endDate,
    this.address,
    this.daysOverdue = 0,
  });
  final String id;
  final String customerName;
  final String stage;
  final String? code;
  final String? service;
  final DateTime? endDate;
  final String? address;
  final int daysOverdue;

  factory HomeOverdueProject.fromJson(JsonMap j) => HomeOverdueProject(
    id: j.strOr('id'),
    customerName: j.strOrNull('customer_name') ?? '-',
    stage: j.strOr('stage'),
    code: j.strOrNull('code'),
    service: j.strOrNull('service'),
    endDate: j.dateTime('end_date'),
    address: j.strOrNull('address'),
    daysOverdue: j.intOr('days_overdue'),
  );
}

@immutable
class HomeReminder {
  const HomeReminder({
    required this.id,
    required this.title,
    required this.status,
    this.remindAt,
    this.note,
    this.projectId,
    this.customerName,
    this.projectCode,
    this.overdue = false,
  });
  final String id;
  final String title;
  final String status;
  final DateTime? remindAt;
  final String? note;
  final String? projectId;
  final String? customerName;
  final String? projectCode;
  final bool overdue;

  factory HomeReminder.fromJson(JsonMap j) => HomeReminder(
    id: j.strOr('id'),
    title: j.strOrNull('title') ?? 'Hatırlatıcı',
    status: j.strOr('status', 'bekliyor'),
    remindAt: j.dateTime('remind_at'),
    note: j.strOrNull('note'),
    projectId: j.strOrNull('project_id'),
    customerName: j.strOrNull('customer_name'),
    projectCode: j.strOrNull('project_code'),
    overdue: j.boolOr('overdue'),
  );
}

@immutable
class HomeLowStockItem {
  const HomeLowStockItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.stockQuantity,
    required this.minStock,
  });
  final String id;
  final String name;
  final String unit;
  final num stockQuantity;
  final num minStock;

  factory HomeLowStockItem.fromJson(JsonMap j) => HomeLowStockItem(
    id: j.strOr('id'),
    name: j.strOrNull('name') ?? '-',
    unit: j.strOr('unit', 'adet'),
    stockQuantity: j.doubleOrNull('stock_quantity') ?? 0,
    minStock:
        j.doubleOrNull('min_stock') ??
        j.doubleOrNull('low_stock_threshold') ??
        0,
  );
}

@immutable
class HomeReceivable {
  const HomeReceivable({
    required this.id,
    required this.customerName,
    required this.balance,
    this.code,
  });
  final String id;
  final String customerName;
  final Money balance;
  final String? code;

  factory HomeReceivable.fromJson(JsonMap j) => HomeReceivable(
    id: j.strOr('id'),
    customerName: j.strOrNull('customer_name') ?? '-',
    balance: j.money('balance'),
    code: j.strOrNull('code'),
  );
}

@immutable
class HomeFinance {
  const HomeFinance({
    required this.collectedThisWeek,
    required this.collectedThisMonth,
    required this.receivableTotal,
    this.receivableProjectCount = 0,
    this.topReceivables = const [],
  });
  final Money collectedThisWeek;
  final Money collectedThisMonth;
  final Money receivableTotal;
  final int receivableProjectCount;
  final List<HomeReceivable> topReceivables;

  factory HomeFinance.fromJson(JsonMap j) {
    final top = j.list('topReceivables').map(HomeReceivable.fromJson).toList();
    return HomeFinance(
      collectedThisWeek: j.money('collectedThisWeek'),
      collectedThisMonth: j.money('collectedThisMonth'),
      receivableTotal: j.money('receivableTotal'),
      receivableProjectCount:
          j.intOrNull('receivableProjectCount') ?? top.length,
      topReceivables: top,
    );
  }
}

@immutable
class HomeOfferStats {
  const HomeOfferStats({
    this.awaitingQuote = 0,
    this.awaitingResponse = 0,
    this.accepted = 0,
    this.rejected = 0,
  });
  final int awaitingQuote;
  final int awaitingResponse;
  final int accepted;
  final int rejected;

  factory HomeOfferStats.fromJson(JsonMap j) => HomeOfferStats(
    awaitingQuote: j.intOr('awaitingQuote'),
    awaitingResponse: j.intOr('awaitingResponse'),
    accepted: j.intOr('accepted'),
    rejected: j.intOr('rejected'),
  );
}

@immutable
class HomeSummary {
  const HomeSummary({
    required this.userId,
    required this.userName,
    required this.generatedAt,
    required this.today,
    required this.tomorrow,
    this.newOfferCount,
    this.newOffers = const [],
    this.offerStats,
    this.overdueProjectCount = 0,
    this.overdueProjects = const [],
    this.finance,
    this.remindersToday = const [],
    this.remindersOverdue = const [],
    this.lowStockCount = 0,
    this.lowStock = const [],
  });

  final String userId;
  final String userName;
  final DateTime? generatedAt;
  final List<Appointment> today;
  final List<Appointment> tomorrow;

  /// saha için null (bölüm yok).
  final int? newOfferCount;
  final List<HomeNewOffer> newOffers;
  final HomeOfferStats? offerStats;
  final int overdueProjectCount;
  final List<HomeOverdueProject> overdueProjects;

  /// Yalnız admin/muhasebe/ortak için; aksi null.
  final HomeFinance? finance;
  final List<HomeReminder> remindersToday;
  final List<HomeReminder> remindersOverdue;
  final int lowStockCount;
  final List<HomeLowStockItem> lowStock;

  int get reminderCount => remindersToday.length + remindersOverdue.length;

  factory HomeSummary.fromJson(JsonMap j) {
    final appts = j.mapOrNull('appointments');
    final reminders = j.mapOrNull('reminders');
    final fin = j.mapOrNull('finance');
    final offers = j.mapOrNull('newOffers');
    final stats = j.mapOrNull('offerStats');
    final overdue = j.mapOrNull('overdueProjects');
    final stock = j.mapOrNull('lowStock');
    final user = asJsonMap(j['user']);
    final overdueItems = (overdue?.list('items') ?? const <JsonMap>[])
        .map(HomeOverdueProject.fromJson)
        .toList();
    final stockItems = (stock?.list('items') ?? const <JsonMap>[])
        .map(HomeLowStockItem.fromJson)
        .toList();
    return HomeSummary(
      userId: user.strOr('id'),
      userName: user.strOr('name'),
      generatedAt: j.dateTime('generatedAt'),
      today: (appts?.list('today') ?? const <JsonMap>[])
          .map(Appointment.fromJson)
          .toList(),
      tomorrow: (appts?.list('tomorrow') ?? const <JsonMap>[])
          .map(Appointment.fromJson)
          .toList(),
      newOfferCount: offers?.intOr('count'),
      newOffers: (offers?.list('latest') ?? const <JsonMap>[])
          .map(HomeNewOffer.fromJson)
          .toList(),
      offerStats: stats == null ? null : HomeOfferStats.fromJson(stats),
      overdueProjectCount: overdue?.intOrNull('count') ?? overdueItems.length,
      overdueProjects: overdueItems,
      finance: fin == null ? null : HomeFinance.fromJson(fin),
      remindersToday: (reminders?.list('today') ?? const <JsonMap>[])
          .map(HomeReminder.fromJson)
          .toList(),
      remindersOverdue: (reminders?.list('overdue') ?? const <JsonMap>[])
          .map(HomeReminder.fromJson)
          .toList(),
      lowStockCount: stock?.intOrNull('count') ?? stockItems.length,
      lowStock: stockItems,
    );
  }

  HomeSummary copyWith({
    List<HomeReminder>? remindersToday,
    List<HomeReminder>? remindersOverdue,
  }) => HomeSummary(
    userId: userId,
    userName: userName,
    generatedAt: generatedAt,
    today: today,
    tomorrow: tomorrow,
    newOfferCount: newOfferCount,
    newOffers: newOffers,
    offerStats: offerStats,
    overdueProjectCount: overdueProjectCount,
    overdueProjects: overdueProjects,
    finance: finance,
    remindersToday: remindersToday ?? this.remindersToday,
    remindersOverdue: remindersOverdue ?? this.remindersOverdue,
    lowStockCount: lowStockCount,
    lowStock: lowStock,
  );
}
