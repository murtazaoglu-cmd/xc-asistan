/**
 * Müdür cümle şablonları (Türkçe; çoğul/ek uyumu kodda) + önerilen aksiyon metadatası.
 * Sektöre özel SABİT ifade yoktur: terimler T (text/terms.js; org_settings sektör sözlüğü) üzerinden gelir.
 * Tüm sayılar adaydan (facts → kural) gelir; burada hiçbir değer HESAPLANMAZ, yalnız biçimlenir.
 */
const tr = require("../text/tr");
const { waDigits, telUri, tomorrowAt } = require("./rules/_util");

const { formatTL: TL, formatPct: PCT } = tr;
const fn = (name) => tr.firstName(name) || "müşteri";
/** "Ahmet'e" gibi özel ad + ek */
const nm = (name, kind) => tr.ek(fn(name), kind, { proper: true });
const D = (ymd) => tr.formatDate(ymd);
const dayShort = (ymd) => `${tr.formatDateShort(ymd)} ${tr.weekdayName(ymd)}`;
const hrs = (n) => `${n} saat`;

/** Her kural için {title(v,T), body(v,T)} */
const TEXT = {
  M1: {
    title: (v, T, s) => (s === "critical" ? `Bu ay net ${TL(v.net)} — nakit açığı var` : `Ay-içi nakit dengesi zayıf: net ${TL(v.net)}`),
    body: (v, T) => {
      let t = `Bu ayki ${T.lc("payments")} ${TL(v.collected)}, işletme giderleri ${TL(v.expense)}; net ${TL(v.net)}.`;
      if (v.fixed_pending > 0) t += ` Ay sonuna kadar uygulanmamış sabit gider ${TL(v.fixed_pending)} daha var (tahmini toplam gider ${TL(v.projected)}).`;
      if (v.home > 0) t += ` Kişisel giderler (${TL(v.home)}) hesaba dahil değil.`;
      if (v.delivered_count > 0) {
        t += ` Teslim edilip bakiyesi açık ${T.n(v.delivered_count, "job")} var (toplam ${TL(v.delivered_total)}).`;
        if (v.top[0]) t += ` Önce ${v.top[0].customer_name} (${TL(v.top[0].balance)}, ${v.top[0].age_days} gündür açık).`;
      }
      return t;
    },
  },
  M2: {
    title: (v, T) => `${v.name}: ${TL(v.balance)} ${T.lc("payment")} bekliyor, ${v.age} gündür açık`,
    body: (v, T) => `${v.name} için ${T.lc("job")} '${v.stage}' aşamasına geçeli ${v.age} gün oldu; kalan bakiye ${TL(v.balance)} (sözleşme+ilave ${TL(v.contract)}, tahsil edilen ${TL(v.paid)}). ${nm(v.name, "dat")} nazik bir hatırlatma göndermek ya da aramak iyi olabilir.`,
  },
  M2b: {
    title: (v) => `Son ${v.window_days} günde tahsilat oranı ${PCT(v.rate_bp)}`,
    body: (v, T) => `Son ${v.window_days} günde başlayan ${T.n(v.n, "job")} için sözleşme toplamı ${TL(v.contract)}; tahsil edilen ${TL(v.paid)} (${PCT(v.rate_bp)}). Avans ya da ara ödeme koşulu eklemek bu oranı yükseltebilir.`,
  },
  M3: {
    title: (v) => `${v.service}: kâr marjı ${PCT(v.margin_bp)}`,
    body: (v, T) => `Son ${v.months} ayda masrafı onaylanmış ${T.n(v.n, "job")} için ortalama marj ${PCT(v.margin_bp)} (gelir ${TL(v.contract)}, bağlı gider ${TL(v.cost)}). ${T.cap("offer")} birim fiyatlarının güncel maliyeti karşılayıp karşılamadığına bakmak ister misiniz?`,
  },
  M3b: {
    title: (v) => `Kâr marjı ${PCT(v.drop_bp)} puan düştü`,
    body: (v, T) => `Son 90 günün marjı ${PCT(v.recent_bp)}, önceki 90 günün ${PCT(v.prev_bp)} (${v.recent_n} ve ${v.prev_n} ${T.lc("job")}, yalnız masrafı onaylılar). Maliyet kalemlerine bakmak için ${T.lc("expenses")} listesini açabilirsiniz.`,
  },
  M4: {
    title: (v) => `Önümüzdeki ${v.total} iş gününün ${v.empty} günü boş`,
    body: (v, T) => `${tr.joinList(v.empty_dates.slice(0, 4).map(dayShort))} günlerinde ${T.lc("appointment")} yok. ${v.open_offers > 0 ? `${v.open_offers} açık ${T.lc("offer")} var${v.waiting_count ? `, ${v.waiting_count} tanesi yanıt bekliyor` : ""}; birkaçını aramak ${T.lc("visit")} doldurabilir.` : `Yeni ${T.lc("customers")} için aramalar ya da paylaşımlar yapmak için uygun bir fırsat.`}`,
  },
  M5: {
    title: (v, T) => `${T.cap("offer")} kabul oranı ${PCT(v.recent_bp)} (önceki dönem ${PCT(v.prev_bp)})`,
    body: (v, T) => {
      let t = `Son 90 günde ${T.lc("offer")} kabul oranı ${PCT(v.recent_bp)}, önceki 90 günde ${PCT(v.prev_bp)}.`;
      if (v.drop) t += ` Düşüş en çok "${v.drop.key}" ${v.drop.dimension === "source" ? "kaynağında" : "türünde"} görülüyor (${PCT(v.drop.prev_bp)} → ${PCT(v.drop.recent_bp)}).`;
      return t + " Veri nedenini söylemiyor; bu bir gözlemdir.";
    },
  },
  M6: {
    title: (v) => `${v.name}: ${v.age} gündür yanıt yok`,
    body: (v, T) => `${v.name} için ${T.lc("offer")} ${v.age} gün önce verildi${v.total != null ? ` (${TL(v.total)})` : ""}. ${nm(v.name, "dat")} kısa bir takip mesajı göndermek ya da aramayı hatırlatmak iyi olabilir.${v.close ? ` ${v.age} gün geçti; kapatmayı düşünebilirsiniz.` : ""}`,
  },
  M6b: {
    title: (v, T) => (v.hours >= 24 ? `${v.name}: ${v.hours} saattir cevap bekleyen ${T.lc("offer")} talebi` : `${v.name}: ${hrs(v.work_hours)} (iş saati) cevap bekliyor`),
    body: (v, T) => `${v.service || T.lc("offer")} talebi henüz ele alınmadı (${tr.formatDate(v.created_at.slice(0, 10))}). Arayarak ${T.lc("visit")} planlayabilirsiniz.`,
  },
  M6c: {
    title: (v, T) => `${v.name}: ${T.lc("visit")} sonrası ${v.age} gündür ${T.lc("offer")} yok`,
    body: (v, T) => `${T.cap("visit")} ${D(v.visit_at.slice(0, 10))} tarihinde yapıldı ama henüz ${T.lc("offer")} hazırlanmadı. ${T.cap("visit")} notlarından ${T.lc("offer")} başlatmak için iyi bir zaman.`,
  },
  M7: {
    title: (v) => `${v.name}: ${TL(v.unbilled)} faturasız tahsilat`,
    body: (v) => `${v.name} için ${TL(v.paid)} tahsil edildi, kayıtlı fatura toplamı ${TL(v.invoiced)}; ${TL(v.unbilled)} faturasız görünüyor (${v.age_days} gündür). Fatura kaydı eklemek ya da mali müşavirinize iletmek gerekebilir.`,
  },
  M8: {
    title: (v) => (v.left < 0 ? `KDV son günü geçti: tahmini ${TL(v.payable)}` : `KDV son günü ${D(v.due)}: tahmini ödenecek ${TL(v.payable)}`),
    body: (v) => `${v.period} dönemi KDV beyan/ödeme son günü ${D(v.due)} (${v.left < 0 ? `${-v.left} gün geçti` : `${v.left} gün kaldı`}). Tahmini ödenecek tutar ${TL(v.payable)}; ay sonu nakit tahmini ${TL(v.cash)}. Bu tutarlar tahminidir; mali müşavirinizle teyit edin.`,
  },
  M9: {
    title: (v) => `${v.category}: bu ay giderler ${PCT(v.jump_bp)} arttı`,
    body: (v) => `${v.category} gideri bu ay şimdiden ${TL(v.current)}; önceki 3 ayın aylık ortalaması ${TL(v.avg)}. Kalemleri inceleyin.`,
  },
  M10: {
    title: (v, T) => `Tahsilatın ${PCT(v.share_bp)} kadarı tek ${T.ek("customer", "abl")}`,
    body: (v, T) => `Son ${v.days} günde toplam ${TL(v.total)} ${T.lc("payment")} içinde ${TL(v.top)} tutarındaki kısım ${nm(v.name, "abl")} geliyor. Tek ${T.ek("customer", "dat")} bağımlılığı azaltmak için tekrarlayan iş fırsatları aramak bir yol olabilir (bilgi).`,
  },
  M11: {
    title: (v) => `${v.name}: teslim ${v.days} gün gecikti`,
    body: (v, T) => `${v.name} ${T.lc("job")} için planlanan teslim tarihi ${D(v.end_date)}; şu an '${v.stage}' aşamasında. ${nm(v.name, "dat")} bilgi vermek iyi olabilir.`,
  },
  M12: {
    title: () => "Satış hattı zayıf: beklenen gelir sabit gideri karşılamıyor",
    body: (v, T) => `Yanıt bekleyen ${T.n(v.open_count, "offer")} toplamı ${TL(v.pipeline)}; son 90 gün kabul oranıyla (${PCT(v.rate_bp)}) beklenen ${TL(v.expected)}. Önümüzdeki ${v.days} günün sabit giderleri ${TL(v.need)}. Yeni talep kaynağı ya da eski ${T.lc("customers")} aramak hattı güçlendirebilir.`,
  },
  M13: {
    title: (v) => `Geçen yılın aynı dönemine göre tahsilat ${PCT(v.drop_bp)} düşük`,
    body: (v, T) => `${tr.monthName(v.month + "-01")} ayının ilk ${v.day} gününde ${T.lc("payments")} ${TL(v.current)}; geçen yıl aynı dönemde ${TL(v.last_year)}. Mevsimsel dalgalanma olabilir; bu bir bilgidir.`,
  },
};

