// Para (finans) modelleri: sözleşme §4-5 satırlarına birebir. Elle yazılmış, null-güvenli.
// Para alanları [Money] (kuruş), tarihler UTC an. Ham UUID ekranda GÖSTERİLMEZ: görünen ad
// için `displayLabel` kullanılır (proje kodu + müşteri adı).
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

/// Ödeme yöntemi: sunucuda sabit 3 değer, ileride çek/senet gelebilir (invoices_vat).
/// Bu yüzden satırda ham metin saklanır; bilinmeyen değer olduğu gibi gösterilir.
@immutable
class Payment {
  const Payment({
    required this.id,
    required this.projectId,
    required this.amount,
    required this.method,
    this.note,
    this.paidAt,
    this.ownerId,
    this.customerName,
    this.projectCode,
  });

  final String id;
  final String projectId;
  final Money amount;

  /// Sunucudaki yöntem değeri ("Havale", "Nakit", "Kredi Kartı" ...).
  final String method;
  final String? note;
  final DateTime? paidAt;
  final String? ownerId;
  final String? customerName;
  final String? projectCode;

  PaymentMethod? get methodEnum => PaymentMethod.fromApi(method);
  String get methodLabel => method.trim().isEmpty ? 'Yöntem yok' : method;

  /// "PRJ-501 · Zeynep Arslan". Kod/ad yoksa genel bir yedek metin (UUID ASLA).
  String get projectLabel =>
      FinanceLabels.project(code: projectCode, customer: customerName);

  factory Payment.fromJson(JsonMap j) => Payment(
    id: j.strOr('id'),
    projectId: j.strOr('project_id'),
    amount: j.money('amount'),
    method: j.strOr('method'),
    note: j.strOrNull('note'),
    paidAt: j.dateTime('paid_at'),
    ownerId: j.strOrNull('owner_id'),
    customerName: j.strOrNull('customer_name'),
    projectCode: j.strOrNull('project_code'),
  );

  Payment copyWith({String? customerName, String? projectCode}) => Payment(
    id: id,
    projectId: projectId,
    amount: amount,
    method: method,
    note: note,
    paidAt: paidAt,
    ownerId: ownerId,
    customerName: customerName ?? this.customerName,
    projectCode: projectCode ?? this.projectCode,
  );
}

/// Gider kapsamı ARAYÜZ karşılığı (eski panelle AYNI adlar): sunucudaki `ev` → Ev,
/// `dukkan` → Dükkan, `genel` → İşletme (sunucu `genel`'i panelde "İşletme" diye gösterir).
/// `ev` işletme kârına DAHİL DEĞİLDİR; dükkan + işletme kâra girer.
/// Not: enum adları eski kodla uyum için korundu (personal = ev, business = dukkan, general = genel).
enum ScopeView {
  personal(ExpenseScope.ev, 'Ev', 'Ev Giderleri'),
  business(ExpenseScope.dukkan, 'Dükkan', 'Dükkan Giderleri'),
  general(ExpenseScope.genel, 'İşletme', 'İşletme Giderleri');

  const ScopeView(this.scope, this.label, this.groupLabel);
  final ExpenseScope scope;

  /// Kullanıcıya görünen kısa ad: Ev / Dükkan / İşletme.
  final String label;

  /// Toplam satırı/kart başlığı: Ev Giderleri / Dükkan Giderleri / İşletme Giderleri.
  final String groupLabel;

  String get api => scope.api;

  /// `ev` dışındakiler işletme giderdir (dukkan + genel).
  bool get isBusiness => this != ScopeView.personal;

  /// Bilinmeyen/boş değer sunucuda varsayılan `genel` gibi davranır.
  static ScopeView fromApi(String? v) {
    for (final e in values) {
      if (e.api == v) return e;
    }
    return ScopeView.general;
  }
}

