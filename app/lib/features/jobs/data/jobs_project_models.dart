// SAHİBİ: jobs ajanı. Proje tarafı modelleri (sözleşme §4, §5, §12).
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

/// Proje kaydı. Saha rolünde `total_amount` yoktur (null).
@immutable
class Project {
  const Project({
    required this.id,
    required this.code,
    this.offerId,
    required this.customerName,
    this.customerPhone,
    this.service,
    required this.stage,
    this.totalAmount,
    this.paidAmount,
    this.startDate,
    this.endDate,
    this.notes,
    this.ownerId,
    this.address,
    this.lat,
    this.lng,
  });

  final String id;
  final String code;
  final String? offerId;
  final String customerName;
  final String? customerPhone;
  final String? service;

  /// Ham aşama metni (bilinmeyen değer çökertmez).
  final String stage;

  /// Sözleşme tutarı; saha rolünde null.
  final Money? totalAmount;

  /// Yalnız liste yanıtında: ÇAĞIRANIN defterindeki tahsilat toplamı.
  final Money? paidAmount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? notes;
  final String? ownerId;
  final String? address;
  final double? lat;
  final double? lng;

  ProjectStage? get stageEnum => ProjectStage.fromApi(stage);
  bool get isDone => stageEnum == ProjectStage.tamamlandi;

  /// Bitiş tarihi geçmiş ve tamamlanmamış.
  bool isOverdue([DateTime? now]) {
    final e = endDate;
    if (e == null || isDone) return false;
    return e.isBefore(now ?? Ist.now());
  }

  int? daysOverdue([DateTime? now]) {
    if (!isOverdue(now)) return null;
    return Ist.dayDiff(endDate!, now ?? Ist.now());
  }

  /// Aşamaya göre ilerleme (0..1): Malzeme Temini 0, ..., Tamamlandı 1.
  double get stageProgress {
    final s = stageEnum;
    if (s == null) return 0;
    return s.index / (ProjectStage.values.length - 1);
  }

  /// Liste satırında kalan (ilave işler listede yok): sözleşme - tahsilat.
  Money? get listBalance =>
      totalAmount == null ? null : (totalAmount! - (paidAmount ?? Money.zero));

  factory Project.fromJson(JsonMap j) => Project(
    id: j.strOr('id'),
    code: j.strOr('code'),
    offerId: j.strOrNull('offer_id'),
    customerName: j.strOr('customer_name'),
    customerPhone: j.strOrNull('customer_phone'),
    service: j.strOrNull('service'),
    stage: j.strOr('stage'),
    totalAmount: j.moneyOrNull('total_amount'),
    paidAmount: j.moneyOrNull('paid_amount'),
    startDate: j.dateTime('start_date'),
    endDate: j.dateTime('end_date'),
    notes: j.strOrNull('notes'),
    ownerId: j.strOrNull('owner_id'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
  );

  Project withStage(String s) => Project(
    id: id,
    code: code,
    offerId: offerId,
    customerName: customerName,
    customerPhone: customerPhone,
    service: service,
    stage: s,
    totalAmount: totalAmount,
    paidAmount: paidAmount,
    startDate: startDate,
    endDate: endDate,
    notes: notes,
    ownerId: ownerId,
    address: address,
    lat: lat,
    lng: lng,
  );
}

/// Yeni (elle) proje gövdesi.
@immutable
class ProjectDraft {
  const ProjectDraft({
    required this.customerName,
    required this.service,
    this.totalAmount = Money.zero,
    this.stage = ProjectStage.malzemeTemini,
    this.address,
  });

  final String customerName;
  final String service;
  final Money totalAmount;
  final ProjectStage stage;
  final String? address;

  JsonMap toJson() => {
    'customer_name': customerName.trim(),
    'service': service.trim(),
    'total_amount': totalAmount.toJson(),
    'stage': stage.api,
    if (address != null && address!.trim().isNotEmpty)
      'address': address!.trim(),
  };
}

abstract final class ProjectValidators {
  static String? customerName(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Müşteri adı zorunludur.';
    if (t.length > 200) return 'En çok 200 karakter.';
    return null;
  }

  static String? service(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Hizmet zorunludur.';
    if (t.length > 200) return 'En çok 200 karakter.';
    return null;
  }

  /// Boş = 0. Negatif ve çözülemeyen tutar geçersizdir (sözleşme: total_amount ≥ 0).
  static String? amount(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final m = Money.parseUserInput(t);
    if (m == null) return 'Geçerli bir tutar girin.';
    if (m.isNegative) return 'Tutar negatif olamaz.';
    return null;
  }

  static String? address(String? v) =>
      (v ?? '').trim().length > 500 ? 'En çok 500 karakter.' : null;

  static String? taskTitle(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Görev başlığı boş olamaz.';
    if (t.length > 300) return 'En çok 300 karakter.';
    return null;
  }