const unitDisplay = (value, unit) => {
  switch (unit) {
    case "kurus": return TL(value);
    case "bp": return PCT(value);
    case "days": return `${value} gün`;
    case "hours": return `${value} saat`;
    case "date": return D(String(value));
    default: return String(value);
  }
};
function renderMetrics(metrics) { return metrics.map((x) => ({ ...x, display: unitDisplay(x.value, x.unit) })); }

/** Müşteriye gidecek hazır WhatsApp metin şablonları (kod → metin). Gerçek gönderim istemcide wa.me ile yapılır. */
const WA = {
  odeme_hatirlatma: (v, T) => `Merhaba ${fn(v.name)}, ${T.lc("job")} ile ilgili ${TL(v.amount_kurus)} tutarındaki bakiye için nazikçe hatırlatma yapmak istedim. Uygun olduğunuzda dönüş yapabilir misiniz? Teşekkürler.`,
  teklif_takip: (v, T) => `Merhaba ${fn(v.name)}, size ilettiğimiz ${T.ek("offer", "acc")} değerlendirme fırsatınız oldu mu? Sormak istediğiniz bir şey olursa yardımcı olurum.`,
  is_bilgilendirme: (v, T) => `Merhaba ${fn(v.name)}, ${T.lc("job")} teslim tarihiyle ilgili sizi bilgilendirmek istiyorum. Uygun bir zamanda arayabilir miyim?`,
  randevu_teyit: (v, T) => `Merhaba ${fn(v.name)}, ${v.date ? D(v.date) : "yakında"}${v.time ? ` saat ${v.time}` : ""} için ${T.lc("appointment")}nizi teyit etmek istedim. Uygun mu?`,
};
const WA_LABEL = { odeme_hatirlatma: "Hatırlatma taslağı", teklif_takip: "Takip mesajı", is_bilgilendirme: "Bilgi mesajı", randevu_teyit: "Teyit mesajı" };