@immutable
class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.scopeRaw,
    this.projectId,
    this.note,
    this.createdAt,
    this.expenseDate,
    this.ownerId,
    this.customerName,
    this.projectCode,
  });

  final String id;
  final String? projectId;
  final String category;
  final Money amount;
  final String? note;
  final DateTime? createdAt;
  final DateTime? expenseDate;

  /// Sunucudaki ham kapsam (`ev|dukkan|genel`).
  final String scopeRaw;
  final String? ownerId;
  final String? customerName;
  final String? projectCode;

  ScopeView get scope => ScopeView.fromApi(scopeRaw);

  /// Kişisel (ev) gider: işletme kârına katılmaz.
  bool get isPersonal => scope == ScopeView.personal;

  /// Gider tarihi; yoksa kayıt zamanı.
  DateTime? get date => expenseDate ?? createdAt;

  bool get hasProject => (projectId ?? '').isNotEmpty;

  String get projectLabel =>
      FinanceLabels.project(code: projectCode, customer: customerName);

  factory Expense.fromJson(JsonMap j) => Expense(
    id: j.strOr('id'),
    projectId: j.strOrNull('project_id'),
    category: j.strOr('category'),
    amount: j.money('amount'),
    note: j.strOrNull('note'),
    createdAt: j.dateTime('created_at'),
    expenseDate: j.dateTime('expense_date'),
    scopeRaw: j.strOr('scope', 'genel'),
    ownerId: j.strOrNull('owner_id'),
    customerName: j.strOrNull('customer_name'),
    projectCode: j.strOrNull('project_code'),
  );

  Expense copyWith({String? customerName, String? projectCode}) => Expense(
    id: id,
    projectId: projectId,
    category: category,
    amount: amount,
    note: note,
    createdAt: createdAt,
    expenseDate: expenseDate,
    scopeRaw: scopeRaw,
    ownerId: ownerId,
    customerName: customerName ?? this.customerName,
    projectCode: projectCode ?? this.projectCode,
  );
}

/// Sabit gider şablonu (`/recurring-expenses`).
@immutable
class RecurringExpense {
  const RecurringExpense({
    required this.id,
    required this.category,
    required this.amount,
    required this.scopeRaw,
    this.note,
    this.active = true,
  });

  final String id;
  final String category;
  final Money amount;
  final String? note;
  final String scopeRaw;
  final bool active;

  ScopeView get scope => ScopeView.fromApi(scopeRaw);

  factory RecurringExpense.fromJson(JsonMap j) => RecurringExpense(
    id: j.strOr('id'),
    category: j.strOr('category'),
    amount: j.money('amount'),
    note: j.strOrNull('note'),
    scopeRaw: j.strOr('scope', 'genel'),
    active: j.boolOr('active', true),
  );
}

/// Proje özeti (ödeme/gider seçici ve alacak takibi için). `GET /projects` satırı:
/// `paid_amount` yalnız çağıranın defterindeki tahsilattır (§4).
@immutable
class ProjectRef {
  const ProjectRef({
    required this.id,
    required this.customerName,
    this.code,
    this.service,
    this.stage,
    this.total = Money.zero,
    this.paid = Money.zero,
    this.extras = Money.zero,
    this.customerPhone,
    this.endDate,
    this.serverBalance,
  });

  final String id;
  final String? code;
  final String customerName;
  final String? service;
  final String? stage;

  /// Sözleşme tutarı (`total_amount`).
  final Money total;

  /// Tahsil edilen (`paid_amount`).
  final Money paid;

  /// İlave işler toplamı (yalnız `/projects/:id/full` bilir; listede sıfır).
  final Money extras;
  final String? customerPhone;
  final DateTime? endDate;

  /// Sunucunun hesapladığı bakiye (`balance` = sözleşme + ilave − tahsilat); yoksa null.
  final Money? serverBalance;

  /// Kalan bakiye = sözleşme + ilave − tahsilat (negatif olamaz; fazla ödeme 0 görünür).
  /// Sunucu `balance` verdiyse (ilave işleri de bilir) o kullanılır.
  Money get remaining =>
      (serverBalance ?? (total + extras - paid)).clampNonNegative();

  /// Fazla tahsilat (kalan negatifse) — bilgi için.
  bool get overpaid => (serverBalance ?? (total + extras - paid)).isNegative;

  bool get isCompleted => (stage ?? '').trim() == 'Tamamlandı';

  /// "PRJ-501 · Zeynep Arslan". ASLA UUID.
  String get displayLabel =>
      FinanceLabels.project(code: code, customer: customerName);

  factory ProjectRef.fromJson(JsonMap j) => ProjectRef(
    id: j.strOr('id'),
    code: j.strOrNull('code'),
    customerName: j.strOr('customer_name'),
    service: j.strOrNull('service'),
    stage: j.strOrNull('stage'),
    total: j.money('total_amount'),
    paid: j.money('paid_amount'),
    customerPhone: j.strOrNull('customer_phone'),
    endDate: j.dateTime('end_date'),
    serverBalance: j.moneyOrNull('balance'),
  );

  ProjectRef copyWith({Money? paid, Money? extras}) => ProjectRef(
    id: id,
    code: code,
    customerName: customerName,
    service: service,
    stage: stage,
    total: total,
    paid: paid ?? this.paid,
    extras: extras ?? this.extras,
    customerPhone: customerPhone,
    endDate: endDate,
    // paid/extras elle değiştiyse sunucu bakiyesi eskimiştir.
    serverBalance: (paid != null || extras != null) ? null : serverBalance,
  );
}