  static String? extraDescription(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Açıklama zorunludur.';
    if (t.length > 300) return 'En çok 300 karakter.';
    return null;
  }

  /// İlave iş tutarı negatif olabilir (indirim) ama sıfır olamaz.
  static String? extraAmount(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Tutar zorunludur.';
    final m = Money.parseUserInput(t);
    if (m == null) return 'Geçerli bir tutar girin.';
    if (m.isZero) return 'Tutar sıfır olamaz.';
    return null;
  }
}

@immutable
class ProjectTask {
  const ProjectTask({
    required this.id,
    required this.projectId,
    required this.title,
    required this.status,
    this.assignedUserId,
  });
  final String id;
  final String projectId;
  final String title;
  final String status;
  final String? assignedUserId;

  TaskStatus? get statusEnum => TaskStatus.fromApi(status);
  bool get isDone => statusEnum == TaskStatus.tamamlandi;

  factory ProjectTask.fromJson(JsonMap j) => ProjectTask(
    id: j.strOr('id'),
    projectId: j.strOr('project_id'),
    title: j.strOr('title'),
    status: j.strOr('status', TaskStatus.bekliyor.api),
    assignedUserId: j.strOrNull('assigned_user_id'),
  );

  ProjectTask withStatus(String s) => ProjectTask(
    id: id,
    projectId: projectId,
    title: title,
    status: s,
    assignedUserId: assignedUserId,
  );
}

@immutable
class ProjectExtra {
  const ProjectExtra({
    required this.id,
    required this.description,
    required this.amount,
    this.createdAt,
  });
  final String id;
  final String description;

  /// Negatif olabilir (indirim).
  final Money amount;
  final DateTime? createdAt;

  factory ProjectExtra.fromJson(JsonMap j) => ProjectExtra(
    id: j.strOr('id'),
    description: j.strOr('description'),
    amount: j.money('amount'),
    createdAt: j.dateTime('created_at'),
  );
}

/// /projects/:id/full içindeki ödeme satırı (salt okunur; ekleme finance modülündedir).
@immutable
class JobPayment {
  const JobPayment({
    required this.id,
    required this.amount,
    required this.method,
    this.note,
    this.paidAt,
  });
  final String id;
  final Money amount;
  final String method;
  final String? note;
  final DateTime? paidAt;

  factory JobPayment.fromJson(JsonMap j) => JobPayment(
    id: j.strOr('id'),
    amount: j.money('amount'),
    method: j.strOr('method'),
    note: j.strOrNull('note'),
    paidAt: j.dateTime('paid_at'),
  );
}

/// /projects/:id/full içindeki gider satırı (salt okunur).
@immutable
class JobExpense {
  const JobExpense({
    required this.id,
    required this.category,
    required this.amount,
    this.note,
    this.date,
  });
  final String id;
  final String category;
  final Money amount;
  final String? note;
  final DateTime? date;

  factory JobExpense.fromJson(JsonMap j) => JobExpense(
    id: j.strOr('id'),
    category: j.strOr('category'),
    amount: j.money('amount'),
    note: j.strOrNull('note'),
    date: j.dateTime('expense_date') ?? j.dateTime('created_at'),
  );
}

/// `GET /projects/:id/full` bileşimi.
@immutable
class ProjectFull {
  const ProjectFull({
    required this.project,
    this.tasks = const [],
    this.extras = const [],
    this.payments = const [],
    this.expenses = const [],
    this.financeVisible = true,
  });

  final Project project;
  final List<ProjectTask> tasks;
  final List<ProjectExtra> extras;
  final List<JobPayment> payments;
  final List<JobExpense> expenses;

  /// false: saha görünümü (sözleşme/ödeme/gider verisi yok).
  final bool financeVisible;

  factory ProjectFull.fromJson(JsonMap j) => ProjectFull(
    project: Project.fromJson(j.mapOrNull('project') ?? const {}),
    tasks: j.list('tasks').map(ProjectTask.fromJson).toList(),
    extras: j.list('extras').map(ProjectExtra.fromJson).toList(),
    payments: j.list('payments').map(JobPayment.fromJson).toList(),
    expenses: j.list('expenses').map(JobExpense.fromJson).toList(),
  );

  Money get extrasTotal => Money.sum(extras.map((e) => e.amount));
  Money get paidTotal => Money.sum(payments.map((e) => e.amount));
  Money get expensesTotal => Money.sum(expenses.map((e) => e.amount));

  /// Sözleşme tutarı (saha: null).
  Money? get contract => project.totalAmount;

  /// Sözleşme + ilave işler.
  Money? get contractWithExtras =>
      contract == null ? null : contract! + extrasTotal;

  /// Kalan = sözleşme + ilave işler - tahsilat (tek formül; sözleşme/araştırma D4).
  Money? get balance =>
      contractWithExtras == null ? null : contractWithExtras! - paidTotal;

