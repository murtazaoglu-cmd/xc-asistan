/** Satış hattı / operasyon kuralları: M4 boş takvim · M5 teklif dönüşümü · M6 bekleyen teklif yaşı · M6b cevapsız talep · M6c keşif sonrası teklif yok · M11 geciken iş · M12 satış hattı. */
const { cand, m, A } = require("./_util");

// ---------------- M4 Boş takvim ----------------
const M4 = {
  key: "M4", group: "satis", title: "Boş takvim",
  description: "Önümüzdeki 7 iş gününde (Pzt–Cmt) randevusu olmayan gün sayısı yüksekse ve açık teklif varsa uyarır.",
  defaultParams: { warn_empty_days: 3, critical_empty_days: 5, workdays: 7 },
  async collect(ctx, params, f) {
    const occ = await f.occupancy.occupancy(ctx, { workdays: params.workdays });
    const w = await f.funnel.waitingQuotes(ctx, { mode: "biz" });
    // veri tamlığı kapısı: son 60 günde hiç randevu yoksa ve açık teklif de yoksa (yeni/etkin olmayan kuruluş) alarm üretme
    const clock = require("../../clock");
    const past = await f.agenda.appointmentsBetween(ctx, clock.zonedToUtc(clock.addDays(ctx.date, -60), "00:00", ctx.tz), ctx.dayStart, { mode: "biz", limit: 1 });
    return { ...occ, waiting: w.items.slice(0, 5), waiting_count: w.count, has_history: past.length > 0 || occ.open_offers > 0 };
  },
  evaluate(i, p) {
    if (!i || i.days.length === 0 || i.has_history === false) return [];
    const warn = i.empty_days >= p.warn_empty_days && i.open_offers > 0;
    const critical = i.empty_days >= p.critical_empty_days;
    if (!warn && !critical) return [];
    return [cand("M4", critical ? "critical" : "warn", "M4:next7", {
      vars: { empty: i.empty_days, total: i.days.length, empty_dates: i.empty_dates, open_offers: i.open_offers, waiting_count: i.waiting_count },
      score: i.empty_days * 100000,
      metrics: [m("empty_days", "Boş gün", i.empty_days, "count"), m("workdays", "İncelenen iş günü", i.days.length, "count"), m("open_offers", "Açık teklif", i.open_offers, "count"), m("waiting", "Yanıt bekleyen teklif", i.waiting_count, "count")],
      refs: i.empty_dates.map((d) => ({ type: "date", id: null, label: d })),
      actions: [A.callList(i.waiting.map((w) => ({ name: w.customer_name, phone: w.phone, offer_id: w.id, age_days: w.age_days }))), A.appointment({ dates: i.empty_dates.slice(0, 3) })],
    })];
  },
};

// ---------------- M5 Teklif dönüşümü ----------------
function biggestDrop(list, dim) {
  let best = null;
  for (const x of list || []) {
    if (x.recent.resolved < 3 || x.prev.resolved < 3 || x.recent.rate_bp == null || x.prev.rate_bp == null) continue;
    const drop = x.prev.rate_bp - x.recent.rate_bp;
    if (drop > 0 && (!best || drop > best.drop)) best = { dimension: dim, key: x.key, recent_bp: x.recent.rate_bp, prev_bp: x.prev.rate_bp, drop };
  }
  return best;
}
const M5 = {
  key: "M5", group: "satis", title: "Teklif dönüşümü",
  description: "Kabul oranı = kabul / (kabul + red + 30 günü geçip yanıtsız kalan). Son 90 gün, önceki 90 güne göre belirgin düştüyse bilgilendirir (neden iddia edilmez).",
  defaultParams: { warn_ratio_bp: 7000, critical_ratio_bp: 5000, abs_critical_bp: 1500, min_resolved: 5 },
  async collect(ctx, params, f) { return ctx.canFinance ? f.funnel.conversion(ctx, { mode: "biz" }) : null; },
  evaluate(i, p) {
    if (!i) return [];
    const { recent, prev } = i;
    if (recent.resolved < p.min_resolved || prev.resolved < p.min_resolved || !prev.rate_bp || recent.rate_bp == null) return [];
    const ratio = Math.round((recent.rate_bp * 10000) / prev.rate_bp);
    const critical = ratio < p.critical_ratio_bp || recent.rate_bp < p.abs_critical_bp;
    const warn = ratio < p.warn_ratio_bp;
    if (!critical && !warn) return [];
    const drop = [biggestDrop(i.by_service, "service"), biggestDrop(i.by_source, "source")].filter(Boolean).sort((a, b) => b.drop - a.drop)[0] || null;
    return [cand("M5", critical ? "critical" : "warn", "M5:conversion", {
      vars: { recent_bp: recent.rate_bp, prev_bp: prev.rate_bp, ratio_bp: ratio, drop },
      score: prev.rate_bp - recent.rate_bp,
      metrics: [m("recent", "Son 90 gün kabul oranı", recent.rate_bp, "bp"), m("prev", "Önceki 90 gün kabul oranı", prev.rate_bp, "bp"), m("ratio", "Önceki döneme oranı", ratio, "bp"),
        m("recent_resolved", "Son dönem sonuçlanan", recent.resolved, "count"), m("prev_resolved", "Önceki dönem sonuçlanan", prev.resolved, "count")],
      refs: drop ? [{ type: drop.dimension, id: null, label: drop.key }] : [], actions: [A.screen("offers", { status: "Reddedildi" })],
    })];
  },
};

