// SAHİBİ: appointments ajanı. Sözleşme §9 "çözümlenmiş randevu" modeli (null-güvenli),
// randevu taslağı (POST/PATCH gövdesi) ve bağlantı adayı (teklif/proje/müşteri seçici).
import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';

/// Çözümlenmiş randevu (GET /appointments, /appointments/:id, POST/PATCH yanıtı,
/// /mobile/home içindeki today/tomorrow satırları).
@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.type,
    required this.scheduledAt,
    required this.status,
    this.offerId,
    this.projectId,
    this.assignedUserId,
    this.assignedUserName,
    this.notes,
    this.ownerId,
    this.customerName,
    this.customerPhone,
    this.address,
    this.lat,
    this.lng,
    this.service,
    this.offerCode,
    this.projectCode,
    this.offerName,
    this.offerPhone,
    this.offerService,
    this.projectCustomer,
  });

  final String id;

  /// Serbest metin (≤40). Bilinmeyen değer olduğu gibi gösterilir.
  final String type;
  final DateTime? scheduledAt;

  /// Serbest metin (≤40): `beklemede`, `onaylandı`, `tamamlandı`, `iptal`, eski: `planlandi`.
  final String status;
  final String? offerId;
  final String? projectId;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? notes;
  final String? ownerId;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final double? lat;
  final double? lng;
  final String? service;
  final String? offerCode;
  final String? projectCode;
  final String? offerName;
  final String? offerPhone;
  final String? offerService;
  final String? projectCustomer;

  factory Appointment.fromJson(JsonMap j) => Appointment(
    id: j.strOr('id'),
    type: j.strOr('type'),
    scheduledAt: j.dateTime('scheduled_at'),
    status: j.strOr('status'),
    offerId: j.strOrNull('offer_id'),
    projectId: j.strOrNull('project_id'),
    assignedUserId: j.strOrNull('assigned_user_id'),
    assignedUserName: j.strOrNull('assigned_user_name'),
    notes: j.strOrNull('notes'),
    ownerId: j.strOrNull('owner_id'),
    customerName: j.strOrNull('customer_name'),
    customerPhone: j.strOrNull('customer_phone'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
    service: j.strOrNull('service'),
    offerCode: j.strOrNull('offer_code'),
    projectCode: j.strOrNull('project_code'),
    offerName: j.strOrNull('offer_name'),
    offerPhone: j.strOrNull('offer_phone'),
    offerService: j.strOrNull('offer_service'),
    projectCustomer: j.strOrNull('project_customer'),
  );

  /// Sunucu zaten çözümler; eski satırlar için yedek zinciri.
  String? get displayName => customerName ?? offerName ?? projectCustomer;
  String? get displayPhone => customerPhone ?? offerPhone;
  String? get displayService => service ?? offerService;

  bool get isCancelled => AppointmentValues.isCancelled(status);
  bool get isDone => AppointmentValues.isDone(status);

  /// Yapılmamış ve iptal edilmemiş.
  bool get isOpen => !isCancelled && !isDone;

  bool get hasLink => offerId != null || projectId != null;

  /// Zamanı geçmiş ama hâlâ açık.
  bool isOverdue([DateTime? now]) {
    final t = scheduledAt;
    return isOpen && t != null && t.isBefore(now ?? Ist.now());
  }

  Appointment copyWith({
    String? status,
    DateTime? scheduledAt,
    String? notes,
    bool clearNotes = false,
  }) => Appointment(
    id: id,
    type: type,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    status: status ?? this.status,
    offerId: offerId,
    projectId: projectId,
    assignedUserId: assignedUserId,
    assignedUserName: assignedUserName,
    notes: clearNotes ? null : (notes ?? this.notes),
    ownerId: ownerId,
    customerName: customerName,
    customerPhone: customerPhone,
    address: address,
    lat: lat,
    lng: lng,
    service: service,
    offerCode: offerCode,
    projectCode: projectCode,
    offerName: offerName,
    offerPhone: offerPhone,
    offerService: offerService,
    projectCustomer: projectCustomer,
  );
}

