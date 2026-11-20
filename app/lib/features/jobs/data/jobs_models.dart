// SAHİBİ: jobs ajanı. Teklif tarafı modelleri (sözleşme §3, §12).
// Para: kuruş tamsayısı (Money). KDV hesabı backend `computeTotals` ile BİREBİR aynıdır
// (kalem bazlı vatIncluded, satır bazında yuvarlama, total = subtotal + tax).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/util/dates.dart';
import '../../../core/util/domain_enums.dart';
import '../../../core/util/json.dart';
import '../../../core/util/money.dart';

num _qtyOf(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim().replaceAll(',', '.')) ?? 1;
  return 1;
}

List<QuoteItem> _itemsOf(Object? v) {
  Object? raw = v;
  if (raw is String) {
    try {
      raw = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  return asJsonList(raw).map(QuoteItem.fromJson).toList();
}

/// Teklif kalemi: `{desc, qty, price, vatIncluded}`.
@immutable
class QuoteItem {
  const QuoteItem({
    required this.desc,
    required this.qty,
    required this.price,
    this.vatIncluded = false,
  });

  final String desc;
  final num qty;

  /// Birim fiyat (vatIncluded true ise KDV DAHİL girilmiş fiyat).
  final Money price;
  final bool vatIncluded;

  factory QuoteItem.fromJson(JsonMap j) => QuoteItem(
    desc: j.strOr('desc', j.strOr('description')),
    qty: _qtyOf(j['qty']),
    price: j.money('price'),
    vatIncluded: j.boolOr('vatIncluded'),
  );

  JsonMap toJson() => {
    'desc': desc,
    'qty': qty,
    'price': price.toJson(),
    'vatIncluded': vatIncluded,
  };

  /// qty x birim fiyat (kuruş): backend `Math.round(qty * price * 100)` ile AYNI kayan nokta
  /// işlemi (sunucu TL'yi double okur; ör. 2,5 x 19,99 = 4997,4999… → 4997). Tamsayı `times`
  /// kullanılırsa yarım kuruşlarda sunucudan 1 kuruş sapılır.
  Money get line => Money.fromKurus(
    ((qty.toDouble() * double.parse(price.toApiString())) * 100).round(),
  );

  /// Satırın KDV dahil toplamı (gösterim).
  Money get lineGross =>
      vatIncluded ? line : line.withVat(QuoteMath.vatPercent);

  QuoteItem copyWith({
    String? desc,
    num? qty,
    Money? price,
    bool? vatIncluded,
  }) => QuoteItem(
    desc: desc ?? this.desc,
    qty: qty ?? this.qty,
    price: price ?? this.price,
    vatIncluded: vatIncluded ?? this.vatIncluded,
  );

  @override
  bool operator ==(Object other) =>
      other is QuoteItem &&
      other.desc == desc &&
      other.qty == qty &&
      other.price == price &&
      other.vatIncluded == vatIncluded;

  @override
  int get hashCode => Object.hash(desc, qty, price, vatIncluded);
}

@immutable
class QuoteTotals {
  const QuoteTotals(this.subtotal, this.tax, this.total);
  final Money subtotal;
  final Money tax;
  final Money total;

  static const zero = QuoteTotals(Money.zero, Money.zero, Money.zero);

  @override
  bool operator ==(Object other) =>
      other is QuoteTotals &&
      other.subtotal == subtotal &&
      other.tax == tax &&
      other.total == total;

  @override
  int get hashCode => Object.hash(subtotal, tax, total);
}

/// Backend `quotes.js computeTotals` ile aynı mantık (tamsayı kuruş):
///   line = round(qty * price)
///   vatIncluded: net += round(line * 100 / 120), gross += line
///   aksi: net += line, gross += line + round(line * 0.2)
///   subtotal = net, tax = gross - net, total = gross
abstract final class QuoteMath {
  static const int vatPercent = 20;
  static const int maxItems = 200;
  static const int maxDescLength = 500;

  static QuoteTotals compute(Iterable<QuoteItem> items) {
    var net = Money.zero;
    var gross = Money.zero;
    for (final it in items) {
      final line = it.line;
      if (it.vatIncluded) {
        net += line.excludingVat(vatPercent);
        gross += line;
      } else {
        net += line;
        gross += line.withVat(vatPercent);
      }
    }
    return QuoteTotals(net, gross - net, gross);
  }

  /// Kalem listesi doğrulaması (backend ile aynı kurallar). Hata yoksa null.
  static String? validate(List<QuoteItem> items) {
    if (items.isEmpty) return 'En az bir kalem ekleyin.';
    if (items.length > maxItems) {
      return 'Bir teklifte en çok $maxItems kalem olabilir.';
    }
    for (final it in items) {
      if (it.desc.trim().isEmpty) return 'Kalem açıklaması boş olamaz.';
      if (it.desc.length > maxDescLength) {
        return 'Kalem açıklaması en çok $maxDescLength karakter olabilir.';
      }
      if (!(it.qty > 0)) return 'Adet sıfırdan büyük olmalı.';
      if (it.price.isNegative) return 'Birim fiyat negatif olamaz.';
    }
    return null;
  }
}

/// Teklifin son hazırlanmış hâli (`quote` nesnesi). Liste satırında `id` olmayabilir.
@immutable
class OfferQuote {
  const OfferQuote({
    this.id,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    this.createdAt,
    this.sentViaWhatsappAt,
    this.sentViaEmailAt,
    this.lastSendStatus,
    this.lastSendAt,
    this.lastSendError,
  });

  final String? id;
  final List<QuoteItem> items;
  final Money subtotal;
  final Money tax;
  final Money total;
  final DateTime? createdAt;
  final DateTime? sentViaWhatsappAt;
  final DateTime? sentViaEmailAt;

  /// `gonderildi` | `kismen` | `basarisiz` | null (hiç gönderilmedi)
  final String? lastSendStatus;
  final DateTime? lastSendAt;
  final String? lastSendError;

  SendStatus? get sendStatus => SendStatus.fromApi(lastSendStatus);

  /// Sunucu toplamları yerine kalemlerden yeniden hesap (tutarlılık denetimi).
  QuoteTotals get computed => QuoteMath.compute(items);

  factory OfferQuote.fromJson(JsonMap j) => OfferQuote(
    id: j.strOrNull('id'),
    items: _itemsOf(j['items']),
    subtotal: j.money('subtotal'),
    tax: j.money('tax'),
    total: j.money('total'),
    createdAt: j.dateTime('created_at'),
    sentViaWhatsappAt: j.dateTime('sent_via_whatsapp_at'),
    sentViaEmailAt: j.dateTime('sent_via_email_at'),
    lastSendStatus: j.strOrNull('last_send_status'),
    lastSendAt: j.dateTime('last_send_at'),
    lastSendError: j.strOrNull('last_send_error'),
  );
}

/// Teklif kaydı (liste satırı + ayrıntı).
@immutable
class Offer {
  const Offer({
    required this.id,
    required this.code,
    this.trackingCode,
    required this.name,
    this.phone,
    this.email,
    this.service,
    this.region,
    this.message,
    this.notes,
    this.photoUrls = const [],
    required this.status,
    this.source,
    this.ownerId,
    this.address,
    this.lat,
    this.lng,
    this.createdAt,
    this.updatedAt,
    this.quote,
    this.quoteTotal,
  });

  final String id;
  final String code;
  final String? trackingCode;
  final String name;
  final String? phone;
  final String? email;
  final String? service;
  final String? region;
  final String? message;
  final String? notes;
  final List<String> photoUrls;

  /// Ham durum metni (bilinmeyen değer çökertmez).
  final String status;
  final String? source;
  final String? ownerId;
  final String? address;
  final double? lat;
  final double? lng;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final OfferQuote? quote;
  final Money? quoteTotal;

  OfferStatus? get statusEnum => OfferStatus.fromApi(status);

  /// Liste tutarı: son teklifin toplamı (yoksa null → "Teklif hazırlanmadı").
  Money? get amount => quote?.total ?? quoteTotal;

  bool get hasQuote => quote != null;
  bool get isAccepted => statusEnum == OfferStatus.kabulEdildi;
  bool get isClosed =>
      statusEnum == OfferStatus.kabulEdildi ||
      statusEnum == OfferStatus.reddedildi;

  /// "Bekleme yaşı" başlangıcı: Teklif Verildi'de son gönderim/hazırlama,
  /// diğer açık durumlarda talebin geliş zamanı. Kapalı durumlarda null.
  DateTime? get waitingSince {
    if (isClosed) return null;
    if (statusEnum == OfferStatus.teklifVerildi) {
      return quote?.lastSendAt ?? quote?.createdAt ?? updatedAt ?? createdAt;
    }
    return createdAt;
  }

  /// Bekleme gün sayısı (İstanbul takvim günü); kapalıysa null.
  int? waitingDays([DateTime? now]) {
    final s = waitingSince;
    if (s == null) return null;
    final d = Ist.dayDiff(s, now ?? Ist.now());
    return d < 0 ? 0 : d;
  }

  factory Offer.fromJson(JsonMap j) => Offer(
    id: j.strOr('id'),
    code: j.strOr('code'),
    trackingCode: j.strOrNull('tracking_code'),
    name: j.strOr('name'),
    phone: j.strOrNull('phone'),
    email: j.strOrNull('email'),
    service: j.strOrNull('service'),
    region: j.strOrNull('region'),
    message: j.strOrNull('message'),
    notes: j.strOrNull('notes'),
    photoUrls: j.stringList('photo_urls'),
    status: j.strOr('status'),
    source: j.strOrNull('source'),
    ownerId: j.strOrNull('owner_id'),
    address: j.strOrNull('address'),
    lat: j.doubleOrNull('lat'),
    lng: j.doubleOrNull('lng'),
    createdAt: j.dateTime('created_at'),
    updatedAt: j.dateTime('updated_at'),
    quote: j.mapOrNull('quote') == null
        ? null
        : OfferQuote.fromJson(j.mapOrNull('quote')!),
    quoteTotal: j.moneyOrNull('quote_total'),
  );

  /// PATCH yanıtı `quote` taşımaz: mevcut teklifi koruyarak satırı günceller.
  Offer mergedWith(Offer fresh) => Offer(
    id: fresh.id,
    code: fresh.code,
    trackingCode: fresh.trackingCode ?? trackingCode,
    name: fresh.name,
    phone: fresh.phone,
    email: fresh.email,
    service: fresh.service,
    region: fresh.region,
    message: fresh.message,
    notes: fresh.notes,
    photoUrls: fresh.photoUrls,
    status: fresh.status,
    source: fresh.source ?? source,
    ownerId: fresh.ownerId ?? ownerId,
    address: fresh.address,
    lat: fresh.lat,
    lng: fresh.lng,
    createdAt: fresh.createdAt ?? createdAt,
    updatedAt: fresh.updatedAt ?? updatedAt,
    quote: fresh.quote ?? quote,
    quoteTotal: fresh.quoteTotal ?? quoteTotal,
  );

  Offer withStatus(String s) => Offer(
    id: id,
    code: code,
    trackingCode: trackingCode,
    name: name,
    phone: phone,
    email: email,
    service: service,
    region: region,
    message: message,
    notes: notes,
    photoUrls: photoUrls,
    status: s,
    source: source,
    ownerId: ownerId,
    address: address,
    lat: lat,
    lng: lng,
    createdAt: createdAt,
    updatedAt: updatedAt,
    quote: quote,
    quoteTotal: quoteTotal,
  );
}

/// Yeni teklif talebi / temel bilgi düzenleme gövdesi.
@immutable
class OfferDraft {
  const OfferDraft({
    required this.name,
    required this.phone,
    required this.service,
    this.email,
    this.region,
    this.message,
    this.notes,
    this.address,
  });

  final String name;
  final String phone;
  final String service;
  final String? email;
  final String? region;
  final String? message;
  final String? notes;
  final String? address;

  factory OfferDraft.fromOffer(Offer o) => OfferDraft(
    name: o.name,
    phone: o.phone ?? '',
    service: o.service ?? '',
    email: o.email,
    region: o.region,
    message: o.message,
    notes: o.notes,
    address: o.address,
  );

  static String? _t(String? s) {
    final v = s?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// POST /offers (yalnız dolu alanlar).
  JsonMap toCreateJson() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'service': service.trim(),
    if (_t(email) != null) 'email': _t(email),
    if (_t(region) != null) 'region': _t(region),
    if (_t(message) != null) 'message': _t(message),
    if (_t(address) != null) 'address': _t(address),
  };

  /// PATCH /offers/:id: temizlenebilen alanlar `null` gider.
  JsonMap toPatchJson() => {
    'name': name.trim(),
    'phone': phone.trim(),
    'service': service.trim(),
    'email': _t(email),
    'region': _t(region),
    'message': _t(message),
    'notes': _t(notes),
    'address': _t(address),
  };
}

/// Form doğrulayıcıları (sözleşme sınırları: §3).
abstract final class OfferValidators {
  static final RegExp _email = RegExp(
    r'^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$',
  );

  static String? name(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Ad soyad zorunludur.';
    if (t.length > 200) return 'En çok 200 karakter.';
    return null;
  }

  static String? phone(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Telefon zorunludur.';
    if (t.length > 40) return 'En çok 40 karakter.';
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) return 'Geçerli bir telefon numarası girin.';
    return null;
  }

  static String? service(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Hizmet zorunludur.';
    if (t.length > 200) return 'En çok 200 karakter.';
    return null;
  }

  /// Boş serbest; doluysa tek ve geçerli adres (backend v16 kuralı).
  static String? email(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    if (t.length > 254 || !_email.hasMatch(t)) {
      return 'Geçerli bir e-posta adresi girin.';
    }
    return null;
  }

  static String? region(String? v) =>
      (v ?? '').trim().length > 200 ? 'En çok 200 karakter.' : null;

  static String? address(String? v) =>
      (v ?? '').trim().length > 500 ? 'En çok 500 karakter.' : null;

  static String? message(String? v) =>
      (v ?? '').trim().length > 2000 ? 'En çok 2000 karakter.' : null;
}

/// Teklif şablonu (`/quote-templates`, yalnız A/M).
@immutable
class QuoteTemplate {
  const QuoteTemplate({
    required this.id,
    required this.name,
    required this.items,
  });
  final String id;
  final String name;
  final List<QuoteItem> items;

  factory QuoteTemplate.fromJson(JsonMap j) => QuoteTemplate(
    id: j.strOr('id'),
    name: j.strOr('name'),
    items: _itemsOf(j['items']),
  );
}

// ---------------------------------------------------------------------------
// Gönderim sonucu (POST /quotes/:offerId/send → 200 / 207 / 502)
// ---------------------------------------------------------------------------

/// Gönderimin DÜRÜST sonucu. "Her zaman gönderildi" göstermek yasaktır.
enum SendOutcome {
  /// Denenen tüm kanallar gitti (200).
  sent,

  /// En az biri gitti, denenen başka kanal hata verdi (207).
  partial,

  /// Hiçbiri gitmedi (502 ya da sunucu hatası).
  failed,
}

@immutable
class ChannelResult {
  const ChannelResult({this.sent = false, this.skipped = false, this.error});
  final bool sent;

  /// Müşterinin e-postası yok vb. (hata sayılmaz).
  final bool skipped;
  final String? error;

  /// Denendi ve gitmedi.
  bool get failed => !sent && !skipped;

  factory ChannelResult.fromJson(JsonMap? j) => j == null
      ? const ChannelResult(skipped: true)
      : ChannelResult(
          sent: j.boolOr('sent'),
          skipped: j.boolOr('skipped'),
          error: j.strOrNull('error'),
        );
}

@immutable
class QuoteSendResult {
  const QuoteSendResult({
    required this.httpStatus,
    required this.outcome,
    this.channel,
    this.status,
    this.error,
    this.message,
    this.whatsapp = const ChannelResult(skipped: true),
    this.email = const ChannelResult(skipped: true),
    this.pdfUrl,
    this.whatsappUrl,
  });

  final int httpStatus;
  final SendOutcome outcome;

  /// "whatsapp" | "email" | "whatsapp,email" | null
  final String? channel;
  final SendStatus? status;
  final String? error;
  final String? message;
  final ChannelResult whatsapp;
  final ChannelResult email;

  /// 10 dk geçerli imzalı bağlantı.
  final String? pdfUrl;
  final String? whatsappUrl;

  List<String> get sentChannelLabels {
    final l = [if (whatsapp.sent) 'WhatsApp', if (email.sent) 'E-posta'];
    if (l.isNotEmpty) return l;
    // Kanal ayrıntısı gelmediyse özet `channel` alanından.
    return (channel ?? '')
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .map(
          (c) => switch (c) {
            'whatsapp' => 'WhatsApp',
            'email' => 'E-posta',
            _ => c,
          },
        )
        .toList();
  }

  List<({String label, String? error})> get failedChannels => [
    if (whatsapp.failed) (label: 'WhatsApp', error: whatsapp.error),
    if (email.failed) (label: 'E-posta', error: email.error),
  ];

  /// Durum kodu + gövdeden DÜRÜST sonuç. Gövde ile durum kodu çelişirse kötümser olan kazanır.
  factory QuoteSendResult.fromResponse(int httpStatus, JsonMap b) {
    final wa = ChannelResult.fromJson(
      b.mapOrNull('channels')?.mapOrNull('whatsapp'),
    );
    final em = ChannelResult.fromJson(
      b.mapOrNull('channels')?.mapOrNull('email'),
    );
    final status = SendStatus.fromApi(b.str('status'));
    final bodySent = b.boolOr('sent', httpStatus != 502 && httpStatus < 500);
    final anyFailed = wa.failed || em.failed;
    final SendOutcome outcome;
    if (httpStatus == 502 ||
        httpStatus >= 500 ||
        !bodySent ||
        status == SendStatus.basarisiz) {
      outcome = SendOutcome.failed;
    } else if (httpStatus == 207 || status == SendStatus.kismen || anyFailed) {
      outcome = SendOutcome.partial;
    } else {
      outcome = SendOutcome.sent;
    }
    return QuoteSendResult(
      httpStatus: httpStatus,
      outcome: outcome,
      channel: b.strOrNull('channel'),
      status: status,
      error: b.strOrNull('error'),
      message: b.strOrNull('message'),
      whatsapp: wa,
      email: em,
      pdfUrl: b.strOrNull('pdfUrl'),
      whatsappUrl: b.strOrNull('whatsappUrl'),
    );
  }

  /// Sunucu hatası (500) ya da ağ hatası: hiçbir şey gönderilmedi sayılır.
  factory QuoteSendResult.failure(String message, {int httpStatus = 500}) =>
      QuoteSendResult(
        httpStatus: httpStatus,
        outcome: SendOutcome.failed,
        error: message,
        message: 'Teklif gönderilemedi.',
      );
}
