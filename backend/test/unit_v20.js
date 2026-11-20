// v20 birim testleri (VERİTABANSIZ, saf): Türkçe metin yardımcıları, sektör sözlüğü, M kurallarının eşik/sınır/kuruş değerlendirmesi,
// şablon üretimi, aksiyon metadatası, tekrar/erteleme hesapları. Çalıştırma: node test/unit_v20.js
const tr = require("../src/assistant/text/tr");
const { makeTerms } = require("../src/assistant/text/terms");
const { RULES, BY_KEY, validateParams } = require("../src/assistant/manager/catalog");
const templates = require("../src/assistant/manager/templates");
const rem = require("../src/assistant/reminders/service");
const { waDigits, telUri } = require("../src/assistant/manager/rules/_util");
const clock = require("../src/assistant/clock");

let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 500) : ""); } };
const eq = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), m, { got: a, want: b });
const ev = (key, input, over = {}) => { const r = BY_KEY.get(key); return r.evaluate(input, { ...r.defaultParams, ...over }); };
const T = makeTerms({});
const env = { date: "2026-11-20", tz: "Europe/Istanbul" };

// ---- tr.js ----
eq(tr.formatTL(1245000), "₺12.450,00", "formatTL 12.450,00");
eq(tr.formatTL(-5650000), "-₺56.500,00", "formatTL negatif");
eq(tr.formatTL(5), "₺0,05", "formatTL kuruş");
eq(tr.formatTL(100000000), "₺1.000.000,00", "formatTL milyon");
eq(tr.formatTL(0), "₺0,00", "formatTL sıfır");
eq(tr.formatTL(1999.6), "₺20,00", "formatTL yuvarlama");
eq(tr.formatPct(1450), "%14,5", "formatPct 14,5");
eq(tr.formatPct(7000), "%70", "formatPct 70");
eq(tr.formatPct(9999), "%100", "formatPct taşma yuvarlama");
eq(tr.ratioBp(1, 3), 3333, "ratioBp");
eq(tr.ratioBp(1, 0), null, "ratioBp payda 0");
eq(tr.formatDate("2026-11-20"), "20 Kas 2026", "formatDate");
eq(tr.weekdayName("2026-11-20"), "Cuma", "weekdayName");
eq(tr.daysBetween("2026-11-20", "2026-12-01"), 11, "daysBetween");
eq(tr.relativeDay("2026-11-21", "2026-11-20"), "Yarın", "relativeDay yarın");
eq(tr.relativeDay("2026-11-17", "2026-11-20"), "3 gün önce", "relativeDay geçmiş");
eq(tr.ek("Ahmet", "dat", { proper: true }), "Ahmet'e", "ek özel ad dat");
eq(tr.ek("Elif", "dat", { proper: true }), "Elif'e", "ek Elif");
eq(tr.ek("Ali", "abl", { proper: true }), "Ali'den", "ek abl");
eq(tr.ek("teklif", "poss"), "teklifi", "ek poss");
eq(tr.ek("randevu", "poss"), "randevusu", "ek poss ünlü sonlu");
eq(tr.ek("proje", "dat"), "projeye", "ek dat ünlü sonlu");
eq(tr.ek("müşteri", "gen"), "müşterinin", "ek gen");
eq(tr.ek("ayak", "dat"), "ayağa", "ek k→ğ");
eq(tr.ek("iş", "loc"), "işte", "ek loc sert ünsüz");
eq(tr.plural("randevu"), "randevular", "plural a");
eq(tr.plural("teklif"), "teklifler", "plural e");
eq(tr.joinList(["a", "b", "c"]), "a, b ve c", "joinList");
eq(tr.countPhrase(3, "Randevu"), "3 randevu", "countPhrase tekil");
eq(tr.firstName("Ayşe Yılmaz"), "Ayşe", "firstName");

// ---- terms ----
eq(T.get("job"), "İş", "terms varsayılan job");
eq(makeTerms({ job: "Proje" }).lc("jobs") === "işler", true, "terms çoğul anahtar varsayılanı korunur");
eq(makeTerms({ job: "Proje" }).n(3, "job"), "3 proje", "terms n");
eq(makeTerms({ job: "  " }).get("job"), "İş", "terms boş değer → varsayılan");
eq(makeTerms({ visit: "Keşif" }).get("visit"), "Keşif", "terms özel");