/// Randevu formunun çıktısı. POST gövdesi [toCreateJson], PATCH gövdesi [toPatchJson].
@immutable
class AppointmentDraft {
  const AppointmentDraft({
    required this.type,
    required this.scheduledAt,
    this.notes,
    this.offerId,
    this.projectId,
    this.assignedUserId,
    this.customerName,
    this.customerPhone,
    this.address,
  });

  final String type;
  final DateTime scheduledAt;
  final String? notes;
  final String? offerId;
  final String? projectId;
  final String? assignedUserId;
  final String? customerName;
  final String? customerPhone;
  final String? address;

  static String? _clean(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// POST /appointments gövdesi: boş alanlar hiç gönderilmez.
  JsonMap toCreateJson() {
    final m = <String, dynamic>{
      'type': type.trim(),
      'scheduled_at': Ist.toApiIso(scheduledAt),
    };
    void put(String k, String? v) {
      final c = _clean(v);
      if (c != null) m[k] = c;
    }

    put('notes', notes);
    put('offer_id', offerId);
    put('project_id', projectId);
    put('assigned_user_id', assignedUserId);
    put('customer_name', customerName);
    put('customer_phone', customerPhone);
    put('address', address);
    return m;
  }

  /// PATCH /appointments/:id gövdesi: yalnız DEĞİŞEN alanlar. Bağlantı/atama kaldırılırsa `null`.
  /// Adres değişirse eski koordinatlar bayat kalmasın diye `lat/lng` de `null` gönderilir.
  JsonMap toPatchJson(Appointment o) {
    final m = <String, dynamic>{};
    if (type.trim() != o.type) m['type'] = type.trim();
    final at = o.scheduledAt;
    if (at == null || at != scheduledAt) {
      m['scheduled_at'] = Ist.toApiIso(scheduledAt);
    }
    void diff(String key, String? now, String? before) {
      final a = _clean(now);
      if (a != _clean(before)) m[key] = a;
    }

    diff('notes', notes, o.notes);
    diff('offer_id', offerId, o.offerId);
    diff('project_id', projectId, o.projectId);
    diff('assigned_user_id', assignedUserId, o.assignedUserId);
    diff('customer_name', customerName, o.displayName);
    diff('customer_phone', customerPhone, o.displayPhone);
    if (_clean(address) != _clean(o.address)) {
      m['address'] = _clean(address);
      m['lat'] = null;
      m['lng'] = null;
    }
    return m;
  }
}

enum LinkKind { offer, project, customer }

/// Randevu formundaki "Kime?" seçicisinin adayı (teklif / proje / müşteri satırı).
@immutable
class LinkCandidate {
  const LinkCandidate({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.phone,
    this.address,
    this.lat,
    this.lng,
  });

  final LinkKind kind;

  /// Teklif/proje için UUID; müşteri için `phone_key`.
  final String id;
  final String title;
  final String? subtitle;
  final String? phone;
  final String? address;
  final double? lat;
  final double? lng;

  static String? _join(Iterable<String?> parts) {
    final p = parts
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toList();
    return p.isEmpty ? null : p.join(' · ');
  }

  factory LinkCandidate.fromOffer(JsonMap j) => LinkCandidate(
    kind: LinkKind.offer,
    id: j.strOr('id'),
    title: j.strOrNull('name') ?? j.strOrNull('code') ?? '-',
    subtitle: _join([
      j.strOrNull('code'),
      j.strOrNull('service'),
      j.strOrNull('region'),
    ]),
    phone: j.strOrNull('phone'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
  );

  factory LinkCandidate.fromProject(JsonMap j) => LinkCandidate(
    kind: LinkKind.project,
    id: j.strOr('id'),
    title: j.strOrNull('customer_name') ?? j.strOrNull('code') ?? '-',
    subtitle: _join([
      j.strOrNull('code'),
      j.strOrNull('service'),
      j.strOrNull('stage'),
    ]),
    phone: j.strOrNull('customer_phone') ?? j.strOrNull('phone'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
  );

  factory LinkCandidate.fromCustomer(JsonMap j) => LinkCandidate(
    kind: LinkKind.customer,
    id: j.strOr('phone_key'),
    title: j.strOrNull('name') ?? j.strOrNull('phone') ?? '-',
    subtitle: _join([j.strOrNull('phone'), j.strOrNull('region')]),
    phone: j.strOrNull('phone'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
  );
}