  /// Tahsilat oranı 0..1 (sözleşme sıfırsa 0).
  double get paidRatio {
    final c = contractWithExtras;
    if (c == null || !c.isPositive) return 0;
    final r = paidTotal.kurus / c.kurus;
    return r.clamp(0.0, 1.0);
  }

  /// İlerleme (0..1): görev varsa tamamlanan görev oranı, yoksa aşama.
  double get progress {
    if (tasks.isNotEmpty) {
      return tasks.where((t) => t.isDone).length / tasks.length;
    }
    return project.stageProgress;
  }

  ProjectFull copyWith({
    Project? project,
    List<ProjectTask>? tasks,
    List<ProjectExtra>? extras,
  }) => ProjectFull(
    project: project ?? this.project,
    tasks: tasks ?? this.tasks,
    extras: extras ?? this.extras,
    payments: payments,
    expenses: expenses,
    financeVisible: financeVisible,
  );
}

// ---------------------------------------------------------------------------
// Belge / paylaşım / aktivite / işbirlikçi
// ---------------------------------------------------------------------------

@immutable
class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.fileUrl,
    required this.fileName,
    this.uploadedByName,
    this.createdAt,
  });
  final String id;

  /// İmzalı, 10 dk geçerli bağlantı: SAKLAMAYIN, her açılışta listeyi yenileyin.
  final String fileUrl;
  final String fileName;
  final String? uploadedByName;
  final DateTime? createdAt;

  String get extension => DocumentRules.extensionOf(fileName);
  bool get isImage => DocumentRules.imageExtensions.contains(extension);
  bool get isPdf => extension == 'pdf';

  factory DocumentItem.fromJson(JsonMap j) => DocumentItem(
    id: j.strOr('id'),
    fileUrl: j.strOr('file_url'),
    fileName: j.strOr('file_name', 'Dosya'),
    uploadedByName: j.strOrNull('uploaded_by_name'),
    createdAt: j.dateTime('created_at'),
  );
}

/// Belge yükleme kuralları (sözleşme §12: allowlist + 15 MB).
abstract final class DocumentRules {
  static const int maxBytes = 15 * 1024 * 1024;
  static const List<String> allowedExtensions = [
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'heic',
    'heif',
    'mp4',
    'mov',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'rtf',
    'txt',
    'csv',
    'dwg',
    'dxf',
    'zip',
  ];
  static const Set<String> imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'heic',
    'heif',
  };

  static String extensionOf(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1).toLowerCase();
  }

  /// Yüklemeden önce istemci denetimi. Hata yoksa null.
  static String? validate(String fileName, int sizeBytes) {
    final ext = extensionOf(fileName);
    if (!allowedExtensions.contains(ext)) return 'Bu dosya türü yüklenemez.';
    if (sizeBytes > maxBytes) return 'Dosya en çok 15 MB olabilir.';
    if (sizeBytes <= 0) return 'Dosya boş görünüyor.';
    return null;
  }
}

@immutable
class ShareItem {
  const ShareItem({
    required this.id,
    required this.userId,
    this.userName,
    this.userEmail,
  });
  final String id;
  final String userId;
  final String? userName;
  final String? userEmail;

  factory ShareItem.fromJson(JsonMap j) => ShareItem(
    id: j.strOr('id'),
    userId: j.strOr('shared_with_user_id'),
    userName: j.strOrNull('user_name'),
    userEmail: j.strOrNull('user_email'),
  );
}

@immutable
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.action,
    this.details,
    this.userName,
    this.createdAt,
  });
  final String id;
  final String action;
  final String? details;
  final String? userName;
  final DateTime? createdAt;

  /// `durum_degisti, duzenlendi, paylasildi, odeme_eklendi, dosya_eklendi, asama_degisti`
  String get label {
    switch (action) {
      case 'durum_degisti':
        return 'Durum değişti';
      case 'duzenlendi':
        return 'Düzenlendi';
      case 'paylasildi':
        return 'Paylaşıldı';
      case 'odeme_eklendi':
        return 'Ödeme eklendi';
      case 'dosya_eklendi':
        return 'Dosya eklendi';
      case 'asama_degisti':
        return 'Aşama değişti';
      default:
        return action.replaceAll('_', ' ');
    }
  }

  factory ActivityItem.fromJson(JsonMap j) => ActivityItem(
    id: j.strOr('id'),
    action: j.strOr('action'),
    details: j.strOrNull('details'),
    userName: j.strOrNull('user_name'),
    createdAt: j.dateTime('created_at'),
  );
}

/// Kullanıcı özeti (işbirlikçi seçici, paylaşım adayı).
@immutable
class PersonRef {
  const PersonRef({required this.id, required this.name, this.role});
  final String id;
  final String name;
  final String? role;

  factory PersonRef.fromJson(JsonMap j) => PersonRef(
    id: j.strOr('id'),
    name: j.strOr('name', 'Kullanıcı'),
    role: j.strOrNull('role'),
  );
}