// ---- telefon ----
eq(waDigits("0532 123 45 67"), "905321234567", "waDigits 0'lı");
eq(waDigits("532 123 45 67"), "905321234567", "waDigits 10 hane");
eq(waDigits("+90 532 123 45 67"), "905321234567", "waDigits +90");
eq(waDigits("123"), null, "waDigits kısa");
eq(telUri("05321234567"), "tel:+905321234567", "telUri");

// ---- katalog ----
eq(RULES.map((r) => r.key), ["M1", "M2", "M2b", "M3", "M3b", "M4", "M5", "M6", "M6b", "M6c", "M7", "M8", "M9", "M10", "M11", "M12", "M13"], "katalog sırası");
ok(RULES.every((r) => r.defaultParams && typeof r.evaluate === "function" && typeof r.collect === "function" && r.title && r.description), "her kural tam");
eq(RULES.filter((r) => r.requires).map((r) => r.key), ["M7", "M8"], "yalnız M7/M8 bağımlı");
ok(validateParams(BY_KEY.get("M6"), { warn_days: 2 }).value.warn_days === 2, "validateParams geçerli");
ok(validateParams(BY_KEY.get("M6"), { yok: 1 }).error, "validateParams bilinmeyen");
ok(validateParams(BY_KEY.get("M6"), { warn_days: 1.5 }).error, "validateParams ondalık");
ok(validateParams(BY_KEY.get("M6"), { warn_days: -1 }).error, "validateParams negatif");