// ---------------- M6 Bekleyen teklif yaşı ----------------
const M6 = {
  key: "M6", group: "satis", title: "Bekleyen teklif yaşı",
  description: "Teklif verilmiş ve yanıt gelmemiş talepler: 3 gün uyarı, 7 gün kritik, 21 gün 'kapatmayı düşün'.",
  defaultParams: { warn_days: 3, critical_days: 7, close_suggest_days: 21 },
  async collect(ctx, params, f) { return f.funnel.waitingQuotes(ctx, { mode: ctx.canFinance ? "biz" : "ops" }); },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const w of i.items) {
      if (w.age_days < p.warn_days) continue;
      const critical = w.age_days >= p.critical_days;
      out.push(cand("M6", critical ? "critical" : "warn", `M6:offer:${w.id}`, {
        entity: { type: "offer", id: w.id }, score: (w.quote_total_kurus || 0) + w.age_days * 1000,
        vars: { name: w.customer_name, code: w.code, age: w.age_days, total: w.quote_total_kurus, service: w.service, close: w.age_days >= p.close_suggest_days },
        metrics: [m("age", "Gün", w.age_days, "days"), ...(w.quote_total_kurus != null ? [m("total", "Teklif tutarı", w.quote_total_kurus, "kurus")] : []), m("close", "Kapatma eşiği (gün)", p.close_suggest_days, "days")],
        refs: [{ type: "offer", id: w.id, label: `${w.code} · ${w.customer_name}` }],
        actions: [A.call({ phone: w.phone, name: w.customer_name, offer_id: w.id }), A.whatsapp({ template: "teklif_takip", phone: w.phone, name: w.customer_name, offer_id: w.id, vars: { service: w.service } }),
          A.reminder({ title: `Teklif takibi: ${w.customer_name}`, offer_id: w.id, name: w.customer_name, phone: w.phone }), A.open("offer", w.id)],
      }));
    }
    return out;
  },
};

// ---------------- M6b Cevapsız talep ----------------
const M6b = {
  key: "M6b", group: "satis", title: "Cevapsız talep",
  description: "'Yeni' durumunda bekleyen talepler: 4 iş saati uyarı, 24 saat kritik.",
  defaultParams: { warn_work_hours: 4, critical_hours: 24 },
  async collect(ctx, params, f) { return f.funnel.unansweredRequests(ctx, { mode: ctx.canFinance ? "biz" : "ops" }); },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const r of i.items) {
      const critical = r.hours >= p.critical_hours;
      if (!critical && r.work_hours < p.warn_work_hours) continue;
      out.push(cand("M6b", critical ? "critical" : "warn", `M6b:offer:${r.id}`, {
        entity: { type: "offer", id: r.id }, score: Math.round(r.hours * 100),
        vars: { name: r.customer_name, code: r.code, hours: Math.floor(r.hours), work_hours: Math.floor(r.work_hours), service: r.service, created_at: r.created_at },
        metrics: [m("hours", "Geçen saat", Math.floor(r.hours), "hours"), m("work_hours", "İş saati", Math.floor(r.work_hours), "hours")],
        refs: [{ type: "offer", id: r.id, label: `${r.code} · ${r.customer_name}` }],
        actions: [A.call({ phone: r.phone, name: r.customer_name, offer_id: r.id }), A.open("offer", r.id)],
      }));
    }
    return out;
  },
};

