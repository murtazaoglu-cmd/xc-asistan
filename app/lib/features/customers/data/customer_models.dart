// Müşteri modelleri (sözleşme §7). Elle yazılmış, null-güvenli.
// Liste satırı: {phone_key, name, email, phone, region, address, lat, lng, offer_count,
// first_contact, last_contact, project_count, total_contracted, total_paid}.
import 'package:flutter/foundation.dart';

import '../../../core/util/json.dart';
import '../../../core/util/money.dart';
import '../../../core/util/phone.dart';

@immutable
class Customer {
  const Customer({
    required this.phoneKey,
    required this.name,
    this.phone,
    this.email,
    this.region,
    this.address,
    this.lat,
    this.lng,
    this.note,
    this.offerCount = 0,
    this.projectCount = 0,
    this.firstContact,
    this.lastContact,
    this.totalContracted = Money.zero,
    this.totalPaid = Money.zero,
  });

  final String phoneKey;
  final String name;
  final String? phone;
  final String? email;
  final String? region;
  final String? address;
  final double? lat;
  final double? lng;

  /// Elle eklenen müşterinin notu (liste yanıtında olmayabilir).
  final String? note;
  final int offerCount;
  final int projectCount;
  final DateTime? firstContact;
  final DateTime? lastContact;
  final Money totalContracted;
  final Money totalPaid;

  /// Kalan bakiye (sözleşme − ödeme), negatif olmaz.
  Money get remaining => (totalContracted - totalPaid).clampNonNegative();

  /// Tekliften türeyen müşteri (kart bilgileri teklif üzerinden değişir).
  bool get isOfferDerived => offerCount > 0;

  String get displayName => name.trim().isEmpty ? '-' : name.trim();

  /// "Ayşe Yılmaz" → "AY"; tek sözcük → ilk iki harf.
  String get initials => initialsOf(name);

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    String up(String s) => s.isEmpty ? s : _upper(s[0]);
    if (parts.length == 1) {
      final w = parts.first;
      return w.length >= 2 ? '${up(w)}${_upper(w[1])}' : up(w);
    }
    return '${up(parts.first)}${up(parts.last)}';
  }

  static String _upper(String c) => switch (c) {
    'i' => 'İ',
    'ı' => 'I',
    _ => c.toUpperCase(),
  };

  factory Customer.fromJson(JsonMap j) {
    final phone = j.strOrNull('phone');
    final key = j.strOrNull('phone_key') ?? PhoneUtil.phoneKey(phone);
    return Customer(
      phoneKey: key,
      name: j.strOr('name'),
      phone: phone,
      email: j.strOrNull('email'),
      region: j.strOrNull('region'),
      address: j.strOrNull('address'),
      lat: j.doubleOrNull('lat'),
      lng: j.doubleOrNull('lng'),
      note: j.strOrNull('note'),
      offerCount: j.intOr('offer_count'),
      projectCount: j.intOr('project_count'),
      firstContact: j.dateTime('first_contact'),
      lastContact: j.dateTime('last_contact'),
      totalContracted: j.money('total_contracted'),
      totalPaid: j.money('total_paid'),
    );
  }

  Customer copyWith({String? note}) => Customer(
    phoneKey: phoneKey,
    name: name,
    phone: phone,
    email: email,
    region: region,
    address: address,
    lat: lat,
    lng: lng,
    note: note ?? this.note,
    offerCount: offerCount,
    projectCount: projectCount,
    firstContact: firstContact,
    lastContact: lastContact,
    totalContracted: totalContracted,
    totalPaid: totalPaid,
  );
}

/// Müşteri kartındaki teklif satırı (`GET /customers/:phoneKey` → offers[]).
@immutable
class CustomerOffer {
  const CustomerOffer({
    required this.id,
    this.code,
    this.service,
    this.status,
    this.createdAt,
    this.total,
    this.notes,
  });

  final String id;
  final String? code;
  final String? service;
  final String? status;
  final DateTime? createdAt;
  final Money? total;
  final String? notes;