// ---- M1 ----
{
  const base = { month: "2026-11", day_of_month: 20, collected: 1000000, expense: 1200000, home: 0, fixed_pending: 0, projected: 1200000, delivered_total: 0, delivered_count: 0, top: [] };
  let c = ev("M1", base); ok(c.length === 1 && c[0].severity === "critical", "M1 gün≥15 net<0 kritik", c);
  eq(c[0].metrics.find((x) => x.key === "net").value, -200000, "M1 net kuruş");
  c = ev("M1", { ...base, day_of_month: 12 }); ok(c.length === 1 && c[0].severity === "warn", "M1 gün 12 net<0 uyarı");
  c = ev("M1", { ...base, day_of_month: 9 }); eq(c.length, 0, "M1 gün 9 sessiz");
  c = ev("M1", { ...base, expense: 500000, projected: 500000 }); eq(c.length, 0, "M1 sağlıklı net → yok");
  // net/tahsilat tam %15 sınırı (1500 bp): net*10000 < 1500*collected → strict
  c = ev("M1", { ...base, collected: 1000000, expense: 850000, projected: 850000, day_of_month: 12 }); eq(c.length, 0, "M1 net tam %15 → tetiklenmez");
  c = ev("M1", { ...base, collected: 1000000, expense: 850001, projected: 850001, day_of_month: 12 }); eq(c.length, 1, "M1 net %15'in 1 kuruş altı → tetiklenir");
  c = ev("M1", { ...base, collected: 1000000, expense: 500000, projected: 1000001, day_of_month: 12 }); eq(c.length, 1, "M1 tahmini gider > tahsilat");
  eq(ev("M1", { ...base, collected: 0, expense: 0 }).length, 0, "M1 veri yok kapısı");
  const txt = templates.render(ev("M1", base)[0], T, env);
  ok(txt.body.includes("₺2.000,00") || txt.body.includes("-₺2.000,00") || txt.body.includes("₺10.000,00"), "M1 metin tutarı biçimli", txt.body);
}
// ---- M2 ----
{
  const item = (o) => ({ delivered: true, project_id: "p1", customer_name: "Ahmet Kaya", code: "PRJ-1", stage: "Teslim", stage_age_days: 8, balance_kurus: 1245000, contract_kurus: 3000000, extras_kurus: 0, paid_kurus: 1755000, service: "Mutfak", phone: "05321234567", ...o });
  const rec = (items, avg = 1000000) => ({ items, avg_job_kurus: avg });
  let c = ev("M2", rec([item()])); ok(c.length === 1 && c[0].severity === "warn", "M2 8 gün uyarı", c);
  c = ev("M2", rec([item({ stage_age_days: 7 })])); eq(c.length, 0, "M2 tam 7 gün → yok (strict)");
  c = ev("M2", rec([item({ stage_age_days: 22 })])); eq(c[0].severity, "critical", "M2 22 gün kritik");
  c = ev("M2", rec([item({ stage_age_days: 21 })])); eq(c[0].severity, "warn", "M2 tam 21 gün uyarı");
  c = ev("M2", rec([item({ balance_kurus: 2500000 })])); eq(c[0].severity, "critical", "M2 bakiye ≥ taban kritik");
  c = ev("M2", rec([item({ balance_kurus: 2499999 })], 1000000)); eq(c[0].severity, "warn", "M2 taban 1 kuruş altı uyarı");
  c = ev("M2", rec([item({ balance_kurus: 6000000 })], 20000000)); eq(c[0].severity, "critical", "M2 ortalamanın %30'u (6.000.000) eşiği kritik");
  c = ev("M2", rec([item({ balance_kurus: 5999999 })], 20000000)); eq(c[0].severity, "warn", "M2 ortalama eşiğinin 1 kuruş altı uyarı");
  c = ev("M2", rec([item({ balance_kurus: 0 })])); eq(c.length, 0, "M2 bakiye 0 → yok");
  c = ev("M2", rec([item({ delivered: false })])); eq(c.length, 0, "M2 teslim değil → yok");
  const r = templates.render(ev("M2", rec([item()]))[0], T, env);
  ok(r.body.includes("₺12.450,00"), "M2 metin kuruş doğru", r.body);
  ok(r.actions.some((a) => a.type === "whatsapp.template" && a.template_code === "odeme_hatirlatma" && a.url.startsWith("https://wa.me/905321234567?text=")), "M2 WhatsApp şablon aksiyonu");
  ok(r.actions.some((a) => a.type === "call" && a.tel_uri === "tel:+905321234567"), "M2 ara aksiyonu");
  ok(r.actions.some((a) => a.type === "reminder.create" && a.body.remind_at === "2026-11-21T06:00:00.000Z"), "M2 yarın 09:00 İstanbul hatırlatma", r.actions.find((a) => a.type === "reminder.create"));
  ok(r.evidence.metrics.every((x) => x.display !== undefined) && r.evidence.metrics.some((x) => x.key === "balance" && x.value === 1245000), "M2 sayısal dayanak");
}
// ---- M2b ----
{
  eq(ev("M2b", { n: 4, contract: 10000000, paid: 6900000, window_days: 90 })[0].severity, "warn", "M2b %69 uyarı");
  eq(ev("M2b", { n: 4, contract: 10000000, paid: 7000000, window_days: 90 }).length, 0, "M2b tam %70 yok");
  eq(ev("M2b", { n: 4, contract: 10000000, paid: 4990000, window_days: 90 })[0].severity, "critical", "M2b <%50 kritik");
  eq(ev("M2b", { n: 2, contract: 10000000, paid: 0, window_days: 90 }).length, 0, "M2b az iş → yok");
  eq(ev("M2b", null).length, 0, "M2b null (finans yok)");
}
// ---- M3 / M3b ----
{
  const svc = (o) => ({ service: "Mutfak", n: 3, contract: 10000000, cost: 7600000, ...o });
  eq(ev("M3", { services: [svc()], window_months: 12 })[0].severity, "warn", "M3 marj %24 uyarı");
  eq(ev("M3", { services: [svc({ cost: 7500000 })], window_months: 12 }).length, 0, "M3 tam %25 yok");
  eq(ev("M3", { services: [svc({ cost: 8600000 })], window_months: 12 })[0].severity, "critical", "M3 %14 kritik");
  eq(ev("M3", { services: [svc({ n: 2, cost: 9900000 })], window_months: 12 }).length, 0, "M3 <3 iş yok");
  const c = ev("M3", { services: [svc()], window_months: 12 })[0];
  eq(c.metrics.find((x) => x.key === "margin").value, 2400, "M3 marj bp");
  eq(ev("M3b", { recent: { n: 3, contract: 10000000, cost: 7000000 }, prev: { n: 3, contract: 10000000, cost: 6000000 } })[0].severity, "warn", "M3b 10 puan düşüş uyarı");
  eq(ev("M3b", { recent: { n: 3, contract: 10000000, cost: 7600000 }, prev: { n: 3, contract: 10000000, cost: 6000000 } })[0].severity, "critical", "M3b >15 puan kritik");
  eq(ev("M3b", { recent: { n: 3, contract: 10000000, cost: 6800000 }, prev: { n: 3, contract: 10000000, cost: 6000000 } }).length, 0, "M3b tam 8 puan yok");
  eq(ev("M3b", { recent: { n: 2, contract: 10000000, cost: 9000000 }, prev: { n: 3, contract: 10000000, cost: 6000000 } }).length, 0, "M3b az iş yok");
}
// ---- M4 ----
{
  const occ = (o) => ({ days: new Array(7).fill({}), empty_days: 3, empty_dates: ["2026-11-23", "2026-11-24", "2026-11-25"], open_offers: 2, waiting: [{ customer_name: "A", phone: "05321234567", id: "o1", age_days: 4 }], waiting_count: 1, has_history: true, ...o });
  eq(ev("M4", occ())[0].severity, "warn", "M4 3 boş + açık teklif uyarı");
  eq(ev("M4", occ({ open_offers: 0 })).length, 0, "M4 3 boş ama açık teklif yok");
  eq(ev("M4", occ({ empty_days: 2 })).length, 0, "M4 2 boş yok");
  eq(ev("M4", occ({ empty_days: 5, open_offers: 0 }))[0].severity, "critical", "M4 5 boş kritik");
  eq(ev("M4", occ({ empty_days: 5, has_history: false })).length, 0, "M4 veri tamlığı kapısı");
  const r = templates.render(ev("M4", occ())[0], T, env);
  ok(r.actions.some((a) => a.type === "call_list") && r.actions.some((a) => a.type === "appointment.create"), "M4 arama listesi + randevu ekle aksiyonu");
}
// ---- M5 ----
{
  const conv = (rr, pr, n = 10) => ({ recent: { resolved: n, rate_bp: rr }, prev: { resolved: n, rate_bp: pr }, by_service: [], by_source: [] });
  eq(ev("M5", conv(4900, 8000))[0].severity, "warn", "M5 oran %61 → uyarı");
  eq(ev("M5", conv(3900, 8000))[0].severity, "critical", "M5 oran <%50 kritik");
  eq(ev("M5", conv(4000, 8000))[0].severity, "warn", "M5 tam %50 uyarı (strict)");
  eq(ev("M5", conv(5600, 8000)).length, 0, "M5 tam %70 yok");
  eq(ev("M5", conv(1000, 1500))[0].severity, "critical", "M5 mutlak %15 altı kritik");
  eq(ev("M5", conv(2000, 8000, 4)).length, 0, "M5 az örnek yok");
}
// ---- M6 / M6b / M6c / M11 ----
{
  const w = (age) => ({ items: [{ id: "o1", age_days: age, customer_name: "Ayşe", code: "TKL-1", phone: "05321234567", quote_total_kurus: 4500050, service: "Kapı" }] });
  eq(ev("M6", w(2)).length, 0, "M6 2 gün yok");
  eq(ev("M6", w(3))[0].severity, "warn", "M6 3 gün uyarı");
  eq(ev("M6", w(7))[0].severity, "critical", "M6 7 gün kritik");
  const r = templates.render(ev("M6", w(22))[0], T, env);
  ok(r.body.includes("₺45.000,50"), "M6 kuruş doğru", r.body);
  ok(/kapat/i.test(r.body), "M6 21+ gün 'kapatmayı düşün'", r.body);
  const u = (h, wh) => ({ items: [{ id: "o2", hours: h, work_hours: wh, customer_name: "Can", code: "TKL-2", phone: null, service: "Kapı", created_at: "2026-11-20T05:00:00Z" }] });
  eq(ev("M6b", u(5, 3)).length, 0, "M6b 3 iş saati yok");
  eq(ev("M6b", u(6, 4))[0].severity, "warn", "M6b 4 iş saati uyarı");
  eq(ev("M6b", u(24, 2))[0].severity, "critical", "M6b 24 saat kritik");
  const v = (age) => ({ items: [{ id: "o3", age_days: age, customer_name: "Eda", code: "TKL-3", phone: "05321234567", service: "Kapı", last_visit_at: "2026-11-18T08:00:00Z" }] });
  eq(ev("M6c", v(1)).length, 0, "M6c 1 gün yok");
  eq(ev("M6c", v(2))[0].severity, "warn", "M6c 2 gün uyarı");
  eq(ev("M6c", v(5))[0].severity, "critical", "M6c 5 gün kritik");
  const j = (d) => ({ items: [{ id: "p9", days_overdue: d, customer_name: "Su", code: "PRJ-9", stage: "Üretim", end_date: "2026-11-10", service: "Mutfak" }] });
  eq(ev("M11", j(0)).length, 0, "M11 0 gün yok");
  eq(ev("M11", j(1))[0].severity, "warn", "M11 1 gün uyarı");
  eq(ev("M11", j(7))[0].severity, "critical", "M11 7 gün kritik");
}
// ---- M7 / M8 ----
{
  const it = (o) => ({ project_id: "p1", code: "PRJ-1", name: "Veli", phone: null, unbilled: 500000, since: "2026-11-01", age_days: 19, invoiced: 0, paid: 500000, ...o });
  eq(ev("M7", { items: [it({ age_days: 7 })], days_to_month_end: 10 }).length, 0, "M7 7 gün yok");
  eq(ev("M7", { items: [it({ age_days: 8 })], days_to_month_end: 10 })[0].severity, "warn", "M7 8 gün uyarı");
  eq(ev("M7", { items: [it({ age_days: 31 })], days_to_month_end: 10 })[0].severity, "critical", "M7 31 gün kritik");
  eq(ev("M7", { items: [it({ age_days: 8 })], days_to_month_end: 4 })[0].severity, "critical", "M7 ay sonu <5 gün kritik");
  const v = (due, payable, cash) => ({ periods: [{ period: "2026-10", payable, due }], cash_estimate: cash, date: "2026-11-20" });
  eq(ev("M8", v("2026-11-28", 1000000, 5000000)).length, 0, "M8 8 gün kala yok");
  eq(ev("M8", v("2026-11-27", 1000000, 5000000))[0].severity, "warn", "M8 7 gün kala uyarı");
  eq(ev("M8", v("2026-11-21", 6000000, 5000000))[0].severity, "critical", "M8 1 gün + nakit yetmez kritik");
  eq(ev("M8", v("2026-11-21", 1000000, 5000000))[0].severity, "warn", "M8 1 gün + nakit yeter uyarı");
  eq(ev("M8", v("2026-11-19", 1000000, 5000000))[0].severity, "critical", "M8 gecikmiş kritik");
  eq(ev("M8", v("2026-11-21", 0, 0)).length, 0, "M8 ödenecek yok");
  ok(BY_KEY.get("M8").scopes.includes("business"), "M8 yalnız işletme kapsamı");
}
// ---- M9 / M10 / M12 / M13 ----
{
  const cat = (cur, prev) => ({ month: "2026-11", months_with_data: 3, categories: [{ category: "Yakıt", current: cur, prev_total: prev }] });
  eq(ev("M9", cat(1500000, 3000000))[0].severity, "warn", "M9 +%50 uyarı");
  eq(ev("M9", cat(1400000, 3000000)).length, 0, "M9 tam +%40 yok");
  eq(ev("M9", cat(1900000, 3000000))[0].severity, "critical", "M9 +%90 kritik");
  eq(ev("M9", cat(500000, 300000)).length, 0, "M9 alt tutar tabanı (≤₺5.000)");
  eq(ev("M9", { ...cat(1500000, 3000000), months_with_data: 1 }).length, 0, "M9 az geçmiş");
  eq(ev("M9", cat(1500000, 3000000))[0].metrics.find((x) => x.key === "avg3").value, 1000000, "M9 3 ay ortalaması kuruş");
  const t = (top, total, payments = 5) => ({ total, payments, customers: 4, top: { key: "k", name: "Mega Ltd", kurus: top }, window_days: 90 });
  eq(ev("M10", t(5100000, 10000000))[0].severity, "warn", "M10 %51 uyarı");
  eq(ev("M10", t(5000000, 10000000)).length, 0, "M10 tam %50 yok");
  eq(ev("M10", t(7100000, 10000000))[0].severity, "critical", "M10 %71 kritik");
  eq(ev("M10", t(900000, 900000, 5)).length, 0, "M10 toplam tabanı");
  eq(ev("M10", t(5100000, 10000000, 2)).length, 0, "M10 az ödeme");
  const p = (pipeline, rate) => ({ pipeline, open_count: 3, rate_bp: rate, resolved: 8, fixed_month: 3000000 });
  // ihtiyaç = 3.000.000*60/30 = 6.000.000
  eq(ev("M12", p(10000000, 5000))[0].severity, "critical", "M12 beklenen 5.000.000 < 6.000.000 kritik");
  eq(ev("M12", p(14000000, 5000))[0].severity, "warn", "M12 beklenen 7.000.000 (1,17×) uyarı");
  eq(ev("M12", p(15000000, 5000)).length, 0, "M12 beklenen 7.500.000 (1,25×) yok");
  eq(ev("M12", { ...p(1, 5000), resolved: 2 }).length, 0, "M12 az örnek");
  eq(ev("M12", { ...p(1, 5000), fixed_month: 0 }).length, 0, "M12 gider yok");
  const s = (cur, ly, o = {}) => ({ month: "2026-11", day: 20, current: cur, last_year: ly, history_days: 400, ...o });
  eq(ev("M13", s(7000000, 10000000))[0].severity, "warn", "M13 %30 düşüş uyarı");
  eq(ev("M13", s(5000000, 10000000))[0].severity, "critical", "M13 %50 kritik");
  eq(ev("M13", s(8000000, 10000000)).length, 0, "M13 %20 yok");
  eq(ev("M13", s(1, 10000000, { history_days: 300 })).length, 0, "M13 <12 ay veri yok");
  eq(ev("M13", s(1, 10000000, { day: 9 })).length, 0, "M13 ayın 10'undan önce yok");
}
// ---- şablon: tüm kurallar için render çökmez, sektör sözlüğü kullanılır ----
{
  const Tp = makeTerms({ job: "Proje", offer: "Teklif", appointment: "Randevu", customer: "Müşteri" });
  const sample = ev("M2", { avg_job_kurus: 1000000, items: [{ delivered: true, project_id: "p1", customer_name: "Ahmet Kaya", code: "PRJ-1", stage: "Teslim", stage_age_days: 10, balance_kurus: 123456, contract_kurus: 200000, extras_kurus: 0, paid_kurus: 76544, service: "Mutfak", phone: "05321234567" }] })[0];
  const out = templates.render(sample, Tp, env);
  ok(out.body.includes("₺1.234,56"), "kuruş 123456 → ₺1.234,56", out.body);
  ok(!/undefined|NaN|\[object/.test(out.title + out.body), "metinde undefined/NaN yok");
  const wa = out.actions.find((a) => a.type === "whatsapp.template");
  ok(wa && wa.text.includes("proje") && wa.text.includes("Ahmet"), "WhatsApp metni sektör sözlüğünü kullanır", wa && wa.text);
  eq(templates.renderMetrics([{ key: "x", label: "x", value: 1450, unit: "bp" }])[0].display, "%14,5", "renderMetrics bp");
}
// ---- hatırlatma hesapları ----
{
  const d = (s) => new Date(s);
  eq(rem.nextOccurrence(d("2026-11-20T06:00:00Z"), "daily").toISOString(), "2026-11-21T06:00:00.000Z", "tekrar: günlük");
  eq(rem.nextOccurrence(d("2026-11-20T06:00:00Z"), "weekly").toISOString(), "2026-11-27T06:00:00.000Z", "tekrar: haftalık");
  eq(rem.nextOccurrence(d("2026-11-20T06:00:00Z"), "weekdays").toISOString(), "2026-11-23T06:00:00.000Z", "tekrar: iş günleri Cuma→Pazartesi");
  eq(rem.nextOccurrence(d("2026-01-31T06:00:00Z"), "monthly").toISOString(), "2026-02-28T06:00:00.000Z", "tekrar: aylık ay sonu kırpma");
  eq(rem.nextOccurrence(d("2026-12-31T06:00:00Z"), "monthly").toISOString(), "2027-01-31T06:00:00.000Z", "tekrar: aylık yıl devri");
  eq(rem.nextOccurrence(d("2026-03-28T20:30:00Z"), "daily").toISOString(), "2026-03-29T20:30:00.000Z", "tekrar: İstanbul saati korunur (UTC+3 sabit)");
  eq(rem.nextOccurrence(d("2026-11-20T06:00:00Z"), "yok"), null, "tekrar: geçersiz");
  const now = d("2026-11-20T10:00:00Z");
  eq(rem.snoozeTarget("15m", now).toISOString(), "2026-11-20T10:15:00.000Z", "erteleme 15 dk");
  eq(rem.snoozeTarget("1h", now).toISOString(), "2026-11-20T11:00:00.000Z", "erteleme 1 saat");
  eq(rem.snoozeTarget("tomorrow", now).toISOString(), "2026-11-21T06:00:00.000Z", "erteleme yarın 09:00 İstanbul");
  eq(rem.snoozeTarget(30, now).toISOString(), "2026-11-20T10:30:00.000Z", "erteleme 30 dk");
  eq(rem.snoozeTarget(4, now), null, "erteleme <5 dk geçersiz");
  eq(rem.snoozeTarget("yarin", now), null, "erteleme geçersiz ön ayar");
  ok(rem.validRecurrence(null) && rem.validRecurrence("daily") && !rem.validRecurrence("hourly"), "validRecurrence");
}
console.log(`\nunit_v20: ${pass} geçti, ${fail} başarısız`);
process.exit(fail ? 1 : 0);