// ---------------- M6c Keşif sonrası teklif yok ----------------
const M6c = {
  key: "M6c", group: "satis", title: "Keşif sonrası teklif yok",
  description: "'Keşif Planlandı' durumunda, keşif tarihi geçmiş ama teklif hazırlanmamış talepler: 2 gün uyarı, 5 gün kritik.",
  defaultParams: { warn_days: 2, critical_days: 5 },
  async collect(ctx, params, f) { return f.funnel.visitWithoutQuote(ctx, { mode: ctx.canFinance ? "biz" : "ops" }); },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const v of i.items) {
      if (v.age_days < p.warn_days) continue;
      out.push(cand("M6c", v.age_days >= p.critical_days ? "critical" : "warn", `M6c:offer:${v.id}`, {
        entity: { type: "offer", id: v.id }, score: v.age_days * 1000,
        vars: { name: v.customer_name, code: v.code, age: v.age_days, service: v.service, visit_at: v.last_visit_at },
        metrics: [m("age", "Gün", v.age_days, "days")], refs: [{ type: "offer", id: v.id, label: `${v.code} · ${v.customer_name}` }],
        actions: [A.open("offer", v.id), A.call({ phone: v.phone, name: v.customer_name, offer_id: v.id }), A.reminder({ title: `Teklif hazırla: ${v.customer_name}`, offer_id: v.id, name: v.customer_name, phone: v.phone, plusDays: 0 })],
      }));
    }
    return out;
  },
};

// ---------------- M11 Geciken iş ----------------
const M11 = {
  key: "M11", group: "operasyon", title: "Geciken iş",
  description: "Planlanan teslim (bitiş) tarihi geçmiş ve tamamlanmamış işler: 1 gün uyarı, 7 gün kritik.",
  defaultParams: { warn_days: 1, critical_days: 7 },
  async collect(ctx, params, f) { return f.agenda.overdueJobs(ctx, { mode: ctx.canFinance ? "biz" : "ops" }); },
  evaluate(i, p) {
    if (!i) return [];
    const out = [];
    for (const j of i.items) {
      if (j.days_overdue < p.warn_days) continue;
      out.push(cand("M11", j.days_overdue >= p.critical_days ? "critical" : "warn", `M11:project:${j.id}`, {
        entity: { type: "project", id: j.id }, score: j.days_overdue * 1000,
        vars: { name: j.customer_name, code: j.code, stage: j.stage, days: j.days_overdue, end_date: j.end_date, service: j.service },
        metrics: [m("days", "Gecikme (gün)", j.days_overdue, "days"), m("end_date", "Planlanan teslim", j.end_date, "date")],
        refs: [{ type: "project", id: j.id, label: `${j.code} · ${j.customer_name}` }],
        actions: [A.open("project", j.id), A.reminder({ title: `Müşteriye bilgi ver: ${j.customer_name}`, project_id: j.id, name: j.customer_name, plusDays: 0 })],
      }));
    }
    return out;
  },
};

// ---------------- M12 Satış hattı zayıf ----------------
const M12 = {
  key: "M12", group: "satis", title: "Satış hattı zayıf",
  description: "Açık tekliflerin (kabul oranıyla ağırlıklı) beklenen geliri, gelecek 60 günün sabit giderleri + hedefi karşılamıyorsa uyarır.",
  defaultParams: { warn_x_bp: 12000, critical_x_bp: 10000, horizon_days: 60, target_kurus: 0, min_resolved: 5 },
  async collect(ctx, params, f) {
    if (!ctx.canFinance) return null;
    const [w, conv, fixed] = await Promise.all([f.funnel.waitingQuotes(ctx, { mode: "biz" }), f.funnel.conversion(ctx, { mode: "biz" }), f.pnl.monthlyFixedTotal(ctx)]);
    return { pipeline: w.total_kurus || 0, open_count: w.count, rate_bp: conv.recent.rate_bp, resolved: conv.recent.resolved, fixed_month: fixed };
  },
  evaluate(i, p) {
    if (!i || i.rate_bp == null || i.resolved < p.min_resolved) return [];
    const need = Math.round((i.fixed_month * p.horizon_days) / 30) + p.target_kurus;
    if (need <= 0) return [];
    const expected = Math.round((i.pipeline * i.rate_bp) / 10000);
    const ratio = Math.round((expected * 10000) / need);
    const sev = ratio < p.critical_x_bp ? "critical" : ratio < p.warn_x_bp ? "warn" : null;
    if (!sev) return [];
    return [cand("M12", sev, "M12:pipeline", {
      vars: { pipeline: i.pipeline, open_count: i.open_count, rate_bp: i.rate_bp, expected, need, ratio_bp: ratio, days: p.horizon_days }, score: need - expected,
      metrics: [m("pipeline", "Açık teklif toplamı", i.pipeline, "kurus"), m("rate", "Son 90 gün kabul oranı", i.rate_bp, "bp"), m("expected", "Beklenen gelir", expected, "kurus"), m("need", `${p.horizon_days} gün sabit gider + hedef`, need, "kurus"), m("ratio", "Karşılama (×)", ratio, "bp")],
      actions: [A.screen("offers", { status: "Teklif Verildi" })],
    })];
  },
};

module.exports = [M4, M5, M6, M6b, M6c, M11, M12];