  factory CustomerOffer.fromJson(JsonMap j) {
    final quote = j.mapOrNull('quote');
    return CustomerOffer(
      id: j.strOr('id'),
      code: j.strOrNull('code'),
      service: j.strOrNull('service'),
      status: j.strOrNull('status'),
      createdAt: j.dateTime('created_at'),
      total: quote?.moneyOrNull('total') ?? j.moneyOrNull('quote_total'),
      notes: j.strOrNull('notes'),
    );
  }
}

/// Müşteri kartındaki proje satırı (`projects[]`).
@immutable
class CustomerProject {
  const CustomerProject({
    required this.id,
    this.code,
    this.service,
    this.stage,
    this.total = Money.zero,
    this.paid = Money.zero,
    this.startDate,
    this.endDate,
  });

  final String id;
  final String? code;
  final String? service;
  final String? stage;
  final Money total;
  final Money paid;
  final DateTime? startDate;
  final DateTime? endDate;

  Money get remaining => (total - paid).clampNonNegative();

  factory CustomerProject.fromJson(JsonMap j) => CustomerProject(
    id: j.strOr('id'),
    code: j.strOrNull('code'),
    service: j.strOrNull('service'),
    stage: j.strOrNull('stage'),
    total: j.money('total_amount'),
    paid: j.money('paid_amount'),
    startDate: j.dateTime('start_date'),
    endDate: j.dateTime('end_date'),
  );
}

@immutable
class CustomerHistory {
  const CustomerHistory({this.offers = const [], this.projects = const []});
  final List<CustomerOffer> offers;
  final List<CustomerProject> projects;

  factory CustomerHistory.fromJson(JsonMap j) => CustomerHistory(
    offers: j.list('offers').map(CustomerOffer.fromJson).toList(),
    projects: j.list('projects').map(CustomerProject.fromJson).toList(),
  );
}

/// Form girdisi (POST/PATCH gövdesi).
@immutable
class CustomerInput {
  const CustomerInput({
    required this.name,
    this.phone = '',
    this.email = '',
    this.region = '',
    this.address = '',
    this.note = '',
  });

  final String name;
  final String phone;
  final String email;
  final String region;
  final String address;
  final String note;

  String get phoneKey => PhoneUtil.phoneKey(phone);

  static String? _opt(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  /// `POST /customers`: boş isteğe bağlı alanlar gönderilmez.
  JsonMap toCreateJson() => {
    'name': name.trim(),
    'phone': phone.trim(),
    if (_opt(email) != null) 'email': _opt(email),
    if (_opt(region) != null) 'region': _opt(region),
    if (_opt(address) != null) 'address': _opt(address),
    if (_opt(note) != null) 'note': _opt(note),
  };

  /// `PATCH /customers/:phoneKey`: boş alan `null` ile temizlenir (telefon değişmez).
  JsonMap toPatchJson() => {
    'name': name.trim(),
    'email': _opt(email),
    'region': _opt(region),
    'address': _opt(address),
    'note': _opt(note),
  };
}

/// Form doğrulayıcıları (Türkçe mesaj; geçerliyse null).
abstract final class CustomerValidators {
  static String? name(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Ad soyad girin.';
    if (t.length > 200) return 'Ad en fazla 200 karakter olabilir.';
    return null;
  }

  /// Telefon zorunlu; en az 10 rakam (0532 111 22 33), en çok 15.
  static String? phone(String? v) {
    final d = PhoneUtil.digits(v);
    if (d.isEmpty) return 'Telefon numarası girin.';
    if (d.length < 10) return 'Telefon en az 10 rakam olmalı.';
    if (d.length > 15) return 'Telefon çok uzun.';
    return null;
  }

  /// İsteğe bağlı; tek, geçerli bir adres (sunucu kuralı: boşluk/virgül/<> yok, ≤254).
  static String? email(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (t.length > 254 ||
        !RegExp(r'^[^\s@,<>;]+@[^\s@,<>;]+\.[^\s@,<>;]{2,}$').hasMatch(t)) {
      return 'Geçerli bir e-posta adresi girin.';
    }
    return null;
  }

  static String? maxLen(String? v, int max, String field) =>
      (v ?? '').trim().length > max
      ? '$field en fazla $max karakter olabilir.'
      : null;
}