/// Kayıt sahibi adayı (defter sahibi): `GET /projects/:id/collaborators` satırı `{id,name,role}`.
@immutable
class OwnerRef {
  const OwnerRef({required this.id, required this.name, this.role});
  final String id;
  final String name;
  final String? role;

  factory OwnerRef.fromJson(JsonMap j) => OwnerRef(
    id: j.strOr('id'),
    name: j.strOr('name'),
    role: j.strOrNull('role'),
  );
}

/// Kullanıcı kimliği → görünen ad (oturumdaki ben + ekip). Bilinmeyen kimlik ham UUID olarak
/// GÖSTERİLMEZ ("Başka kullanıcı").
@immutable
class OwnerDirectory {
  const OwnerDirectory({this.selfId, this.names = const {}});
  final String? selfId;
  final Map<String, String> names;

  static const OwnerDirectory empty = OwnerDirectory();

  bool isSelf(String? id) => id != null && id.isNotEmpty && id == selfId;

  /// Kayıt başkasına aitse adı; kendimse ya da sahip yoksa null.
  String? otherOwnerName(String? id) {
    if (id == null || id.isEmpty || isSelf(id)) return null;
    return nameOf(id);
  }

  String nameOf(String? id) {
    if (id == null || id.isEmpty) return 'Sahibi belirtilmemiş';
    final n = names[id];
    if (n != null && n.trim().isNotEmpty) return isSelf(id) ? '$n (Ben)' : n;
    return isSelf(id) ? 'Ben' : 'Başka kullanıcı';
  }
}

/// Gösterim metinleri: UUID'yi gizleyen tek yer.
abstract final class FinanceLabels {
  static String project({String? code, String? customer}) {
    final c = (code ?? '').trim();
    final n = (customer ?? '').trim();
    if (c.isNotEmpty && n.isNotEmpty) return '$c · $n';
    if (c.isNotEmpty) return c;
    if (n.isNotEmpty) return n;
    return 'Proje';
  }
}

/// Ödeme/gider formlarının sunucuya gidecek değerleri (doğrulanmış).
@immutable
class PaymentInput {
  const PaymentInput({
    required this.amount,
    required this.method,
    required this.paidAt,
    this.note,
    this.ownerId,
  });
  final Money amount;
  final String method;
  final DateTime paidAt;
  final String? note;

  /// Başkasının defterine yazmak için (v16 kuralı sunucuda denetlenir); null/boş = kendi defterim.
  final String? ownerId;

  JsonMap toJson() => {
    'amount': amount.toJson(),
    'method': method,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'paid_at': paidAtIso,
    if (ownerId != null && ownerId!.isNotEmpty) 'owner_id': ownerId,
  };

  String get paidAtIso => _noon(paidAt);
}

@immutable
class ExpenseInput {
  const ExpenseInput({
    required this.category,
    required this.amount,
    required this.scope,
    required this.date,
    this.projectId,
    this.note,
    this.ownerId,
  });
  final String category;
  final Money amount;
  final ScopeView scope;
  final DateTime date;
  final String? projectId;
  final String? note;

  /// Başkasının defterine yazmak için; null/boş = gönderilmez (düzenlemede mevcut sahip korunur).
  final String? ownerId;

  /// POST gövdesi. `project_id` yoksa genel gider (personel için 403).
  JsonMap toCreateJson() => {
    'category': category.trim(),
    'amount': amount.toJson(),
    'scope': scope.api,
    'expense_date': _noon(date),
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
    if (projectId != null && projectId!.isNotEmpty) 'project_id': projectId,
    if (ownerId != null && ownerId!.isNotEmpty) 'owner_id': ownerId,
  };

  /// PATCH gövdesi (proje değiştirilemez); `note: null` notu temizler.
  JsonMap toPatchJson() => {
    'category': category.trim(),
    'amount': amount.toJson(),
    'scope': scope.api,
    'expense_date': _noon(date),
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    if (ownerId != null && ownerId!.isNotEmpty) 'owner_id': ownerId,
  };
}

@immutable
class RecurringInput {
  const RecurringInput({
    required this.category,
    required this.amount,
    required this.scope,
    this.note,
    this.active,
  });
  final String category;
  final Money amount;
  final ScopeView scope;
  final String? note;
  final bool? active;

  JsonMap toCreateJson() => {
    'category': category.trim(),
    'amount': amount.toJson(),
    'scope': scope.api,
    if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
  };

  JsonMap toPatchJson() => {
    ...toCreateJson(),
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    if (active != null) 'active': active,
  };
}

// Panel kuralı: gün öğlen 12:00 İstanbul ofsetiyle gönderilir (gün kayması olmaz).
String _noon(DateTime instant) => Ist.noonIso(instant);