function waText(template, vars, T) { const f = WA[template]; return f ? f(vars || {}, T) : ""; }

/** Aksiyon niyetlerini uygulamanın kullanacağı metadataya çevirir. Uygulamayı B/C'nin uçları yapar (endpoint alanı mevcut uçları işaret eder). */
function buildActions(intents, T, env) {
  const out = [];
  const seen = new Set();
  for (const a of intents || []) {
    let x = null;
    switch (a.type) {
      case "reminder":
        x = { type: "reminder.create", label: "Hatırlat", endpoint: { method: "POST", path: "/api/reminders" },
          body: { title: String(a.title).slice(0, 200), remind_at: tomorrowAt(env.date, "09:00", a.plusDays, env.tz), ...(a.project_id ? { project_id: a.project_id } : {}), note: "Müdür önerisinden" } };
        break;
      case "call": { const tel = telUri(a.phone); if (tel) x = { type: "call", label: a.name ? `Ara: ${fn(a.name)}` : "Ara", phone: a.phone, tel_uri: tel }; break; }
      case "whatsapp": {
        const d = waDigits(a.phone);
        const text = waText(a.template, { name: a.name, ...(a.vars || {}) }, T);
        if (d && text) x = { type: "whatsapp.template", label: WA_LABEL[a.template] || "WhatsApp", template_code: a.template, phone: a.phone, text, url: `https://wa.me/${d}?text=${encodeURIComponent(text)}` };
        break;
      }
      case "appointment":
        x = { type: "appointment.create", label: `${T.cap("appointment")} ekle`, endpoint: { method: "POST", path: "/api/appointments" },
          body: { type: T.get("visit"), ...(a.name ? { customer_name: a.name } : {}), ...(a.phone ? { customer_phone: a.phone } : {}), ...(a.offer_id ? { offer_id: a.offer_id } : {}), ...(a.project_id ? { project_id: a.project_id } : {}) },
          suggested_dates: a.dates };
        break;
      case "open": x = { type: "open", label: "Aç", entity_type: a.entity_type, id: a.id }; break;
      case "call_list": if (a.items && a.items.length) x = { type: "call_list", label: "Arama listesi", items: a.items.map((i) => ({ ...i, tel_uri: telUri(i.phone) })) }; break;
      case "screen": x = { type: "screen", label: "Göster", screen: a.screen, params: a.params }; break;
      default: break;
    }
    if (!x) continue;
    const key = JSON.stringify([x.type, x.template_code, x.phone, x.entity_type, x.id, x.screen, x.body && x.body.title]);
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(x);
    if (out.length >= 8) break;
  }
  return out;
}

/** Aday → {title, body, evidence, actions} */
function render(c, T, env) {
  const t = TEXT[c.rule];
  const title = t ? t.title(c.vars, T, c.severity) : c.rule;
  const body = t ? t.body(c.vars, T, c.severity) : "";
  return {
    title: title.slice(0, 200), body,
    evidence: { rule: c.rule, severity: c.severity, metrics: renderMetrics(c.metrics), refs: c.refs, why: `${c.rule}: ${body}` },
    actions: buildActions(c.actions, T, env),
  };
}

module.exports = { render, buildActions, renderMetrics, waText, WA, TEXT, unitDisplay };
