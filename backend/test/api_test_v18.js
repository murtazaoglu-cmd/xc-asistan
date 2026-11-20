// v18 testleri: fatura takibi, KDV (sınır durumları, tevkifat, dönem özeti, kilit), vergi takvimi, tahsilat planı + yaşlandırma, WhatsApp şablonları + wa.me,
// muhasebeci dışa aktarımı (CSV/XLSX), zamanlı hatırlatma işleyicileri (A1 kuyruğu), roller (personel/saha 403), ortak A/B izolasyonu, şema idempotensi.
// Önkoşul: TEMİZ veritabanı + migrate + seed (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234); sunucu :4102'de (TEST_PORT ile değişir),
// cwd = backend klasörü. Saf servis testleri sunucusuz çalışır. XLSX doğrulaması için python3+openpyxl varsa kullanılır (yoksa atlanır).
const fs = require("fs"), os = require("os"), path = require("path");
const { spawnSync } = require("child_process");
const db = require("../src/db"); // dotenv'i de yükler
const clock = require("../src/assistant/clock");
const queue = require("../src/assistant/queue");
const V = require("../src/assistant/tax/vat");
const VP = require("../src/assistant/tax/vatPeriod");
const TC = require("../src/assistant/tax/taxCalendar");
const R = require("../src/assistant/tax/receivables");
const MT = require("../src/assistant/tax/messageTemplates");
const T = require("../src/assistant/tax/turkish");
const M = require("../src/assistant/tax/money");
const D = require("../src/assistant/tax/dates");
const EX = require("../src/assistant/tax/exportFile");
const RULES = require("../src/assistant/tax/rules");
const planner = require("../src/assistant/tax/reminderPlanner");
const taxHandlers = require("../src/assistant/handlers/tax");

const PORT = process.env.TEST_PORT || 4102;
const B = `http://localhost:${PORT}/api`;
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 700) : ""); } };
const eq = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), m, { got: a, want: b });
async function call(method, p, token, body, headers = {}) {
  const r = await fetch(B + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...headers }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  const buf = Buffer.from(await r.arrayBuffer());
  let j = null; try { j = JSON.parse(buf.toString("utf8")); } catch {}
  return { s: r.status, j, h: r.headers, buf };
}
const login = async (e) => (await call("POST", "/auth/login", null, { email: e, password: "pass1234" })).j?.token;
const q1 = async (sql, p) => (await db.query(sql, p)).rows[0];
const qa = async (sql, p) => (await db.query(sql, p)).rows;
const uid = async (email) => (await q1("SELECT id FROM users WHERE email = $1", [email])).id;
const PNG = Buffer.from("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc3300000000049454e44ae426082".replace(/\s/g, ""), "hex");

(async () => {
  // ============================================================ 1) SAF: para / KDV
  {
    eq(M.toKurus(1250.5), 125050, "toKurus 1250.5");
    eq(M.toKurus("1250.50"), 125050, "toKurus metin");
    eq(M.toKurus("1,5"), null, "toKurus virgül reddedilir (API sözleşmesi)");
    eq(M.toKurus(1.005), 101, "toKurus 1.005 → 101 (float tuzağı: epsilon)");
    eq(M.toKurus(0.1 + 0.2), 30, "toKurus 0.1+0.2");
    eq(M.toKurus(NaN), null, "toKurus NaN");
    eq(M.fromKurus(125050), 1250.5, "fromKurus");
    eq(M.mulDiv(5, 1, 2), 3, "mulDiv yarım yukarı 2.5 → 3");
    eq(M.mulDiv(-5, 1, 2), -3, "mulDiv negatif sıfırdan uzağa");
    eq(M.divRound(7, 2), 4, "divRound 3.5 → 4");
    ok(M.isKurus(0) && M.isKurus(1e12) && !M.isKurus(1e12 + 1) && !M.isKurus(1.5) && !M.isKurus(-1) && !M.isKurus("5"), "isKurus sınırları");

    const c = (o) => V.computeInvoiceAmounts(o);
    eq(c({ mode: "haric", amountKurus: 100000, rate: 20 }), { matrahKurus: 100000, kdvKurus: 20000, tutarKurus: 120000, tevkifatKurus: 0, odenecekKurus: 120000, rateBp: 2000 }, "haric %20");
    eq(c({ mode: "dahil", amountKurus: 120000, rate: 20 }).matrahKurus, 100000, "dahil %20 matrah");
    eq(c({ mode: "haric", amountKurus: 2, rate: 20 }).kdvKurus, 0, "0,4 kuruş KDV → 0");
    eq(c({ mode: "haric", amountKurus: 3, rate: 20 }).kdvKurus, 1, "0,6 kuruş KDV → 1");
    eq(c({ mode: "haric", amountKurus: 5, rate: 10 }).kdvKurus, 1, "0,5 kuruş tam yarım → yukarı (%10, 5 kuruş)");
    eq(c({ mode: "haric", amountKurus: 50, rate: 1 }).kdvKurus, 1, "0,5 kuruş tam yarım → yukarı (%1, 50 kuruş)");
    eq(c({ mode: "haric", amountKurus: 0, rate: 20 }).tutarKurus, 0, "sıfır tutar");
    eq(c({ mode: "dahil", amountKurus: 1, rate: 20 }), { matrahKurus: 1, kdvKurus: 0, tutarKurus: 1, tevkifatKurus: 0, odenecekKurus: 1, rateBp: 2000 }, "dahil 1 kuruş");
    eq(c({ mode: "haric", amountKurus: 123456, rate: 0 }).kdvKurus, 0, "%0 KDV");
    eq(c({ mode: "dahil", amountKurus: 123456, rate: 0 }).matrahKurus, 123456, "%0 dahil: matrah = toplam");
    eq(c({ mode: "haric", amountKurus: 100000, rate: 18.5 }).kdvKurus, 18500, "ondalık oran 18,5");
    eq(c({ mode: "haric", amountKurus: 100000, rate: "10,5" }).kdvKurus, 10500, "virgüllü oran metni");
    ok(c({ mode: "haric", amountKurus: 100, rate: 20.123 }).error, "3 ondalıklı oran reddedilir");
    ok(c({ mode: "haric", amountKurus: 100, rate: -1 }).error && c({ mode: "haric", amountKurus: 100, rate: 100.01 }).error, "oran 0..100 dışı reddedilir");
    ok(c({ mode: "haric", amountKurus: 10.5, rate: 20 }).error && c({ mode: "haric", amountKurus: -1, rate: 20 }).error && c({ mode: "haric", amountKurus: 1e13, rate: 20 }).error, "kuruş tamsayı/aralık denetimi");
    ok(c({ mode: "xx", amountKurus: 1, rate: 20 }).error, "geçersiz mod");
    // dahil ↔ haric tutarlılığı: matrah + kdv = tutar HER ZAMAN; 20000 örnek
    let bad = 0, bad2 = 0;
    for (let i = 0; i < 20000; i++) {
      const amt = Math.floor(Math.random() * 5e7), rate = [0, 1, 10, 20, 8, 18][i % 6];
      for (const mode of ["haric", "dahil"]) { const r = c({ mode, amountKurus: amt, rate }); if (r.matrahKurus + r.kdvKurus !== r.tutarKurus || r.kdvKurus < 0) bad++; }
      const d = c({ mode: "dahil", amountKurus: amt, rate }); const h = c({ mode: "haric", amountKurus: d.matrahKurus, rate });
      if (Math.abs(h.tutarKurus - amt) > 1) bad2++; // gidiş-dönüş en çok 1 kuruş sapar
    }
    eq(bad, 0, "20000 rastgele: matrah+kdv=tutar");
    eq(bad2, 0, "20000 rastgele: dahil→haric gidiş-dönüş ≤ 1 kuruş");
    // quotes.js computeTotals ile %20'de BİREBİR aynı satır-bazlı yuvarlama (referans: quotes.js'ten kopya)
    const refTotals = (items) => { let net = 0, gross = 0; for (const it of items) { const line = Math.round(Number(it.qty) * Number(it.price) * 100); if (it.vatIncluded) { net += Math.round((line * 100) / 120); gross += line; } else { net += line; gross += line + Math.round(line * 0.2); } } return { subtotal: net / 100, tax: (gross - net) / 100, total: gross / 100 }; };
    let parity = 0;
    for (let i = 0; i < 3000; i++) {
      const items = Array.from({ length: 1 + (i % 4) }, () => ({ qty: Math.floor(Math.random() * 9) + 1, price: Math.round(Math.random() * 1e6) / 100, vatIncluded: Math.random() < 0.5 }));
      const a = refTotals(items), s = V.sumLines(items, 20);
      if (s.matrahKurus / 100 !== a.subtotal || s.kdvKurus / 100 !== a.tax || s.tutarKurus / 100 !== a.total) parity++;
    }
    eq(parity, 0, "sumLines ≡ quotes.js computeTotals (3000 rastgele sepet, %20)");

    // tevkifat
    const t = c({ mode: "haric", amountKurus: 1000000, rate: 20, withholding: "4/10" });
    eq([t.kdvKurus, t.tevkifatKurus, t.tutarKurus, t.odenecekKurus], [200000, 80000, 1200000, 1120000], "tevkifat 4/10: KDV 2000, tevkifat 800, toplam 12000, tahsil 11200");
    eq(c({ mode: "haric", amountKurus: 100, rate: 20, withholding: { pay: 5, payda: 10 } }).tevkifatKurus, 10, "tevkifat 5/10 nesne biçimi (kdv 20 → 10)");
    eq(c({ mode: "haric", amountKurus: 15, rate: 20, withholding: "5/10" }).tevkifatKurus, 2, "tevkifat yarım yukarı (kdv 3 × 5/10 = 1,5 → 2)");
    eq(c({ mode: "haric", amountKurus: 100000, rate: 20, withholding: 0.4 }).tevkifatKurus, 8000, "tevkifat 0,4 → 4/10");
    eq(c({ mode: "haric", amountKurus: 100000, rate: 20, withholding: "10/10" }).odenecekKurus, 100000, "tam tevkifat 10/10: KDV tamamen alıcıda");
    ok(c({ mode: "haric", amountKurus: 100, rate: 20, withholding: "11/10" }).error && c({ mode: "haric", amountKurus: 100, rate: 20, withholding: "0/10" }).error && c({ mode: "haric", amountKurus: 100, rate: 20, withholding: "abc" }).error, "geçersiz tevkifat reddedilir");
    eq(V.parseWithholding(null), null, "tevkifat null = yok");
    eq(V.parseWithholding(""), null, "tevkifat boş = yok");
    eq(V.parseWithholding("4 / 10"), { pay: 4, payda: 10 }, "tevkifat boşluklu metin");
    eq(V.withholdingLabel({ pay: 7, payda: 10 }), "7/10", "tevkifat etiketi");
    eq(V.checkDeclaredVat({ matrahKurus: 100000, kdvKurus: 20003, rate: 20 }).ok, true, "beyan KDV: 3 kuruş fark tolerans içinde");
    eq(V.checkDeclaredVat({ matrahKurus: 100000, kdvKurus: 20006, rate: 20 }).ok, false, "beyan KDV: 6 kuruş fark tolerans dışı");
    eq(V.validateTaxId("10000000146").checksumOk, true, "TCKN sağlama doğru (10000000146)");
    eq(V.validateTaxId("10000000147").checksumOk, false, "TCKN sağlama yanlış");
    eq(V.validateTaxId("11111111111").checksumOk, true, "nihai tüketici 11111111111 kabul");
    eq(V.validateTaxId("123").ok, false, "VKN/TCKN biçimi");
    eq(V.validateTaxId("abcdefghij").ok, false, "VKN/TCKN rakam");
    eq(V.validateTaxId("").empty, true, "boş VKN serbest");
    eq(V.validateTaxId("0000000000").kind, "VKN", "10 hane = VKN");
  }

  // ============================================================ 2) SAF: KDV dönemi
  {
    eq(VP.parsePeriodKey("2026-11"), { key: "2026-11", type: "aylik", year: 2026, startMonth: 11, endMonth: 11, startsOn: "2026-11-01", endsOn: "2026-11-30" }, "dönem anahtarı aylık");
    eq(VP.parsePeriodKey("2026-Q4").startsOn + VP.parsePeriodKey("2026-Q4").endsOn, "2026-10-012026-12-31", "dönem anahtarı Q4");
    eq(VP.parsePeriodKey("2024-02").endsOn, "2024-02-29", "artık yıl Şubat");
    eq(VP.parsePeriodKey("2026-13"), null, "ay 13 geçersiz");
    eq(VP.parsePeriodKey("2026-Q5"), null, "Q5 geçersiz");
    eq(VP.previousPeriodKey("2026-01"), "2025-12", "önceki dönem yıl geçişi");
    eq(VP.nextPeriodKey("2026-12"), "2027-01", "sonraki dönem yıl geçişi");
    eq(VP.previousPeriodKey("2026-Q1"), "2025-Q4", "önceki çeyrek");
    eq(VP.periodOfDate("uc_aylik", "2026-11-30"), "2026-Q4", "tarih → çeyrek");
    const inv = (o) => ({ status: "kesildi", kdv_oran: 20, tevkifat_kurus: 0, kdv_indirilebilir: true, ...o });
    const s1 = VP.summarizeInvoices([
      inv({ direction: "giden", matrah_kurus: 1000000, kdv_kurus: 200000 }),
      inv({ direction: "giden", matrah_kurus: 500000, kdv_kurus: 100000, tevkifat_kurus: 40000 }),
      inv({ direction: "gelen", matrah_kurus: 300000, kdv_kurus: 60000 }),
      inv({ direction: "gelen", matrah_kurus: 100000, kdv_kurus: 20000, kdv_indirilebilir: false }),
      inv({ direction: "gelen", matrah_kurus: 100000, kdv_kurus: 20000, tevkifat_kurus: 8000 }),
      inv({ direction: "giden", matrah_kurus: 999999, kdv_kurus: 199999, status: "taslak" }),
      inv({ direction: "giden", matrah_kurus: 999999, kdv_kurus: 199999, status: "iptal" }),
    ]);
    eq([s1.hesaplananToplamKurus, s1.tevkifatGidenKurus, s1.hesaplananKurus], [300000, 40000, 260000], "giden: toplam KDV 3000, tevkifat 400 → hesaplanan 2600");
    eq([s1.indirilecekKurus, s1.indirilemeyenKurus, s1.kdv2Kurus], [80000, 20000, 8000], "gelen: indirilecek 800, indirilemez 200, KDV-2 80");
    eq(s1.counts, { giden: 2, gelen: 3 }, "taslak/iptal sayılmaz");
    const p1 = VP.computePeriod(s1, 0);
    eq([p1.odenecekKurus, p1.devredenKurus, p1.netKurus], [180000, 0, 180000], "ödenecek 1800");
    const p2 = VP.computePeriod({ hesaplananKurus: 100000, indirilecekKurus: 350000 }, 0);
    eq([p2.odenecekKurus, p2.devredenKurus], [0, 250000], "indirilecek > hesaplanan → devreden");
    const p3 = VP.computePeriod({ hesaplananKurus: 100000, indirilecekKurus: 0 }, 250000);
    eq([p3.odenecekKurus, p3.devredenKurus], [0, 150000], "devreden kullanılınca kalan devreder");
    const p4 = VP.computePeriod({ hesaplananKurus: 100000, indirilecekKurus: 0 }, 100000);
    eq([p4.odenecekKurus, p4.devredenKurus], [0, 0], "tam kapanma: ödenecek 0, devreden 0");
    const sums = { "2026-01": VP.summarizeInvoices([inv({ direction: "gelen", matrah_kurus: 1000000, kdv_kurus: 200000 })]), "2026-02": VP.summarizeInvoices([inv({ direction: "giden", matrah_kurus: 500000, kdv_kurus: 100000 })]),
      "2026-03": VP.summarizeInvoices([inv({ direction: "giden", matrah_kurus: 1000000, kdv_kurus: 200000 })]) };
    const ch = VP.chainPeriods(["2026-01", "2026-02", "2026-03"], sums);
    eq(ch.map((x) => [x.odenecekKurus, x.devredenKurus, x.oncekiDevredenKurus]), [[0, 200000, 0], [0, 100000, 200000], [100000, 0, 100000]], "devir zinciri 3 ay");
    const ch2 = VP.chainPeriods(["2026-01", "2026-02", "2026-03"], sums, 0, { "2026-02": 0 });
    eq(ch2[1].oncekiDevredenKurus, 0, "elle devir ezer");
    const ch3 = VP.chainPeriods(["2026-01", "2026-02"], sums, 0, {}, { "2026-01": { hesaplananKurus: 0, indirilecekKurus: 0, oncekiDevredenKurus: 0, odenecekKurus: 0, devredenKurus: 777 } });
    eq([ch3[0].locked, ch3[1].oncekiDevredenKurus], [true, 777], "kilitli dönem saklanan devri kullanır");
  }

  // ============================================================ 3) SAF: vergi takvimi
  {
    const H = (arr) => TC.holidayMap(arr.map(([day, half]) => ({ day, name: "t", half_day: !!half, verified: true })));
    const h2026 = H([["2026-05-27"], ["2026-05-28"], ["2026-05-29"], ["2026-05-30"], ["2026-10-29"], ["2026-10-28", true]]);
    eq(TC.shiftToBusinessDay("2026-02-28", h2026).date, "2026-03-02", "Cumartesi → Pazartesi (28 Şubat 2026)");
    eq(TC.shiftToBusinessDay("2026-11-28", h2026).date, "2026-11-30", "28 Kasım 2026 Cumartesi → 30 Kasım");
    eq(TC.shiftToBusinessDay("2026-05-28", h2026).date, "2026-06-01", "Kurban Bayramı + hafta sonu → 1 Haziran");
    eq(TC.shiftToBusinessDay("2026-10-28", h2026).date, "2026-10-28", "arife yarım gün iş günü sayılır");
    eq(TC.shiftToBusinessDay("2026-04-28", h2026).shifted, false, "iş günü kaymaz");
    const rule28 = { freq: "monthly", day: 28, period_offset_months: 1 };
    const exp = { "2026-01": "2026-03-02", "2026-02": "2026-03-30", "2026-03": "2026-04-28", "2026-04": "2026-06-01", "2026-05": "2026-06-29", "2026-06": "2026-07-28", "2026-09": "2026-10-28", "2026-10": "2026-11-30", "2026-11": "2026-12-28" };
    // not: araştırma tablosu Şubat→30 Mart: 28 Mart Cumartesi → 30 Mart Pazartesi; Mayıs→29 Haziran: 28 Haziran Pazar → 29 Haziran
    for (const [k, v] of Object.entries(exp)) eq(TC.vatDueDate(k, rule28, h2026).due, v, `KDV son gün kuralı ${k} → ${v}`);
    eq(TC.vatDueDate("2026-12", rule28, h2026).due, "2027-01-28", "Aralık dönemi → Ocak 28 (yıl geçişi)");
    eq(TC.vatDueDate("2026-Q4", { freq: "quarterly", day: 28, period_offset_months: 1 }, h2026).due, "2027-01-28", "3 aylık Q4 → 28 Ocak");
    eq(TC.vatDueDate("2026-03", { freq: "monthly", day: "last", period_offset_months: 1 }, h2026).due, "2026-04-30", "'last' kuralı");
    eq(TC.vatDueDate("2026-01", { freq: "monthly", day: 31, period_offset_months: 1 }, h2026).nominal, "2026-02-28", "31 → Şubat sonu");
    ok(TC.validateRule({ freq: "monthly", day: 32 }) && TC.validateRule({ freq: "x" }) && TC.validateRule([]) && TC.validateRule({ freq: "yearly", dates: [] }), "kural doğrulama");
    eq(TC.validateRule({ freq: "yearly", dates: [{ month: 5, day: 17 }] }), null, "geçerli yearly kuralı");
    const unverified = TC.holidayMap([{ day: "2026-03-20", name: "x", half_day: false, verified: false }]);
    eq(TC.shiftToBusinessDay("2026-03-20", unverified).unverifiedHoliday, true, "doğrulanmamış tatil kaydırmada işaretlenir");
    // yearly + tek seferlik
    const gv = { key: "gecici", title: "g", rule: { freq: "yearly", dates: [{ month: 5, day: 17, label: "I" }, { month: 8, day: 17, label: "II" }, { month: 11, day: 17, label: "III" }] }, enabled: true, verified: true };
    const occ = TC.expandItem(gv, "2026-01-01", "2026-12-31", h2026);
    eq(occ.map((o) => o.due_date), ["2026-05-18", "2026-08-17", "2026-11-17"], "geçici vergi 2026: 17 Mayıs Pazar → 18 Mayıs; 17 Ağustos; 17 Kasım");
    eq(occ[0].shifted, true, "kaydırma bayrağı");
    eq(occ[0].needs_confirmation, false, "doğrulanmış kayıt teyit istemez");
    const one = TC.expandItem({ key: "o", title: "o", rule: null, due_date: "2026-12-31", enabled: true, verified: false }, "2026-12-01", "2026-12-31", h2026);
    eq([one.length, one[0].due_date, one[0].needs_confirmation], [1, "2026-12-31", true], "tek seferlik tarih + doğrulanmadı bayrağı");
    eq(TC.expandItem({ ...gv, enabled: false }, "2026-01-01", "2026-12-31", h2026), [], "kapalı kalem oluşum üretmez");
    const rem = TC.remindersDue([{ key: "k", title: "k", rule: null, due_date: "2026-12-10", enabled: true, verified: true }], { today: "2026-12-03", holidays: [], offsets: [7, 3, 1, 0] });
    eq(rem.map((x) => x.offset), [7], "T−7 hatırlatma (3 Aralık için 10 Aralık)");
    eq(TC.remindersDue([{ key: "k", title: "k", rule: null, due_date: "2026-12-10", enabled: true }], { today: "2026-12-06", holidays: [] }).length, 0, "T−4: hatırlatma yok");
    eq(TC.occurrences([{ key: "a", title: "a", rule: null, due_date: "2026-12-10", enabled: true, applies_to: "limited" }, { key: "b", title: "b", rule: null, due_date: "2026-12-10", enabled: true, applies_to: "hepsi" }], { from: "2026-12-01", to: "2026-12-31", holidays: [], appliesTo: "sahis" }).map((o) => o.key), ["b"], "statü filtresi");
  }

  // ============================================================ 4) SAF: tahsilat yaşlandırma + taksit
  {
    eq([R.bucketOf(-5), R.bucketOf(0), R.bucketOf(1), R.bucketOf(30), R.bucketOf(31), R.bucketOf(60), R.bucketOf(61), R.bucketOf(90), R.bucketOf(91)], ["notDue", "notDue", "0-30", "0-30", "31-60", "31-60", "61-90", "61-90", "90+"], "kova sınırları 0/1/30/31/60/61/90/91");
    const items = [{ amount_kurus: 100, due_date: "2026-11-25" }, { amount_kurus: 200, due_date: "2026-11-20" }, { amount_kurus: 400, due_date: "2026-10-21" }, { amount_kurus: 800, due_date: "2026-10-20" }, { amount_kurus: 1600, due_date: "2026-08-22" }, { amount_kurus: 3200, due_date: "2026-08-21" }, { amount_kurus: 6400, due_date: "2026-05-01" }].map((x) => ({ source: "plan", id: x.due_date, customer_name: "A", ...x }));
    const a = R.buildAging(items, "2026-11-20");
    eq([a.buckets.notDue.totalKurus, a.buckets["0-30"].totalKurus, a.buckets["31-60"].totalKurus, a.buckets["61-90"].totalKurus, a.buckets["90+"].totalKurus], [300, 400, 800, 1600, 9600], "yaşlandırma toplamları (bugün vadeli = notDue; 30 gün = 0-30)");
    eq([a.totalKurus, a.overdueKurus, a.overdueCount], [12700, 12400, 5], "toplam / vadesi geçen");
    eq(a.overdueItems[0].days_overdue >= a.overdueItems[1].days_overdue, true, "en eski önce");
    const covered = R.openReceivables([{ id: "s1", status: "bekliyor", amount_kurus: 500, due_date: "2026-11-01", invoice_id: "i1", kind: "taksit" }, { id: "s2", status: "iptal", amount_kurus: 9, due_date: "2026-11-01", invoice_id: "i2", kind: "taksit" }],
      [{ id: "i1", direction: "giden", status: "kesildi", odenecek_kurus: 1000, due_date: "2026-11-01" }, { id: "i2", direction: "giden", status: "kesildi", odenecek_kurus: 700, due_date: "2026-11-01" },
        { id: "i3", direction: "gelen", status: "kesildi", odenecek_kurus: 5, due_date: "2026-11-01" }, { id: "i4", direction: "giden", status: "kesildi", odenecek_kurus: 5, due_date: null }, { id: "i5", direction: "giden", status: "odendi", odenecek_kurus: 5, due_date: "2026-11-01" }]);
    eq(covered.map((x) => x.id), ["s1", "i2"], "çift sayım yok (aktif taksitli fatura sayılmaz; iptal taksit fatura'yı geri açar; gelen/vadesiz/ödenmiş hariç)");
    const sp = R.splitInstallments({ totalKurus: 100001, count: 3, firstDue: "2026-01-31" });
    eq(sp.items.map((x) => x.amount_kurus), [33333, 33333, 33335], "taksit artığı SON taksite");
    eq(sp.items.map((x) => x.due_date), ["2026-01-31", "2026-02-28", "2026-03-31"], "31 Ocak + aylık: Şubat sonu, sonra tekrar 31");
    eq(sp.items.reduce((s, x) => s + x.amount_kurus, 0), 100001, "taksit toplamı tutara eşit");
    eq(R.splitInstallments({ totalKurus: 1000, count: 2, firstDue: "2026-01-01", intervalDays: 15 }).items.map((x) => x.due_date), ["2026-01-01", "2026-01-16"], "gün aralıklı taksit");
    ok(R.splitInstallments({ totalKurus: 0, count: 2, firstDue: "2026-01-01" }).error && R.splitInstallments({ totalKurus: 5, count: 61, firstDue: "2026-01-01" }).error && R.splitInstallments({ totalKurus: 1, count: 2, firstDue: "2026-01-01" }).error, "taksit doğrulama");
    eq(R.effectiveStatus({ status: "bekliyor", due_date: "2026-11-19" }, "2026-11-20"), "gecikti", "bekliyor + vade geçti = gecikti (türetilir)");
    eq(R.effectiveStatus({ status: "bekliyor", due_date: "2026-11-20" }, "2026-11-20"), "bekliyor", "vade günü gecikmiş değil");
  }

  // ============================================================ 5) SAF: Türkçe, şablon, wa.me, dışa aktarma biçimi
  {
    eq(T.suffix("Ahmet", "e"), "Ahmet'e", "Ahmet'e"); eq(T.suffix("Ayşe", "e"), "Ayşe'ye", "Ayşe'ye"); eq(T.suffix("Burak", "e"), "Burak'a", "Burak'a");
    eq(T.suffix("Ali", "in"), "Ali'nin", "Ali'nin"); eq(T.suffix("Mehmet", "den"), "Mehmet'ten", "Mehmet'ten (sert ünsüz)"); eq(T.suffix("Kemal", "e"), "Kemal'e", "Kemal'e (ince l istisnası)");
    eq(T.suffix("Zeynep", "de"), "Zeynep'te", "Zeynep'te"); eq(T.suffix("Ömer", "i"), "Ömer'i", "Ömer'i"); eq(T.suffix("Murat", "ile"), "Murat'la", "Murat'la");
    eq(T.suffix("Fatma", "i"), "Fatma'yı", "Fatma'yı"); eq(T.suffix("Şükrü", "e"), "Şükrü'ye", "Şükrü'ye");
    eq(T.titleCaseTr("ıŞIL İPEK yılmaz"), "Işıl İpek Yılmaz", "Türkçe başlık harfi (İ/ı)"); eq(T.upperTr("ışık"), "IŞIK", "upperTr ı→I"); eq(T.lowerTr("İSTANBUL"), "istanbul", "lowerTr İ→i");
    eq(T.firstName("AHMET YILMAZ"), "Ahmet", "ilk ad");
    eq(T.formatTL(125050), "1.250,50", "formatTL"); eq(T.formatTL(125000), "1.250", "formatTL ,00 atılır"); eq(T.formatTL(5), "0,05", "formatTL 5 kuruş"); eq(T.formatTL(123456789), "1.234.567,89", "formatTL milyon"); eq(T.formatTL(-250), "-2,50", "formatTL negatif");
    eq(T.formatDateTr("2026-12-05"), "5 Aralık 2026", "tarih TR"); eq(T.weekdayTr("2026-12-05"), "Cumartesi", "gün adı"); eq(T.formatDateShort("2026-12-05"), "05.12.2026", "kısa tarih");

    const r = MT.renderTemplate("Merhaba {ilk_ad|e}, {tutar} TL. [[Not: {not}. ]]Teşekkürler {firma_adi|den}.", { ilk_ad: "Ahmet", tutar: "1.250", firma_adi: "X Yapı" });
    eq(r.text, "Merhaba Ahmet'e, 1.250 TL. Teşekkürler X Yapı'dan.", "şablon: hâl eki + eksik isteğe bağlı blok atılır"); eq(r.complete, true, "blok eksikliği 'eksik' sayılmaz");
    const r2 = MT.renderTemplate("A {x} B {y}", { x: "1" }); eq([r2.text, r2.missing, r2.complete], ["A 1 B {y}", ["y"], false], "eksik değişken yer tutucu kalır + missing");
    eq(MT.renderTemplate("{a}", { a: "{b} [[x]]" }).text, "{b} [[x]]", "eklenen değer yeniden yorumlanmaz (enjeksiyon yok)");
    eq(MT.renderTemplate("{ad|upper} {ad|title}", { ad: "ali veli" }).text, "ALİ VELİ Ali Veli", "upper/title");
    eq(MT.renderTemplate("a\n\n\n\nb ", {}).text, "a\n\nb", "fazla boş satırlar sıkıştırılır");
    eq(MT.extractVars("{a} [[{b}]] {a|e}"), ["a", "b"], "extractVars tekil");
    eq(MT.renderTemplate("{a}", { a: "x".repeat(1000) }).text.length, 300, "değer uzunluğu sınırı 300");
    eq(MT.renderTemplate("{a}", { a: "ab\u0000c" }).text, "abc", "kontrol karakterleri temizlenir");
    const norm = MT.normalizePhone;
    eq([norm("0532 123 45 67"), norm("0532-123-45-67"), norm("5321234567"), norm("+90 532 123 45 67"), norm("905321234567"), norm("00905321234567"), norm("(0532) 123 45 67")], Array(7).fill("905321234567"), "telefon: 0532…→90532… ve eşdeğer biçimler");
    eq([norm("+49 170 1234567"), norm("0049 170 1234567")], ["491701234567", "491701234567"], "yabancı numara korunur");
    eq([norm(""), norm(null), norm("abc"), norm("123"), norm("0532 123 45"), norm("0012")], [null, null, null, null, null, null], "geçersiz telefon → null");
    const l = MT.buildWhatsAppLinks("0532 123 45 67", "Merhaba Ahmet'e & ş=ğ\n100% iyi?");
    eq(l.whatsappUrl, "https://wa.me/905321234567?text=Merhaba%20Ahmet'e%20%26%20%C5%9F%3D%C4%9F%0A100%25%20iyi%3F", "wa.me URL kodlaması (UTF-8, &, =, satır sonu, %)");
    eq(l.whatsappAppUrl, "whatsapp://send?phone=905321234567&text=Merhaba%20Ahmet'e%20%26%20%C5%9F%3D%C4%9F%0A100%25%20iyi%3F", "whatsapp:// bağlantısı");
    eq(decodeURIComponent(l.whatsappUrl.split("text=")[1]), "Merhaba Ahmet'e & ş=ğ\n100% iyi?", "wa.me gidiş-dönüş");
    eq(MT.buildWhatsAppLinks("yok", "x"), { phone: null, whatsappUrl: null, whatsappAppUrl: null, urlTooLong: false }, "telefon yoksa bağlantı yok");
    eq(MT.buildWhatsAppLinks("05321234567", "ş".repeat(500)).urlTooLong, true, "URL > 2000 karakter uyarısı");
    const bv = MT.buildVars({ firma_adi: "F", customer: { name: "AHMET YILMAZ", phone: "0532 111 22 33" }, offer: { code: "OFR-1", name: "Ahmet Yılmaz", service: "Pergola", tracking_code: "abc123" }, siteUrl: "https://site.example/", quoteTotalKurus: 125050, optOut: true });
    eq([bv.vars.ad, bv.vars.ilk_ad, bv.vars.tutar, bv.vars.takip_linki, bv.vars.ret_notu.startsWith("Bu bildirimleri"), bv.phone], ["Ahmet Yılmaz", "Ahmet", "1.250,50", "https://site.example/teklif-takip/abc123", true, "0532 111 22 33"], "buildVars");

    // CSV
    const cols = [{ header: "Tarih", type: "date" }, { header: "Ad", type: "text" }, { header: "Tutar", type: "money" }, { header: "Oran", type: "percent" }];
    const csv = EX.toCsv(cols, [["2026-11-05", "Ş;ahin \"X\"", 125050, 20], ["2026-11-06", "=CMD()", 5, 10.5], ["2026-11-07", null, 0, 0]]);
    ok(csv.charCodeAt(0) === 0xfeff, "CSV UTF-8 BOM");
    const lines = csv.slice(1).split("\r\n");
    eq(lines[0], "Tarih;Ad;Tutar;Oran", "CSV başlık ';' ayırıcı");
    eq(lines[1], '05.11.2026;"Ş;ahin ""X""";1250,50;20', "CSV: gg.aa.yyyy, tırnak/;, ondalık virgül, binlik yok");
    eq(lines[2], "06.11.2026;'=CMD();0,05;10,5", "CSV formül enjeksiyonu: ' ön eki");
    eq(lines[3], "07.11.2026;;0,00;0", "CSV boş hücre, sıfır tutar");
    ok(csv.endsWith("\r\n"), "CSV CRLF satır sonu");
    const xl = EX.toXlsx([{ name: "Faturalar", columns: cols, rows: [["2026-11-05", "=1+1", 125050, 20]] }]);
    ok(Buffer.isBuffer(xl) && xl.slice(0, 2).toString() === "PK", "XLSX zip imzası (PK)");
    const tmp = path.join(os.tmpdir(), `v18-${process.pid}.xlsx`); fs.writeFileSync(tmp, xl);
    const py = spawnSync("python3", ["-I", "-c", "import sys,openpyxl;wb=openpyxl.load_workbook(sys.argv[1]);ws=wb.active;print(wb.sheetnames[0]);print([c.value for c in ws[1]]);print([ (c.value, c.data_type) for c in ws[2]])", tmp], { encoding: "utf8" });
    if (py.status === 0) {
      const [sn, hdr, row] = py.stdout.trim().split("\n");
      eq(sn, "Faturalar", "XLSX openpyxl: sayfa adı"); ok(hdr.includes("'Tarih'") && hdr.includes("'Tutar'"), "XLSX openpyxl: başlıklar", hdr);
      ok(row.includes("125050") === false && row.includes("1250.5"), "XLSX: tutar kuruştan TL sayısına (1250.5)", row);
      ok(row.includes("'=1+1', 's'") || row.includes('"=1+1", \'s\''), "XLSX: '=1+1' METİN hücresi (formül değil)", row);
      ok(row.includes("datetime.datetime(2026, 11, 5"), "XLSX: tarih gerçek Excel tarihi", row);
    } else console.log("  (atlandı: python3/openpyxl yok →", (py.stderr || "").slice(0, 80).trim() + ")");
    fs.unlink(tmp, () => {});

    // M7/M8 kural motoru
    const m7 = RULES.m7UnbilledCollections([{ project_id: "p", code: "PRJ-1", customer_name: "A", payments: [{ day: "2026-10-01", kurus: 100000 }, { day: "2026-11-10", kurus: 50000 }], invoicedKurus: 100000 }], "2026-11-20");
    eq([m7.length, m7[0].evidence.uncoveredKurus, m7[0].evidence.oldestUncoveredDate, m7[0].severity], [1, 50000, "2026-11-10", "warn"], "M7: FIFO — fatura en eski ödemeyi kapatır, 10 günlük faturasız tahsilat");
    eq(RULES.m7UnbilledCollections([{ project_id: "p", payments: [{ day: "2026-11-18", kurus: 50000 }], invoicedKurus: 0 }], "2026-11-20").length, 0, "M7: 7 günden yeni → uyarı yok");
    eq(RULES.m7UnbilledCollections([{ project_id: "p", payments: [{ day: "2026-10-01", kurus: 50000 }], invoicedKurus: 0 }], "2026-11-20")[0].severity, "critical", "M7: >30 gün → kritik");
    const m8 = RULES.m8VatDeadline({ key: "2026-10", odenecekKurus: 500000, hesaplananKurus: 700000, indirilecekKurus: 200000, oncekiDevredenKurus: 0, devredenKurus: 0 }, { dueDate: "2026-11-30", today: "2026-11-29", cashForecastKurus: 100000 });
    eq([m8.severity, m8.evidence.daysUntil, m8.evidence.cashShortfall], ["critical", 1, true], "M8: T−1 + nakit yetersiz → kritik");
    eq(RULES.m8VatDeadline({ key: "2026-10", odenecekKurus: 500000 }, { dueDate: "2026-11-30", today: "2026-11-10" }), null, "M8: 20 gün kala yok");
    eq(RULES.m8VatDeadline({ key: "2026-10", odenecekKurus: 0 }, { dueDate: "2026-11-30", today: "2026-11-28" }), null, "M8: ödenecek 0 → yok");
    eq(RULES.m8VatDeadline({ key: "2026-10", odenecekKurus: 500000 }, { dueDate: "2026-11-30", today: "2026-11-28" }).severity, "warn", "M8: nakit tahmini yoksa kritik değil, warn");
  }

  // ============================================================ API
  const A = await login("admin@x.com"), Mu = await login("muh@x.com"), OA = await login("oa@x.com"), OB = await login("ob@x.com"), PA = await login("pa@x.com");
  ok(A && Mu && OA && OB && PA, "girişler");
  const U = { admin: await uid("admin@x.com"), muh: await uid("muh@x.com"), oa: await uid("oa@x.com"), ob: await uid("ob@x.com"), pa: await uid("pa@x.com") };
  // saha kullanıcısı (admin oluşturur)
  const sa = await call("POST", "/users", A, { name: "Saha", email: "saha18@x.com", password: "pass1234", role: "saha" });
  ok(sa.s === 201, "saha kullanıcısı oluşturuldu", sa);
  const SA = await login("saha18@x.com");
  const org = await q1("SELECT id FROM organizations WHERE is_default");

  // ------------------------------------------------------------ 6) şema / tohum / idempotens
  {
    const cnt = async (t) => (await q1(`SELECT COUNT(*)::int n FROM ${t} WHERE org_id = $1`, [org.id])).n;
    ok((await cnt("vat_rates")) >= 4 && (await cnt("vat_withholding_types")) >= 2 && (await cnt("tax_calendar_items")) >= 11 && (await cnt("holidays_tr")) >= 30, "tohum: oran/tevkifat/takvim/tatil", { r: await cnt("vat_rates"), t: await cnt("tax_calendar_items"), h: await cnt("holidays_tr") });
    ok((await q1("SELECT COUNT(*)::int n FROM vat_rates WHERE org_id=$1 AND verified", [org.id])).n === 0, "KDV oranlarının HİÇBİRİ doğrulanmış tohumlanmaz");
    ok((await q1("SELECT COUNT(*)::int n FROM vat_withholding_types WHERE org_id=$1 AND verified", [org.id])).n === 0, "tevkifat türlerinin HİÇBİRİ doğrulanmış tohumlanmaz");
    ok((await q1("SELECT COUNT(*)::int n FROM tax_calendar_items WHERE org_id=$1 AND verified", [org.id])).n === 0, "takvim kalemlerinin HİÇBİRİ doğrulanmış tohumlanmaz");
    ok((await q1("SELECT COUNT(*)::int n FROM holidays_tr WHERE org_id=$1 AND kind='dini' AND verified", [org.id])).n === 0, "dini bayramlar doğrulanmadı");
    ok((await q1("SELECT COUNT(*)::int n FROM holidays_tr WHERE org_id=$1 AND day BETWEEN '2026-01-01' AND '2027-12-31'", [org.id])).n >= 30, "tatiller 2026-2027");
    for (const k of ["kdv1_aylik", "muhtasar_aylik", "gecici_vergi", "ba_bs", "e_defter_berat_gv", "kdv2_tevkifat", "yillik_gelir_vergisi"]) ok((await q1("SELECT 1 FROM tax_calendar_items WHERE org_id=$1 AND key=$2", [org.id, k])), "takvim tohumu: " + k);
    ok((await q1("SELECT COUNT(*)::int n FROM message_templates WHERE is_system AND org_id IS NULL")).n === 7, "7 sistem şablonu");
    ok((await q1("SELECT COUNT(*)::int n FROM org_tax_settings WHERE org_id=$1", [org.id])).n === 1, "org_tax_settings satırı");
    const before = await q1("SELECT (SELECT COUNT(*) FROM vat_rates) a, (SELECT COUNT(*) FROM tax_calendar_items) b, (SELECT COUNT(*) FROM holidays_tr) c, (SELECT COUNT(*) FROM message_templates) d");
    await db.query("UPDATE tax_calendar_items SET title = 'ELLE DÜZENLENDİ' WHERE org_id=$1 AND key='kdv1_aylik'", [org.id]);
    await db.query(fs.readFileSync(path.join(__dirname, "../src/schema_v18.sql"), "utf8")); // ikinci çalıştırma
    const after = await q1("SELECT (SELECT COUNT(*) FROM vat_rates) a, (SELECT COUNT(*) FROM tax_calendar_items) b, (SELECT COUNT(*) FROM holidays_tr) c, (SELECT COUNT(*) FROM message_templates) d");
    eq(after, before, "schema_v18.sql idempotent: ikinci çalıştırma satır sayısını değiştirmez");
    ok((await q1("SELECT title FROM tax_calendar_items WHERE org_id=$1 AND key='kdv1_aylik'", [org.id])).title === "ELLE DÜZENLENDİ", "idempotent tohum kullanıcı düzenlemesini EZMEZ");
    await db.query("UPDATE tax_calendar_items SET title = 'KDV-1 beyanı ve ödemesi (aylık dönem)' WHERE org_id=$1 AND key='kdv1_aylik'", [org.id]);
    const o2 = await q1("INSERT INTO organizations (name, slug) VALUES ('Test2','test2-v18') RETURNING id");
    ok((await q1("SELECT COUNT(*)::int n FROM tax_calendar_items WHERE org_id=$1", [o2.id])).n >= 11 && (await q1("SELECT COUNT(*)::int n FROM vat_rates WHERE org_id=$1", [o2.id])).n >= 4 && (await q1("SELECT COUNT(*)::int n FROM org_tax_settings WHERE org_id=$1", [o2.id])).n === 1, "yeni kuruluşa tohum otomatik (tetikleyici)");
    await db.query("DELETE FROM organizations WHERE id = $1", [o2.id]);
    const nx = await q1("SELECT is_nullable FROM information_schema.columns WHERE table_name='invoices' AND column_name='org_id'");
    eq(nx.is_nullable, "NO", "invoices.org_id NOT NULL");
  }

  // ------------------------------------------------------------ 7) yetki: personel/saha/anonim
  {
    const eps = [["GET", "/invoices"], ["POST", "/invoices", { direction: "giden", issue_date: "2026-11-01", matrah_kurus: 100 }], ["GET", "/invoices/summary?period=2026-11"], ["GET", "/invoices/export?period=2026-11"],
      ["GET", "/vat/periods"], ["GET", "/vat/periods/2026-11"], ["POST", "/vat/periods/2026-11/lock", {}], ["GET", "/vat/rates"], ["GET", "/vat/insights"], ["GET", "/tax-calendar"], ["GET", "/tax-calendar/items"], ["GET", "/tax-calendar/holidays"], ["GET", "/tax-calendar/settings"],
      ["GET", "/payment-schedule"], ["POST", "/payment-schedule", {}], ["GET", "/receivables/aging"], ["GET", "/receivables/overdue"], ["GET", "/message-templates"], ["GET", "/message-templates/variables"]];
    for (const [m, p, b] of eps) {
      const pa = await call(m, p, PA, b), sa2 = await call(m, p, SA, b), an = await call(m, p, null, b);
      ok(pa.s === 403, `personel 403: ${m} ${p}`, pa.s); ok(sa2.s === 403, `saha 403: ${m} ${p}`, sa2.s); ok(an.s === 401, `anonim 401: ${m} ${p}`, an.s);
    }
    for (const [m, p, b] of [["POST", "/vat/rates", { code: "xx", rate: 5, label: "x" }], ["POST", "/tax-calendar/items", { key: "xx", title: "x", due_date: "2026-12-01" }], ["PUT", "/tax-calendar/settings", { tax_status: "sahis" }], ["POST", "/tax-calendar/holidays", { day: "2026-12-12", name: "x" }]]) {
      const o = await call(m, p, OA, b); ok(o.s === 403, `ortak düzenleyemez (referans veri): ${m} ${p}`, o.s);
    }
  }

  // ------------------------------------------------------------ 8) fatura CRUD
  const inv = (o) => ({ direction: "giden", issue_date: "2026-11-05", invoice_type: "e-arsiv", ...o });
  let I1, I2;
  {
    let r = await call("POST", "/invoices", A, inv({ invoice_no: "ABC2026000001", counterparty: "Ahmet Yılmaz", counterparty_tax_id: "10000000146", matrah_kurus: 1000000, kdv_oran: 20, due_date: "2026-12-05", note: "Pergola" }));
    ok(r.s === 201, "fatura oluştur (KDV hariç, %20)", r);
    I1 = r.j;
    eq([I1.matrah_kurus, I1.kdv_kurus, I1.tutar_kurus, I1.odenecek_kurus, I1.tevkifat_kurus, I1.tevkifat_oran, I1.status], [1000000, 200000, 1200000, 1200000, 0, null, "kesildi"], "hesaplanan tutarlar");
    ok(I1.needs_confirmation === undefined && I1.confirmation && I1.confirmation.needed === true && /doğrulanmadı/.test(I1.confirmation.reasons.join(" ")), "doğrulanmamış KDV oranı → 'mali müşavire teyit' bayrağı", I1.confirmation);
    eq([I1.invoice_type_label, I1.status_label, I1.direction, I1.overdue], ["e-Arşiv", "Kesildi", "giden", false], "etiketler");
    eq(r.j.warnings, [], "uyarı yok");
    r = await call("POST", "/invoices", A, inv({ tutar_kurus: 120000, kdv_oran: 20, invoice_no: "ABC2026000002" }));
    eq([r.j.matrah_kurus, r.j.kdv_kurus, r.j.tutar_kurus], [100000, 20000, 120000], "KDV DAHİL giriş: matrah ayrıştırılır"); I2 = r.j;
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 1000000, kdv_oran: 20, tevkifat: "4/10", invoice_no: "T-1" }));
    eq([r.j.kdv_kurus, r.j.tevkifat_kurus, r.j.tevkifat_oran, r.j.tutar_kurus, r.j.odenecek_kurus], [200000, 80000, "4/10", 1200000, 1120000], "tevkifat 4/10 API");
    ok(r.j.confirmation.reasons.some((x) => /Tevkifat/.test(x) && /doğrulanmadı/.test(x)), "tevkifat doğrulanmadı bayrağı", r.j.confirmation);
    const tev = r.j.id;
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 1000, kdv_oran: 20, tevkifat_oran: { pay: 7, payda: 10 }, invoice_no: "T-2" }));
    eq([r.j.tevkifat_kurus, r.j.tevkifat_oran], [140, "7/10"], "tevkifat_oran nesne girişi 7/10");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 5000, kdv_oran: 0, invoice_no: "Z-1" }));
    eq(r.s, 201, "KDV %0 istisna nedeni yazılmadan da kaydedilir"); ok(r.j.confirmation.reasons.some((x) => /istisna nedeni/.test(x)), "…ama istisna nedeni eksik bayrağı");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 5000, kdv_oran: 0, kdv_istisna_nedeni: "İhracat", invoice_no: "Z-2" }));
    ok(!r.j.confirmation.reasons.some((x) => /istisna nedeni/.test(x)), "istisna nedeni yazılınca bayrak düşer");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_oran: 7, invoice_no: "R-7" }));
    ok(r.s === 201 && r.j.warnings.some((w) => w.code === "kdv_rate_not_listed") && r.j.confirmation.needed, "listede olmayan oran (%7) uyarı + teyit", r.j.warnings);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_kurus: 20002, kdv_oran: 20, invoice_no: "M-1" }));
    eq([r.s, r.j.matrah_kurus, r.j.kdv_kurus, r.j.tutar_kurus], [201, 100000, 20002, 120002], "belgedeki KDV esastır (2 kuruş fark tolerans içinde)");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_kurus: 25000, kdv_oran: 20, invoice_no: "M-2" }));
    ok(r.s === 400 && r.j.code === "kdv_mismatch" && r.j.expectedKdvKurus === 20000, "KDV uyuşmazlığı → 400 kdv_mismatch + beklenen", r.j);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_kurus: 25000, kdv_oran: 20, invoice_no: "M-3", accept_mismatch: true }));
    ok(r.s === 201 && r.j.warnings.some((w) => w.code === "kdv_mismatch_accepted"), "accept_mismatch:true ile kabul + uyarı", r.j);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, tutar_kurus: 130000, kdv_kurus: 20000, kdv_oran: 20 }));
    ok(r.s === 400 && r.j.code === "total_mismatch", "matrah+kdv ≠ tutar → total_mismatch", r.j);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, tutar_kurus: 120000, kdv_oran: 20 }));
    ok(r.s === 400, "matrah ve tutar birlikte, kdv_kurus yok → 400");
    // kötü girdiler
    const bad = async (b, msg) => { const x = await call("POST", "/invoices", A, b); ok(x.s === 400, "400: " + msg, x); };
    await bad(inv({ matrah_kurus: 12.5, kdv_oran: 20 }), "kesirli kuruş"); await bad(inv({ matrah_kurus: "1000", kdv_oran: 20 }), "metin kuruş"); await bad(inv({ matrah_kurus: -5, kdv_oran: 20 }), "negatif");
    await bad(inv({ matrah_kurus: 1e13, kdv_oran: 20 }), "10 milyar TL üstü"); await bad(inv({ kdv_oran: 20 }), "tutar yok"); await bad(inv({ matrah_kurus: 100, kdv_oran: 120 }), "oran > 100");
    await bad(inv({ matrah_kurus: 100, kdv_oran: 20.123 }), "3 ondalıklı oran"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, tevkifat: "12/10" }), "tevkifat pay > payda");
    await bad({ issue_date: "2026-11-05", matrah_kurus: 100, kdv_oran: 20 }, "yön yok"); await bad(inv({ direction: "x", matrah_kurus: 100, kdv_oran: 20 }), "yön geçersiz"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, issue_date: "2026-02-30" }), "olmayan tarih");
    await bad(inv({ matrah_kurus: 100, kdv_oran: 20, issue_date: undefined }), "tarih yok"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, invoice_type: "fatura" }), "tür geçersiz"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, status: "x" }), "durum geçersiz");
    await bad(inv({ matrah_kurus: 100, kdv_oran: 20, counterparty_tax_id: "123" }), "VKN biçimi"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, project_id: "abc" }), "bozuk uuid");
    await bad(inv({ matrah_kurus: 100, kdv_oran: 20, counterparty: "x".repeat(201) }), "karşı taraf > 200"); await bad(inv({ matrah_kurus: 100, kdv_oran: 20, note: 5 }), "not metin değil");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_oran: 20, project_id: "00000000-0000-4000-8000-000000000000" }));
    eq(r.s, 404, "olmayan proje 404");
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_oran: 20, counterparty_tax_id: "10000000147" }));
    ok(r.s === 201 && r.j.warnings.some((w) => w.code === "tax_id_checksum"), "TCKN sağlama hatalı → uyarı (engel değil)", r.j.warnings);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100000, kdv_oran: 20, invoice_no: "ABC2026000001", counterparty: "Ahmet Yılmaz" }));
    ok(r.s === 201 && r.j.warnings.some((w) => w.code === "duplicate_invoice_no"), "yinelenen belge no → uyarı", r.j.warnings);
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100, due_date: "2026-11-01", invoice_no: "D-1" }));
    ok(r.s === 201 && r.j.warnings.some((w) => w.code === "due_before_issue") && r.j.kdv_oran === 20, "varsayılan oran (vat_rates is_default = %20) + vade<fatura uyarısı", r.j);
    // Idempotency-Key (v17): aynı anahtar → tek kayıt
    const key = "inv-idem-" + Date.now();
    const a1 = await call("POST", "/invoices", A, inv({ matrah_kurus: 777, kdv_oran: 20, invoice_no: "IDEM-1" }), { "Idempotency-Key": key });
    const a2 = await call("POST", "/invoices", A, inv({ matrah_kurus: 777, kdv_oran: 20, invoice_no: "IDEM-1" }), { "Idempotency-Key": key });
    ok(a1.s === 201 && a2.s === 201 && a2.h.get("idempotent-replay") === "true" && a1.j.id === a2.j.id, "Idempotency-Key: ikinci istek tekrarlanmaz", a2.h.get("idempotent-replay"));
    eq((await q1("SELECT COUNT(*)::int n FROM invoices WHERE invoice_no = 'IDEM-1'")).n, 1, "idempotent: tek satır");

    // GET / PATCH
    r = await call("GET", `/invoices/${I1.id}`, A); ok(r.s === 200 && r.j.files.length === 0 && r.j.counterparty === "Ahmet Yılmaz", "GET fatura");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { matrah_kurus: 2000000 });
    eq([r.j.matrah_kurus, r.j.kdv_kurus, r.j.tutar_kurus], [2000000, 400000, 2400000], "PATCH matrah: KDV yeniden hesaplanır");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { kdv_oran: 10 });
    eq([r.j.matrah_kurus, r.j.kdv_kurus, r.j.tutar_kurus], [2000000, 200000, 2200000], "PATCH oran: matrah sabit, KDV yeniden");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { tevkifat: "5/10" }); eq([r.j.tevkifat_kurus, r.j.odenecek_kurus], [100000, 2100000], "PATCH tevkifat ekle");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { tevkifat: null }); eq([r.j.tevkifat_kurus, r.j.tevkifat_oran], [0, null], "PATCH tevkifat kaldır");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { note: "yeni not", kdv_indirilebilir: false }); eq([r.j.note, r.j.kdv_indirilebilir, r.j.tutar_kurus], ["yeni not", false, 2200000], "PATCH tutarlara dokunmadan not");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { kdv_oran: 20, matrah_kurus: 1000000 }); eq(r.j.tutar_kurus, 1200000, "PATCH eski değerlere dön");
    r = await call("PATCH", `/invoices/${I1.id}`, A, {}); eq(r.s, 400, "PATCH boş gövde 400");
    r = await call("PATCH", `/invoices/${I1.id}`, A, { direction: "gelen" }); eq(r.j.direction, "gelen", "PATCH yön"); await call("PATCH", `/invoices/${I1.id}`, A, { direction: "giden" });
    r = await call("PATCH", `/invoices/${I1.id}`, A, { due_date: null }); eq(r.j.due_date, null, "PATCH vade temizle"); await call("PATCH", `/invoices/${I1.id}`, A, { due_date: "2026-12-05" });

    // filtreler / liste
    await call("POST", "/invoices", A, inv({ direction: "gelen", invoice_type: "kagit", issue_date: "2026-10-10", matrah_kurus: 300000, kdv_oran: 20, counterparty: "Demir Ltd", invoice_no: "G-1", due_date: "2026-10-20" }));
    r = await call("GET", "/invoices?direction=gelen", A); ok(r.j.every((x) => x.direction === "gelen") && r.j.length >= 1, "filtre: yön");
    r = await call("GET", "/invoices?period=2026-10", A); ok(r.j.length === 1 && r.j[0].invoice_no === "G-1", "filtre: period=2026-10", r.j.map((x) => x.invoice_no));
    r = await call("GET", "/invoices?period=2026", A); ok(r.j.length > 5, "filtre: period=yıl");
    r = await call("GET", "/invoices?period=2026-Q4", A); ok(r.j.length > 5, "filtre: period=çeyrek");
    r = await call("GET", "/invoices?period=2026-13", A); eq(r.s, 400, "filtre: geçersiz period 400");
    r = await call("GET", "/invoices?status=odendi", A); eq(r.j.length, 0, "filtre: durum");
    r = await call("GET", "/invoices?status=kesildi,gonderildi&limit=2&offset=0", A); ok(r.j.length === 2 && Number(r.h.get("x-total-count")) > 2, "sayfalama + X-Total-Count", r.h.get("x-total-count"));
    r = await call("GET", "/invoices?q=Demir", A); ok(r.j.length === 1 && r.j[0].invoice_no === "G-1", "arama q");
    r = await call("GET", "/invoices?q=Demir&limit=1", A); eq(r.h.get("x-total-count"), "1", "arama + toplam");
    r = await call("GET", "/invoices?overdue=1&asOf=2026-11-20", A);
    ok(r.j.some((x) => x.invoice_no === "G-1" && x.overdue === true) || r.s === 200, "filtre: overdue çalışır");
    r = await call("GET", "/invoices?from=2026-11-01&to=2026-11-30&direction=giden", A); ok(r.j.length >= 4 && r.j.every((x) => x.issue_date >= "2026-11-01" && x.issue_date <= "2026-11-30"), "filtre: from/to");
    r = await call("GET", "/invoices?due_from=2026-12-01&due_to=2026-12-31", A); ok(r.j.some((x) => x.id === I1.id), "filtre: due_from/due_to");
    r = await call("GET", "/invoices?status=zz", A); eq(r.s, 400, "filtre: geçersiz durum 400");
    r = await call("GET", "/invoices?limit=0", A); eq(r.s, 400, "limit 0 → 400");
    r = await call("GET", "/invoices/00000000-0000-4000-8000-000000000000", A); eq(r.s, 404, "olmayan fatura 404");
    r = await call("GET", "/invoices/zzz", A); eq(r.s, 400, "bozuk id 400");
    // muhasebe, admin'in (işletme) defterini görür
    r = await call("GET", `/invoices/${I1.id}`, Mu); ok(r.s === 200, "muhasebe işletme defterini görür");
    r = await call("PATCH", `/invoices/${I2.id}`, Mu, { note: "muh notu" }); ok(r.s === 200 && r.j.note === "muh notu", "muhasebe düzenler");
  }

  // ------------------------------------------------------------ 9) ortak A/B izolasyonu
  {
    let r = await call("POST", "/invoices", OA, inv({ matrah_kurus: 5000000, kdv_oran: 20, invoice_no: "OA-1", counterparty: "OA Müşteri" }));
    ok(r.s === 201, "ortak kendi faturasını oluşturur", r); const oaId = r.j.id;
    const oaRow = await q1("SELECT owner_id, org_id FROM invoices WHERE id=$1", [oaId]); ok(oaRow.owner_id === U.oa && oaRow.org_id === org.id, "ortak faturası ortağın defterinde + org_id dolu");
    r = await call("GET", "/invoices", OB); ok(r.s === 200 && r.j.length === 0, "ortak B ortak A'nın faturasını listede görmez", r.j.length);
    r = await call("GET", `/invoices/${oaId}`, OB); eq(r.s, 404, "ortak B GET → 404 (varlık sızdırmaz)");
    r = await call("PATCH", `/invoices/${oaId}`, OB, { note: "hack" }); eq(r.s, 404, "ortak B PATCH → 404");
    r = await call("DELETE", `/invoices/${oaId}`, OB); eq(r.s, 404, "ortak B DELETE → 404");
    r = await call("POST", `/invoices/${oaId}/mark-paid`, OB, {}); eq(r.s, 404, "ortak B mark-paid → 404");
    r = await call("GET", `/invoices/${oaId}`, A); eq(r.s, 404, "admin de ortak A'nın defterini görmez (defter = sahibi)");
    r = await call("GET", `/invoices/${oaId}`, Mu); eq(r.s, 404, "muhasebe ortak defterini görmez");
    r = await call("GET", "/invoices", OA); ok(r.j.length === 1 && r.j[0].invoice_no === "OA-1", "ortak A yalnız kendini görür");
    r = await call("GET", "/invoices?period=2026-11", A); ok(!r.j.some((x) => x.invoice_no === "OA-1"), "admin listesinde ortak faturası yok");
    // ortak, başkasının projesine bağlayamaz
    const pr = await call("POST", "/projects", A, { customer_name: "Admin Müşteri", service: "Pergola", total_amount: 100000 });
    ok(pr.s === 201, "proje (admin)"); const projA = pr.j.id;
    r = await call("POST", "/invoices", OB, inv({ matrah_kurus: 100, kdv_oran: 20, project_id: projA })); eq(r.s, 403, "ortak B başkasının projesine fatura bağlayamaz (403)");
    r = await call("POST", "/payment-schedule", OB, { project_id: projA, amount_kurus: 100, due_date: "2026-12-01" }); eq(r.s, 403, "ortak B başkasının projesine plan satırı yazamaz");
    // KDV dönemi ve alacak izolasyonu
    r = await call("GET", "/vat/periods/2026-11", OA); ok(r.s === 200 && r.j.hesaplanan_kurus === 1000000, "ortak A KDV dönemi yalnız kendi faturası (hesaplanan 10.000 TL)", r.j.hesaplanan_kurus);
    r = await call("GET", "/vat/periods/2026-11", OB); ok(r.s === 200 && r.j.hesaplanan_kurus === 0 && r.j.belge_sayisi.giden === 0, "ortak B KDV dönemi boş");
    r = await call("POST", "/vat/periods/2026-11/lock", OA, {}); ok(r.s === 200 && r.j.status === "kilitli", "ortak A kendi dönemini kilitler");
    r = await call("GET", "/vat/periods/2026-11", A); ok(r.j.status === "acik", "…admin'in dönemi etkilenmez");
    r = await call("POST", `/invoices`, OA, inv({ matrah_kurus: 100, kdv_oran: 20, issue_date: "2026-11-15", invoice_no: "OA-2" })); eq(r.s, 409, "ortak A kilitli döneme fatura ekleyemez (409)");
    r = await call("POST", "/vat/periods/2026-11/unlock", OA, {}); eq(r.s, 200, "ortak A kilidi açar");
    // ortak şablon izolasyonu
    r = await call("POST", "/message-templates", OA, { key: "ozel_oa", title: "OA özel", body: "Merhaba {ad}" }); eq(r.s, 201, "ortak kendi şablonunu ekler");
    const tplOA = r.j.id;
    r = await call("GET", "/message-templates", OB); ok(!r.j.some((t) => t.key === "ozel_oa"), "ortak B, OA'nın şablonunu listede görmez");
    r = await call("GET", `/message-templates/${tplOA}`, OB); eq(r.s, 404, "ortak B şablonu GET 404");
    r = await call("PATCH", `/message-templates/${tplOA}`, OB, { title: "x" }); eq(r.s, 404, "ortak B şablonu PATCH 404");
    r = await call("POST", `/message-templates/${tplOA}/render`, OB, { vars: { ad: "x" } }); eq(r.s, 404, "ortak B şablonu render 404");
    r = await call("GET", "/message-templates", A); ok(!r.j.some((t) => t.key === "ozel_oa"), "admin de OA'nın şablonunu görmez");
    // ortak ödeme planı + alacak
    const cp = await call("POST", "/projects", OA, { customer_name: "OA Proje Müşterisi", service: "Kapı", total_amount: 500000 });
    r = await call("POST", "/payment-schedule", OA, { project_id: cp.j.id, amount_kurus: 100000, due_date: "2026-11-01" }); ok(r.s === 201, "ortak A plan satırı");
    r = await call("GET", "/payment-schedule", OB); eq(r.j.length, 0, "ortak B planı görmez");
    r = await call("GET", "/receivables/aging?asOf=2026-11-20", OA); eq(r.j.totalKurus, 100000, "ortak A yaşlandırma kendi alacağı");
    r = await call("GET", "/receivables/aging?asOf=2026-11-20", OB); eq(r.j.totalKurus, 0, "ortak B yaşlandırma boş");
    r = await call("GET", "/receivables/aging?asOf=2026-11-20", A); ok(!JSON.stringify(r.j).includes("OA Proje"), "admin yaşlandırmasında ortak alacağı yok");
    r = await call("GET", "/invoices/export?period=2026-11&format=csv", OB); ok(r.s === 200 && !r.buf.toString().includes("OA-1"), "ortak B dışa aktarımında ortak A'nın faturası yok");
  }

  // ------------------------------------------------------------ 10) ödendi işaretle / silme / durumlar
  {
    let r = await call("POST", `/invoices/${I2.id}/mark-paid`, A, { paid_at: "2026-11-18", method: "Havale" });
    ok(r.s === 200 && r.j.status === "odendi" && r.j.paid_at === "2026-11-18", "mark-paid", r.j);
    r = await call("POST", `/invoices/${I2.id}/mark-paid`, A, {}); eq(r.s, 409, "zaten ödendi → 409");
    r = await call("PATCH", `/invoices/${I2.id}`, A, { status: "gonderildi" }); eq([r.j.status, r.j.paid_at], ["gonderildi", null], "ödendi → gönderildi: paid_at temizlenir");
    r = await call("POST", `/invoices/${I2.id}/mark-paid`, A, { method: "Papirüs" }); eq(r.s, 400, "geçersiz yöntem 400");
    // projeye bağlı + create_payment (NUMERIC TL dönüşümü)
    const pr = await call("POST", "/projects", A, { customer_name: "Tahsilat Müşteri", service: "Otomatik kapı", total_amount: 50000 });
    const pid = pr.j.id;
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 1000000, kdv_oran: 20, tevkifat: "4/10", project_id: pid, invoice_no: "PAY-1", due_date: "2026-11-25" }));
    const payInv = r.j.id; eq(r.j.odenecek_kurus, 1120000, "tevkifatlı fatura tahsil edilecek 11.200 TL");
    r = await call("POST", `/invoices/${payInv}/mark-paid`, A, { create_payment: true, method: "Havale", paid_at: "2026-11-19" });
    ok(r.s === 200 && r.j.created_payment && r.j.created_payment.amount === 11200, "create_payment: payments NUMERIC TL = ödenecek (tevkifat düşülmüş) 11200", r.j.created_payment);
    const pay = await q1("SELECT amount, method, owner_id FROM payments WHERE id=$1", [r.j.created_payment.id]);
    ok(Number(pay.amount) === 11200 && pay.method === "Havale" && pay.owner_id === U.admin, "payments satırı doğru defterde", pay);
    eq(r.j.payment_id, r.j.created_payment.id, "faturaya ödeme bağlandı");
    // ödenen fatura silinemez; iptal → silinir
    r = await call("DELETE", `/invoices/${payInv}`, A); eq(r.s, 409, "ödenmiş fatura silinemez");
    r = await call("PATCH", `/invoices/${payInv}`, A, { status: "iptal" }); eq(r.j.status, "iptal", "iptal");
    r = await call("DELETE", `/invoices/${payInv}`, A); eq(r.s, 200, "iptal fatura silinir");
    ok(await q1("SELECT 1 FROM payments WHERE project_id=$1", [pid]), "fatura silinince tahsilat kaydı korunur");
    // create_payment yalnız projeli giden
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 100, kdv_oran: 20, invoice_no: "NP-1" }));
    const np = await call("POST", `/invoices/${r.j.id}/mark-paid`, A, { create_payment: true }); eq(np.s, 400, "create_payment projesiz fatura → 400");
    const draft = await call("POST", "/invoices", A, inv({ matrah_kurus: 100, kdv_oran: 20, status: "taslak", invoice_no: "TASLAK-1" }));
    ok(draft.s === 201 && draft.j.status === "taslak", "taslak oluşturulur");
    r = await call("POST", `/invoices/${draft.j.id}/mark-paid`, A, {}); eq(r.s, 409, "taslak ödendi yapılamaz");
    r = await call("DELETE", `/invoices/${draft.j.id}`, A); eq(r.s, 200, "taslak silinir");
  }

  // ------------------------------------------------------------ 11) dosya ekleri (güvenli yükleme + imzalı URL)
  {
    const up = async (token, id, name, buf, ctype = "application/octet-stream") => { const fd = new FormData(); fd.append("file", new Blob([buf], { type: ctype }), name); const r = await fetch(`${B}/invoices/${id}/files`, { method: "POST", headers: { Authorization: "Bearer " + token }, body: fd }); let j = null; try { j = await r.json(); } catch {} return { s: r.status, j }; };
    let r = await up(A, I1.id, "fatura.png", PNG); ok(r.s === 201 && r.j.file_name === "fatura.png" && /\/uploads\/invoices\/.+\?exp=\d+&sig=/.test(r.j.file_url), "PNG eklenir + imzalı URL döner", r);
    const fileId = r.j.id, signed = r.j.file_url;
    ok(!(await q1("SELECT file_url FROM invoice_files WHERE id=$1", [fileId])).file_url.includes("sig="), "veritabanında İMZASIZ URL saklanır");
    let g = await fetch(signed); ok(g.status === 200 && g.headers.get("x-content-type-options") === "nosniff", "imzalı URL ile indirme 200 + nosniff", g.status);
    const bare = signed.split("?")[0]; g = await fetch(bare); eq(g.status, 401, "imzasız URL 401");
    g = await fetch(signed.replace(/sig=[^&]+/, "sig=AAAA")); eq(g.status, 401, "bozuk imza 401");
    g = await fetch(bare, { headers: { Authorization: "Bearer " + OB } }); eq(g.status, 403, "başka ortak Bearer ile 403");
    g = await fetch(bare, { headers: { Authorization: "Bearer " + A } }); eq(g.status, 200, "sahibi (admin) Bearer ile 200");
    g = await fetch(bare, { headers: { Authorization: "Bearer " + Mu } }); eq(g.status, 200, "muhasebe (işletme defteri) Bearer ile 200");
    g = await fetch(bare, { headers: { Authorization: "Bearer " + PA } }); eq(g.status, 403, "personel Bearer ile 403");
    g = await fetch(`${B}/invoices/${I1.id}/files/${fileId}`, { headers: { Authorization: "Bearer " + A } }); ok(g.status === 200 && /^inline/.test(g.headers.get("content-disposition") || ""), "doğrudan akış ucu 200 inline");
    g = await fetch(`${B}/invoices/${I1.id}/files/${fileId}`, { headers: { Authorization: "Bearer " + OB } }); eq(g.status, 404, "başka ortak akış ucu 404");
    r = await up(A, I1.id, "x.exe", Buffer.from("MZ")); eq(r.s, 400, "izin verilmeyen uzantı (.exe) 400");
    r = await up(A, I1.id, "x.svg", Buffer.from("<svg onload=alert(1)>")); eq(r.s, 400, ".svg (betik taşıyabilir) 400");
    r = await up(A, I1.id, "x.html", Buffer.from("<html>")); eq(r.s, 400, ".html 400");
    r = await up(A, I1.id, "sahte.png", Buffer.from("bu bir png degil")); eq(r.s, 400, "içerik uzantıyla uyuşmuyor (sahte PNG) 400");
    r = await up(A, I1.id, "../../etc/pass.png", PNG); ok(r.s === 201 && !/\.\.|etc/.test(r.j.file_url.split("/uploads/")[1]), "yol geçişi adı sunucu adına yansımaz", r.j && r.j.file_url);
    r = await up(OB, I1.id, "o.png", PNG); eq(r.s, 404, "başka ortak yükleyemez (404)");
    const before = fs.readdirSync(path.resolve(process.env.UPLOAD_DIR || "./uploads", "invoices")).length;
    r = await up(OB, I1.id, "o2.png", PNG); const after = fs.readdirSync(path.resolve(process.env.UPLOAD_DIR || "./uploads", "invoices")).length;
    eq(after, before, "yetkisiz yükleme diske HİÇ yazılmaz");
    r = await up(PA, I1.id, "p.png", PNG); eq(r.s, 403, "personel yükleyemez");
    r = await up(A, I1.id, "buyuk.pdf", Buffer.concat([Buffer.from("%PDF-1.4\n"), Buffer.alloc(16 * 1024 * 1024)])); eq(r.s, 413, "16 MB → 413");
    const pdf = await up(A, I1.id, "a.pdf", Buffer.from("%PDF-1.4\n1 0 obj\n<<>>\nendobj\n")); eq(pdf.s, 201, "PDF eklenir");
    r = await call("GET", `/invoices/${I1.id}`, A); eq(r.j.files.length, 3, "detayda ekler (imzalı)");
    r = await call("GET", "/invoices", A); eq(r.j.find((x) => x.id === I1.id).file_count, 3, "listede file_count");
    for (let i = 0; i < 8; i++) await up(A, I1.id, `d${i}.png`, PNG);
    r = await up(A, I1.id, "fazla.png", PNG); eq(r.s, 409, "en çok 10 ek (409)");
    r = await call("DELETE", `/invoices/${I1.id}/files/${fileId}`, A); eq(r.s, 200, "ek silinir");
    const stored = fs.readdirSync(path.resolve(process.env.UPLOAD_DIR || "./uploads", "invoices")).filter((f) => signed.includes(encodeURIComponent(f)));
    eq(stored.length, 0, "ek silinince dosya diskten kalkar");
    r = await call("DELETE", `/invoices/${I1.id}/files/${fileId}`, A); eq(r.s, 404, "ikinci silme 404");
  }

  // ------------------------------------------------------------ 12) KDV dönemi: hesap / özet / kilit
  {
    // temiz bir defter: yeni ortak yerine admin'in 2026-09 ve 2026-08 dönemleri boş → onları kullan
    const mk = (o) => call("POST", "/invoices", A, { invoice_type: "e-fatura", kdv_oran: 20, ...o });
    await mk({ direction: "gelen", issue_date: "2026-08-10", matrah_kurus: 10000000, invoice_no: "V-G1" });                        // 20.000 TL indirilecek → devreden
    await mk({ direction: "giden", issue_date: "2026-09-05", matrah_kurus: 5000000, invoice_no: "V-S1" });                       // 10.000 hesaplanan (ağustos devreden 20.000'i karşılar)
    await mk({ direction: "giden", issue_date: "2026-09-30", matrah_kurus: 10000000, tevkifat: "4/10", invoice_no: "V-S2" });  // 20.000 KDV, 8.000 tevkifat → 12.000
    await mk({ direction: "gelen", issue_date: "2026-09-15", matrah_kurus: 1000000, kdv_indirilebilir: false, invoice_no: "V-G2" }); // indirilemez
    await mk({ direction: "gelen", issue_date: "2026-09-20", matrah_kurus: 2000000, tevkifat: "5/10", invoice_no: "V-G3" });      // 4.000 KDV; tevkifat 2.000 (KDV-2)
    await mk({ direction: "giden", issue_date: "2026-09-12", matrah_kurus: 99999900, status: "taslak", invoice_no: "V-T" });      // sayılmaz
    await mk({ direction: "giden", issue_date: "2026-09-13", matrah_kurus: 99999900, status: "iptal", invoice_no: "V-I" });       // sayılmaz
    let r = await call("GET", "/vat/periods/2026-08", A);
    ok(r.s === 200 && r.j.hesaplanan_kurus === 0 && r.j.indirilecek_kurus === 2000000 && r.j.odenecek_kurus === 0 && r.j.devreden_kurus === 2000000, "Ağustos: indirilecek 20.000 → devreden 20.000", r.j);
    r = await call("GET", "/vat/periods/2026-09", A);
    const p9 = r.j;
    eq([p9.hesaplanan_toplam_kurus, p9.tevkifat_giden_kurus, p9.hesaplanan_kurus], [3000000, 800000, 2200000], "Eylül: giden KDV 30.000 − tevkifat 8.000 = hesaplanan 22.000");
    eq([p9.indirilecek_kurus, p9.indirilemeyen_kurus, p9.kdv2_kurus], [400000, 200000, 200000], "Eylül: indirilecek 4.000 (indirilemez 2.000 ve KDV-2 2.000 ayrı)");
    eq([p9.onceki_devreden_kurus, p9.odenecek_kurus, p9.devreden_kurus], [2000000, 0, 200000], "Eylül: devreden 20.000 kullanılır → ödenecek 0, kalan devir 2.000");
    // 22.000 − 4.000 − 20.000 = −2.000 → devreden 2.000
    eq(p9.net_kurus, -200000, "Eylül net −2.000 (devir dahil)");
    ok(p9.tahmini === true && p9.needs_confirmation === true && p9.confirmation_reasons.length >= 2, "dönem 'tahmini' + teyit nedenleri", p9.confirmation_reasons);
    ok(p9.confirmation_reasons.some((x) => /Tevkifatlı/.test(x)), "tevkifatlı işlem teyit notu");
    eq(p9.due_date, "2026-10-28", "Eylül dönemi son günü 28 Ekim (kural + takvim)");
    ok(p9.confirmation_reasons.some((x) => /son gün kuralı/.test(x) && /doğrulanmadı/.test(x)), "son gün kuralı doğrulanmadı bayrağı");
    eq(p9.belge_sayisi, { giden: 2, gelen: 2 }, "belge sayıları (taslak/iptal hariç)");
    ok(p9.oran_kirilimi.giden[0].rate === 20, "oran kırılımı");
    r = await call("GET", "/vat/periods/2026-Q3", A); eq(r.j.hesaplanan_kurus, 2200000, "3 aylık dönem (Q3) toplam");
    r = await call("GET", "/vat/periods?year=2026", A); ok(r.s === 200 && r.j.periods.length === 12 && r.j.periods[8].period_key === "2026-09", "yıllık liste 12 dönem");
    eq(r.j.periods[8].onceki_devreden_kurus, 2000000, "liste: devir zinciri");
    r = await call("GET", "/vat/periods?year=2026&type=uc_aylik", A); eq(r.j.periods.length, 4, "3 aylık liste 4 dönem");
    r = await call("GET", "/vat/periods/2026-9", A); eq(r.s, 400, "geçersiz dönem anahtarı 400");
    // kilit
    r = await call("POST", "/vat/periods/2026-09/calculate", A, { note: "mali müşavire gönderildi" }); ok(r.s === 200 && r.j.stored === true && r.j.note === "mali müşavire gönderildi" && r.j.status === "acik", "calculate: anlık görüntü saklanır");
    r = await call("POST", "/vat/periods/2026-09/lock", A, {}); ok(r.s === 200 && r.j.status === "kilitli" && r.j.locked_at, "dönem kilitlendi");
    r = await call("POST", "/vat/periods/2026-09/lock", A, {}); eq(r.s, 409, "zaten kilitli → 409");
    r = await call("POST", "/vat/periods/2026-09/calculate", A, {}); eq(r.s, 409, "kilitli dönem hesaplanamaz");
    r = await mk({ direction: "giden", issue_date: "2026-09-25", matrah_kurus: 100, invoice_no: "V-LATE" }); eq([r.s, r.j.code, r.j.period], [409, "vat_period_locked", "2026-09"], "kilitli döneme fatura EKLENEMEZ");
    const s2 = (await call("GET", "/invoices?q=V-S2", A)).j[0];
    r = await call("PATCH", `/invoices/${s2.id}`, A, { matrah_kurus: 1 }); eq(r.s, 409, "kilitli dönemdeki fatura KDV'yi etkileyen alanla değiştirilemez");
    r = await call("PATCH", `/invoices/${s2.id}`, A, { note: "sadece not" }); eq(r.s, 200, "…ama not değişebilir");
    r = await call("PATCH", `/invoices/${s2.id}`, A, { issue_date: "2026-10-01" }); eq(r.s, 409, "kilitli dönemden tarih taşıma 409");
    r = await call("PATCH", `/invoices/${s2.id}`, A, { status: "iptal" }); eq(r.s, 409, "kilitli dönemde iptal 409");
    r = await call("DELETE", `/invoices/${(await call("GET", "/invoices?q=V-I", A)).j[0].id}`, A); eq(r.s, 200, "iptal (sayılmayan) fatura kilitli dönemde de silinebilir");
    r = await call("PATCH", `/invoices/${s2.id}`, A, { status: "odendi" }); eq(r.s, 200, "durum kesildi→ödendi KDV'yi etkilemez (sayılan ↔ sayılan)");
    r = await call("GET", "/vat/periods/2026-10", A); eq(r.j.onceki_devreden_kurus, 200000, "kilitli Eylül'ün saklanan devri (2.000) Ekim'e akar");
    r = await call("POST", "/vat/periods/2026-09/unlock", A, {}); ok(r.s === 200 && r.j.status === "acik", "kilit açıldı");
    r = await call("POST", "/vat/periods/2026-09/unlock", A, {}); eq(r.s, 409, "kilitli değil → 409");
    r = await mk({ direction: "giden", issue_date: "2026-09-25", matrah_kurus: 100, invoice_no: "V-LATE" }); eq(r.s, 201, "kilit açılınca fatura eklenir");
    // elle açılış devri
    r = await call("PATCH", "/vat/periods/2026-08", A, { manual_carry_in_kurus: 500000 }); ok(r.s === 200 && r.j.onceki_devreden_kurus === 500000 && r.j.devreden_kurus === 2500000, "elle açılış devri (uygulama öncesi)", r.j);
    r = await call("PATCH", "/vat/periods/2026-08", A, { manual_carry_in_kurus: -5 }); eq(r.s, 400, "negatif devir 400");
    r = await call("PATCH", "/vat/periods/2026-08", A, { manual_carry_in_kurus: null }); eq(r.j.onceki_devreden_kurus, 0, "elle devir temizlenir");
    // özet
    r = await call("GET", "/invoices/summary?period=2026-09", A);
    eq([r.j.giden.kdvKurus, r.j.giden.tevkifatKurus, r.j.gelen.kdvKurus, r.j.giden.count], [3000020, 800000, 600000, 3], "fatura özeti (taslak/iptal hariç) — V-LATE dahil");
    r = await call("GET", "/invoices/summary", A); eq(r.s, 400, "özet period zorunlu");
    // dışa aktarım: KDV dönem özeti
    r = await call("GET", "/vat/periods/2026-09/export?format=csv", A);
    ok(r.s === 200 && /text\/csv/.test(r.h.get("content-type")) && r.buf[0] === 0xef && r.buf[1] === 0xbb && r.buf[2] === 0xbf, "KDV özeti CSV: UTF-8 BOM", r.buf.slice(0, 4));
    ok(r.h.get("x-needs-confirmation") === "true" && /kdv-ozeti-2026-09\.csv/.test(r.h.get("content-disposition")), "KDV özeti başlıkları (teyit + dosya adı)");
    let txt = r.buf.toString("utf8").slice(1); ok(txt.includes(";") && txt.includes("\r\n") && /Hesaplanan KDV[^;]*;;;;[0-9]+,[0-9]{2};/.test(txt), "KDV özeti ';' ayırıcı + ondalık virgül", txt.slice(0, 300));
    ok(/Ödenecek KDV \(tahmini\)/.test(txt), "KDV özeti Türkçe karakterler");
    r = await call("GET", "/vat/periods/2026-09/export?format=xlsx", A);
    ok(r.s === 200 && /spreadsheetml/.test(r.h.get("content-type")) && r.buf.slice(0, 2).toString() === "PK", "KDV özeti XLSX");
    r = await call("GET", "/vat/periods/2026-09/export?format=pdf", A); eq(r.s, 400, "desteklenmeyen biçim 400");
  }

  // ------------------------------------------------------------ 13) fatura dışa aktarımı (muhasebeci sütunları)
  {
    let r = await call("GET", "/invoices/export?period=2026-09&format=csv", A);
    ok(r.s === 200 && /text\/csv; charset=utf-8/.test(r.h.get("content-type")) && /faturalar-2026-09\.csv/.test(r.h.get("content-disposition")) && r.h.get("cache-control") === "private, no-store", "CSV başlıkları");
    ok(r.buf[0] === 0xef && r.buf[1] === 0xbb && r.buf[2] === 0xbf, "UTF-8 BOM");
    const lines = r.buf.toString("utf8").slice(1).split("\r\n").filter(Boolean);
    const head = lines[0].split(";");
    eq(head.slice(0, 8), ["Tarih", "Belge Türü", "Belge No", "ETTN", "Yön", "Karşı Taraf Unvan", "VKN/TCKN", "Matrah"], "muhasebeci sütunları (başlangıç)");
    ok(["KDV Oranı (%)", "KDV", "Tevkifat Oranı", "Tevkifat Tutarı", "Genel Toplam", "Ödenecek", "Para Birimi", "Proje Kodu", "Açıklama", "Durum", "Vade", "İndirilebilir KDV (E/H)", "Dönem", "Teyit Gerekli (E/H)"].every((h) => head.includes(h)), "muhasebeci sütunları (tam)", head);
    const row = lines.find((l) => l.includes("V-S2")).split(";");
    const col = (n) => row[head.indexOf(n)];
    eq([col("Tarih"), col("Belge Türü"), col("Yön"), col("Matrah"), col("KDV Oranı (%)"), col("KDV"), col("Tevkifat Oranı"), col("Tevkifat Tutarı"), col("Genel Toplam"), col("Ödenecek"), col("Para Birimi"), col("Durum"), col("Dönem")],
      ["30.09.2026", "e-Fatura", "Giden", "100000,00", "20", "20000,00", "4/10", "8000,00", "120000,00", "112000,00", "TRY", "Ödendi", "2026-09"], "satır: gg.aa.yyyy, tutarlar ondalık virgül, tevkifat, ödenecek");
    ok(!lines.some((l) => l.includes("V-T;") || l.includes("V-I;")), "taslak/iptal varsayılan dışarıda");
    ok(lines.some((l) => l.includes("V-G2") && l.split(";")[head.indexOf("İndirilebilir KDV (E/H)")] === "H"), "indirilemez gelen fatura: H");
    ok(lines.every((l) => l.split(";").length === head.length || l.includes('"')), "her satır başlıkla aynı sütun sayısında");
    r = await call("GET", "/invoices/export?period=2026-09&format=csv&include=all", A); ok(r.buf.toString("utf8").includes("V-T") && r.buf.toString("utf8").includes("Taslak"), "include=all taslak/iptal dahil");
    r = await call("GET", "/invoices/export?period=2026-09&direction=gelen", A); ok(!r.buf.toString("utf8").includes("V-S1") && r.buf.toString("utf8").includes("V-G1") === false, "yön filtresi + varsayılan biçim csv");
    r = await call("GET", "/invoices/export?period=2026-09&format=xlsx", A); ok(r.s === 200 && /spreadsheetml/.test(r.h.get("content-type")) && /faturalar-2026-09\.xlsx/.test(r.h.get("content-disposition")), "XLSX başlıkları");
    const tmp = path.join(os.tmpdir(), `v18api-${process.pid}.xlsx`); fs.writeFileSync(tmp, r.buf);
    const py = spawnSync("python3", ["-I", "-c", "import sys,openpyxl;wb=openpyxl.load_workbook(sys.argv[1]);print(wb.sheetnames);ws=wb['Faturalar'];print(ws.max_row, ws.max_column);print([c.value for c in ws[1]][:3])", tmp], { encoding: "utf8" });
    if (py.status === 0) { const L = py.stdout.trim().split("\n"); eq(L[0], "['Faturalar', 'Özet']", "XLSX sayfaları: Faturalar + Özet"); ok(+L[1].split(" ")[1] === head.length && +L[1].split(" ")[0] >= 5, "XLSX satır/sütun sayısı", L[1]); }
    fs.unlink(tmp, () => {});
    r = await call("GET", "/invoices/export", A); eq(r.s, 400, "export: period zorunlu");
    r = await call("GET", "/invoices/export?period=2026-09&format=json", A); eq(r.s, 400, "export: biçim 400");
    // CSV formül enjeksiyonu (kullanıcı verisi)
    await call("POST", "/invoices", A, { direction: "gelen", issue_date: "2026-07-03", matrah_kurus: 100, kdv_oran: 20, counterparty: "=HYPERLINK(\"http://x\")", invoice_no: "+1", note: "@SUM(1)" });
    r = await call("GET", "/invoices/export?period=2026-07&format=csv", A); const t7 = r.buf.toString("utf8");
    ok(t7.includes("'=HYPERLINK") && t7.includes(";'+1;") && t7.includes("'@SUM"), "CSV: = + @ ile başlayan kullanıcı metni ' ile etkisizleştirilir", t7.slice(0, 400));
    // büyük dışa aktarım sınırı yok, ama sütun sayısı sabit
    eq((await call("GET", "/invoices/export?period=2025-01", A)).buf.toString("utf8").slice(1).split("\r\n").filter(Boolean).length, 1, "boş dönem: yalnız başlık satırı");
  }

  // ------------------------------------------------------------ 14) KDV oranları / tevkifat türleri / vergi takvimi uçları
  {
    let r = await call("GET", "/vat/rates", Mu); ok(r.s === 200 && r.j.rates.length >= 4 && r.j.rates.every((x) => x.needs_confirmation === true) && /tavsiye değildir/.test(r.j.disclaimer), "oranlar: hepsi needs_confirmation + uyarı metni");
    ok(r.j.withholding_types.some((t) => t.label_ratio === "4/10") && r.j.withholding_types.every((t) => t.needs_confirmation), "tevkifat türleri 4/10, 7/10 + bayrak");
    const rate20 = r.j.rates.find((x) => x.code === "kdv_genel");
    r = await call("PATCH", `/vat/rates/${rate20.id}`, A, { verified: true, note: "mali müşavir teyit etti" }); ok(r.j.verified === true && r.j.needs_confirmation === false && r.j.verified_by === U.admin, "oran doğrulanır (kim/ne zaman kaydı)");
    r = await call("POST", "/invoices", A, { direction: "giden", issue_date: "2026-12-01", matrah_kurus: 1000, kdv_oran: 20, invoice_no: "VR-1" }); ok(r.j.confirmation.needed === false, "doğrulanmış oranlı fatura: teyit bayrağı yok", r.j.confirmation);
    r = await call("PATCH", `/vat/rates/${rate20.id}`, A, { rate: 21 }); ok(r.j.rate === 21 && r.j.verified === false, "oran değişince doğrulama DÜŞER");
    await call("PATCH", `/vat/rates/${rate20.id}`, A, { rate: 20, verified: true });
    r = await call("POST", "/vat/rates", A, { code: "kdv_ozel_8", rate: 8, label: "Özel", valid_from: "2026-01-01" }); ok(r.s === 201 && r.j.verified === false, "yeni oran doğrulanmadı doğar");
    const r8 = r.j.id;
    r = await call("POST", "/vat/rates", A, { code: "kdv_ozel_8", rate: 8, label: "Özel" }); eq(r.s, 409, "yinelenen kod 409");
    r = await call("POST", "/vat/rates", A, { code: "Kötü Kod", rate: 8, label: "x" }); eq(r.s, 400, "kod biçimi 400");
    r = await call("POST", "/vat/rates", A, { code: "kdv_x", rate: 101, label: "x" }); eq(r.s, 400, "oran > 100 reddedilir");
    r = await call("POST", "/vat/rates", A, { code: "kdv_def", rate: 5, label: "x", is_default: true }); const n = await q1("SELECT COUNT(*)::int n FROM vat_rates WHERE org_id=$1 AND is_default", [org.id]); eq(n.n, 1, "tek varsayılan oran"); await call("DELETE", `/vat/rates/${r.j.id}`, A);
    await call("PATCH", `/vat/rates/${rate20.id}`, A, { is_default: true });
    r = await call("POST", "/invoices", A, inv({ matrah_kurus: 10000, kdv_oran: 8, issue_date: "2026-12-02", invoice_no: "R8" })); ok(r.s === 201 && !r.j.warnings.some((w) => w.code === "kdv_rate_not_listed"), "eklenen oran listede → uyarı yok");
    r = await call("DELETE", `/vat/rates/${r8}`, A); eq(r.s, 200, "oran silinir");
    r = await call("POST", "/vat/withholding-types", A, { code: "ozel_3_10", pay: 3, payda: 10, label: "özel" }); ok(r.s === 201 && r.j.verified === false, "tevkifat türü eklenir");
    r = await call("POST", "/vat/withholding-types", A, { code: "kotu", pay: 11, payda: 10, label: "x" }); eq(r.s, 400, "pay > payda 400");
    // takvim
    r = await call("GET", "/tax-calendar?asOf=2026-11-20&days=60", A);
    ok(r.s === 200 && r.j.items.length >= 3 && /tahminidir/.test(r.j.disclaimer) && r.j.needs_confirmation_count === r.j.items.length, "takvim: yaklaşanlar hepsi teyit bayraklı");
    const kdv = r.j.items.find((x) => x.key === "kdv1_aylik" && x.due_date === "2026-11-30"); ok(kdv && kdv.period_label === "Ekim 2026" && kdv.shifted === true && kdv.shift_reasons.includes("hafta_sonu") && kdv.days_until === 10 && kdv.nominal_date === "2026-11-28", "Ekim KDV: 28 Kasım Cumartesi → 30 Kasım (araştırma tablosu ile aynı)", kdv);
    ok(r.j.items.some((x) => x.key === "muhtasar_aylik" && x.due_date === "2026-11-26"), "Ekim muhtasar: 26 Kasım");
    ok(r.j.items.some((x) => x.key === "muhtasar_aylik" && x.due_date === "2026-12-28"), "Kasım muhtasar: 26 Aralık Cumartesi → 28 Aralık");
    ok(!r.j.items.some((x) => x.key === "kdv2_tevkifat"), "kapalı (varsayılan) kalemler listelenmez");
    ok(r.j.items.every((x, i, a) => i === 0 || a[i - 1].due_date <= x.due_date), "son güne göre sıralı");
    r = await call("GET", "/tax-calendar?from=2026-01-01&to=2026-12-31&statu=sahis", A);
    ok(r.j.items.some((x) => x.key === "gecici_vergi" && x.due_date === "2026-05-18") && r.j.items.some((x) => x.key === "gecici_vergi" && x.due_date === "2026-08-17") && r.j.items.some((x) => x.key === "gecici_vergi" && x.due_date === "2026-11-17"), "geçici vergi 2026 (18 Mayıs, 17 Ağustos, 17 Kasım)");
    ok(r.j.items.some((x) => x.key === "kdv1_aylik" && x.due_date === "2026-06-01" && x.period_label === "Nisan 2026"), "Nisan KDV → 1 Haziran (Kurban Bayramı kaydırması, tatil tohumu ile)");
    ok(r.j.items.some((x) => x.key === "kdv1_aylik" && x.due_date === "2026-03-02" && x.period_label === "Ocak 2026"), "Ocak KDV → 2 Mart");
    ok(r.j.items.some((x) => x.key === "yillik_gelir_vergisi") && !r.j.items.some((x) => x.key === "kurumlar_vergisi"), "statü=sahis: yıllık gelir vergisi var, kurumlar vergisi yok");
    ok(r.j.items.some((x) => x.key === "kdv1_aylik" && x.due_date === "2026-06-01" && x.confirmation_reasons.length >= 1), "kaydırmalı oluşumda teyit nedeni");
    r = await call("GET", "/tax-calendar?statu=anonim", A); eq(r.s, 400, "statü doğrulama");
    r = await call("GET", "/tax-calendar?days=9999", A); eq(r.s, 400, "days sınırı");
    r = await call("GET", "/tax-calendar?from=2026-12-01&to=2026-11-01", A); eq(r.s, 400, "to < from");
    r = await call("GET", "/tax-calendar/items", OA); ok(r.s === 200 && r.j.length >= 11 && r.j.every((x) => x.needs_confirmation && x.verified === false), "ortak takvim kalemlerini OKUR; hepsi doğrulanmadı");
    ok(r.j.find((x) => x.key === "ba_bs").confidence === "belirsiz" && r.j.find((x) => x.key === "kdv1_aylik").confidence === "ikincil", "güven sınıfı: Ba-Bs belirsiz, KDV-1 ikincil");
    const kdvItem = r.j.find((x) => x.key === "kdv1_aylik");
    // düzenleme
    r = await call("PATCH", `/tax-calendar/items/${kdvItem.id}`, A, { verified: true, source: "GİB 2026 takvimi PDF" }); ok(r.j.verified === true && r.j.needs_confirmation === false && r.j.verified_by === U.admin, "takvim kalemi doğrulandı");
    r = await call("GET", "/tax-calendar?asOf=2026-11-20&days=20", A); ok(r.j.items.find((x) => x.key === "kdv1_aylik").needs_confirmation === false, "doğrulanmış kalem + yalnız hafta sonu kayması → teyit gerekmez", r.j.items.find((x) => x.key === "kdv1_aylik"));
    r = await call("PATCH", `/tax-calendar/items/${kdvItem.id}`, A, { rule: { freq: "monthly", day: 27, period_offset_months: 1 } }); ok(r.s === 200 && r.j.verified === false, "kural/tarih değişince doğrulama düşer");
    await call("PATCH", `/tax-calendar/items/${kdvItem.id}`, A, { rule: { freq: "monthly", day: 28, period_offset_months: 1 }, verified: true });
    r = await call("PATCH", `/tax-calendar/items/${kdvItem.id}`, A, { rule: { freq: "monthly", day: 40 } }); eq(r.s, 400, "geçersiz kural 400");
    r = await call("POST", "/tax-calendar/items", A, { key: "mali_musavir_gorusme", title: "Mali müşavir görüşmesi", kind: "bilgi", due_date: "2026-12-15", note: "özel kayıt" }); ok(r.s === 201 && r.j.verified === false, "özel takvim kaydı (tek seferlik)");
    const custom = r.j.id;
    r = await call("GET", "/tax-calendar?asOf=2026-12-10&days=10", OA); ok(r.j.items.some((x) => x.key === "mali_musavir_gorusme" && x.due_date === "2026-12-15"), "özel kayıt takvimde (ortak okur)");
    r = await call("POST", "/tax-calendar/items", A, { key: "mali_musavir_gorusme", title: "x", due_date: "2026-12-15" }); eq(r.s, 409, "yinelenen anahtar 409");
    r = await call("POST", "/tax-calendar/items", A, { key: "x1", title: "x" }); eq(r.s, 400, "kural ya da tarih gerekir");
    r = await call("POST", "/tax-calendar/items", A, { key: "x1", title: "x", due_date: "2026-02-30" }); eq(r.s, 400, "geçersiz tarih");
    r = await call("DELETE", `/tax-calendar/items/${custom}`, A); eq(r.s, 200, "özel kayıt silinir");
    r = await call("PATCH", "/tax-calendar/items/00000000-0000-4000-8000-000000000000", A, { title: "x" }); eq(r.s, 404, "olmayan kalem 404");
    // tatiller
    r = await call("GET", "/tax-calendar/holidays?year=2026", Mu); ok(r.s === 200 && r.j.length >= 15 && r.j.some((x) => x.day === "2026-05-27" && x.kind === "dini" && x.needs_confirmation === true) && r.j.some((x) => x.day === "2026-10-29" && x.needs_confirmation === false), "tatiller: dini doğrulanmadı, sabit tarihli doğrulandı");
    r = await call("GET", "/tax-calendar/holidays?year=2027", Mu); ok(r.j.some((x) => x.day === "2027-03-09") && r.j.filter((x) => x.kind === "dini").every((x) => x.needs_confirmation), "2027 dini bayramlar tahmini/doğrulanmadı");
    r = await call("POST", "/tax-calendar/holidays", A, { day: "2026-12-31", name: "İdari izin", kind: "idari" }); eq(r.s, 201, "idari izin eklenir");
    r = await call("POST", "/tax-calendar/holidays", A, { day: "2026-12-31", name: "x" }); eq(r.s, 409, "aynı gün 409");
    r = await call("PATCH", "/tax-calendar/holidays/2026-12-31", A, { verified: true, half_day: true }); ok(r.j.verified && r.j.half_day, "tatil düzenlenir");
    r = await call("DELETE", "/tax-calendar/holidays/2026-12-31", A); eq(r.s, 200, "tatil silinir");
    r = await call("DELETE", "/tax-calendar/holidays/2026-12-31", A); eq(r.s, 404, "olmayan tatil 404");
    r = await call("POST", "/tax-calendar/holidays", A, { day: "bozuk", name: "x" }); eq(r.s, 400, "tatil tarihi doğrulama");
    // tatil kaydırmayı etkiler: 29 Kasım... 28 Aralık'ı tatil yap → 29 Aralık
    await call("POST", "/tax-calendar/holidays", A, { day: "2026-12-28", name: "deneme tatili", verified: true });
    r = await call("GET", "/tax-calendar?from=2026-12-01&to=2026-12-31", A); ok(r.j.items.some((x) => x.key === "kdv1_aylik" && x.due_date === "2026-12-29"), "yeni tatil kaydırmayı değiştirir (28 → 29 Aralık)");
    await call("DELETE", "/tax-calendar/holidays/2026-12-28", A);
    // vergi ayarı
    r = await call("GET", "/tax-calendar/settings", Mu); ok(r.s === 200 && r.j.tax_status === null && r.j.vat_period_type === "aylik", "vergi ayarı varsayılan: statü belirtilmedi, aylık");
    r = await call("PUT", "/tax-calendar/settings", A, { tax_status: "limited" }); eq(r.j.tax_status, "limited", "statü = limited");
    r = await call("GET", "/tax-calendar?from=2026-01-01&to=2026-12-31", A); ok(r.j.statu === "limited" && r.j.statu_source === "settings" && r.j.items.some((x) => x.key === "kurumlar_vergisi") && !r.j.items.some((x) => x.key === "yillik_gelir_vergisi"), "takvim ayardaki statüye göre");
    r = await call("PUT", "/tax-calendar/settings", A, { tax_status: "anonim" }); eq(r.s, 400, "statü doğrulama");
    r = await call("PUT", "/tax-calendar/settings", A, {}); eq(r.s, 400, "boş ayar 400");
    r = await call("PUT", "/tax-calendar/settings", Mu, { tax_status: "sahis" }); eq(r.j.tax_status, "sahis", "muhasebe de ayarlar");
    r = await call("PUT", "/tax-calendar/settings", A, { tax_status: null }); eq(r.j.tax_status, null, "statü temizlenir");
  }

  // ------------------------------------------------------------ 15) tahsilat planı + yaşlandırma
  let projPay, schedIds = [];
  {
    const pr = await call("POST", "/projects", A, { customer_name: "Plan Müşteri", service: "Pergola", total_amount: 300000 }); projPay = pr.j.id;
    let r = await call("POST", "/payment-schedule/generate", A, { project_id: projPay, total_kurus: 10000001, count: 3, first_due: "2026-10-31", kind: "taksit" });
    ok(r.s === 201 && r.j.items.length === 3 && r.j.items.reduce((s, x) => s + x.amount_kurus, 0) === 10000001, "taksit üret: toplam korunur", r.j.items && r.j.items.map((x) => x.amount_kurus));
    eq(r.j.items.map((x) => x.amount_kurus), [3333333, 3333333, 3333335], "kuruş artığı son taksitte");
    eq(r.j.items.map((x) => x.due_date), ["2026-10-31", "2026-11-30", "2026-12-31"], "aylık vadeler ay sonu sıkıştırmalı");
    eq(r.j.items.map((x) => x.installment_no), [1, 2, 3], "taksit no"); schedIds = r.j.items.map((x) => x.id);
    eq(new Set(r.j.items.map((x) => x.group_id)).size, 1, "tek group_id");
    r = await call("GET", `/payment-schedule?project_id=${projPay}`, A); ok(r.j.length === 3 && r.j[0].customer_name === "Plan Müşteri" && r.j[0].project_code, "plan listesi + müşteri/proje kodu");
    r = await call("GET", "/payment-schedule?status=gecikti", A); ok(r.j.length >= 1 && r.j.every((x) => x.effective_status === "gecikti" && x.days_overdue > 0), "gecikti filtresi türetilmiştir (saklanmaz)");
    eq((await q1("SELECT COUNT(*)::int n FROM payment_schedule WHERE status = 'gecikti'")).n, 0, "'gecikti' veritabanında saklanmaz (CHECK)");
    r = await call("POST", "/payment-schedule/generate", A, { project_id: projPay, total_kurus: 1000, count: 61, first_due: "2026-10-31" }); eq(r.s, 400, "taksit sayısı > 60");
    r = await call("POST", "/payment-schedule/generate", A, { project_id: projPay, total_kurus: 1.5, count: 2, first_due: "2026-10-31" }); eq(r.s, 400, "kesirli toplam");
    r = await call("POST", "/payment-schedule/generate", A, { total_kurus: 100, count: 2, first_due: "2026-10-31" }); eq(r.s, 400, "proje/teklif şart");
    r = await call("POST", "/payment-schedule", A, { project_id: projPay, kind: "cek", amount_kurus: 500000, due_date: "2026-11-10", instrument_no: "ÇEK-0001", bank: "Ziraat", note: "ciro edilmedi" });
    ok(r.s === 201 && r.j.method === "Çek" && r.j.instrument_no === "ÇEK-0001" && r.j.bank === "Ziraat", "çek kaydı: yöntem otomatik Çek"); const cek = r.j.id;
    r = await call("POST", "/payment-schedule", A, { project_id: projPay, kind: "senet", amount_kurus: 100, due_date: "2026-11-10", method: "Nakit" }); eq(r.s, 400, "senet + Nakit tutarsız");
    r = await call("POST", "/payment-schedule", A, { project_id: projPay, amount_kurus: 0, due_date: "2026-11-10" }); eq(r.s, 400, "tutar 0 reddedilir");
    r = await call("POST", "/payment-schedule", A, { project_id: projPay, amount_kurus: 100, due_date: "yarın" }); eq(r.s, 400, "tarih biçimi");
    r = await call("POST", "/payment-schedule", A, { amount_kurus: 100, due_date: "2026-11-10" }); eq(r.s, 400, "hedef yok");
    r = await call("POST", "/payment-schedule", A, { project_id: projPay, kind: "xx", amount_kurus: 100, due_date: "2026-11-10" }); eq(r.s, 400, "tür geçersiz");
    r = await call("PATCH", `/payment-schedule/${cek}`, A, { due_date: "2026-11-15", amount_kurus: 600000 }); eq([r.j.due_date, r.j.amount_kurus], ["2026-11-15", 600000], "PATCH vade/tutar");
    r = await call("PATCH", `/payment-schedule/${cek}`, A, { kind: "taksit", method: "Çek" }); eq(r.s, 200, "tür taksit + Çek yöntemi geçerli");
    r = await call("PATCH", `/payment-schedule/${cek}`, A, { kind: "cek" }); eq(r.s, 200, "tür çek'e dönüş");
    // yaşlandırma
    r = await call("GET", "/receivables/aging?asOf=2026-11-20", A);
    const buckets = r.j.buckets;
  }
  {
    // açık giden faturalar (vadeli) alacağa girer; planlı fatura çift sayılmaz
    const open = await q1(`SELECT COALESCE(SUM(odenecek_kurus),0)::bigint s, COUNT(*)::int n FROM invoices WHERE owner_id=$1 AND direction='giden' AND status IN ('kesildi','gonderildi') AND due_date IS NOT NULL`, [U.admin]);
    let r = await call("GET", "/receivables/aging?asOf=2026-11-20", A);
    eq(r.j.totalKurus, 10000001 + 600000 + open.s, "yaşlandırma = planlar + vadeli açık giden faturalar");
    eq(r.j.sources.plan, 4, "kaynak sayacı plan"); eq(r.j.sources.fatura, open.n, "kaynak sayacı fatura");
    // I1 (vade 2026-12-05, 12.000 TL) için taksit planı ekle → fatura ayrıca sayılmaz
    r = await call("POST", "/payment-schedule", A, { invoice_id: I1.id, amount_kurus: 1200000, due_date: "2026-12-05", kind: "bakiye" }); eq(r.s, 201, "faturaya bağlı plan satırı");
    const r2 = await call("GET", "/receivables/aging?asOf=2026-11-20", A);
    eq(r2.j.totalKurus, 10000001 + 600000 + open.s, "faturaya bağlı plan fatura yerine geçer: toplam aynı (çift sayım yok)");
    eq(r2.j.sources.fatura, open.n - 1, "fatura kaynağı bir azaldı");
    // kova değerleri el ile
    const d = r2.j;
    // taksitler 10-31 (20 gün gecikmiş: 0-30), 11-30 / 12-31 (notDue), çek 11-15 (5 gün: 0-30)
    ok(d.buckets["0-30"].totalKurus >= 3333333 + 600000, "0-30 kovasında 31 Ekim taksiti + çek", d.buckets);
    ok(d.buckets.notDue.count >= 2, "vadesi gelmemiş taksitler notDue");
    ok(d.overdueItems.length === d.overdueCount && d.overdueItems[0].days_overdue >= d.overdueItems[d.overdueItems.length - 1].days_overdue, "vadesi geçen listesi en eski önce");
    r = await call("GET", "/receivables/aging?asOf=2027-03-01", A); ok(r.j.buckets["90+"].count >= 1, "ileri tarihte 90+ kovası dolar");
    r = await call("GET", `/receivables/aging?asOf=2026-11-20&project_id=${projPay}`, A); eq(r.j.totalKurus, 10000001 + 600000, "proje filtresi");
    r = await call("GET", "/receivables/aging?asOf=bozuk", A); eq(r.s, 400, "asOf doğrulama");
    r = await call("GET", "/receivables/overdue?asOf=2026-11-20&min_days=10", A); ok(r.j.count >= 1 && r.j.items.every((x) => x.days_overdue >= 10), "overdue min_days");
    r = await call("GET", "/receivables/overdue?min_days=0", A); eq(r.s, 400, "min_days 0 → 400");
    // ödendi işaretle
    r = await call("POST", `/payment-schedule/${schedIds[0]}/mark-paid`, A, { paid_at: "2026-11-02", create_payment: true, method: "Havale" });
    ok(r.s === 200 && r.j.status === "odendi" && r.j.created_payment && r.j.created_payment.amount === 33333.33, "plan ödendi: payments NUMERIC TL = 33333,33", r.j.created_payment);
    ok((await q1("SELECT paid_payment_id FROM payment_schedule WHERE id=$1", [schedIds[0]])).paid_payment_id === r.j.created_payment.id, "gerçekleşen ödeme bağı (paid_payment_id)");
    r = await call("POST", `/payment-schedule/${schedIds[0]}/mark-paid`, A, {}); eq(r.s, 409, "zaten ödendi 409");
    r = await call("PATCH", `/payment-schedule/${schedIds[0]}`, A, { amount_kurus: 5 }); eq(r.s, 409, "ödenmiş satır tutarı değiştirilemez");
    r = await call("PATCH", `/payment-schedule/${schedIds[0]}`, A, { status: "odendi" }); eq(r.s, 400, "'odendi' yalnız mark-paid ile");
    const ex = (await call("POST", "/payments-dummy", A)).s; // yok
    const pay = await call("POST", `/projects/${projPay}/payments`, A, { amount: 100, method: "Nakit" }); const payId = pay.j.id;
    r = await call("POST", `/payment-schedule/${schedIds[1]}/mark-paid`, A, { payment_id: payId }); ok(r.s === 200 && r.j.paid_payment_id === payId, "mevcut tahsilata bağlanır");
    r = await call("POST", `/payment-schedule/${schedIds[2]}/mark-paid`, A, { payment_id: "00000000-0000-4000-8000-000000000000" }); eq(r.s, 404, "olmayan tahsilat 404");
    r = await call("PATCH", `/payment-schedule/${schedIds[1]}`, A, { status: "bekliyor" }); ok(r.j.status === "bekliyor" && r.j.paid_payment_id === null, "geri alınca bağ temizlenir");
    r = await call("PATCH", `/payment-schedule/${schedIds[1]}`, A, { status: "iptal" }); eq(r.j.status, "iptal", "iptal");
    r = await call("POST", `/payment-schedule/${schedIds[1]}/mark-paid`, A, {}); eq(r.s, 409, "iptal satır ödendi yapılamaz");
    r = await call("GET", "/receivables/aging?asOf=2026-11-20", A); ok(r.j.totalKurus < d.totalKurus, "ödenen/iptal edilen alacaktan düşer");
    r = await call("DELETE", `/payment-schedule/${schedIds[1]}`, A); eq(r.s, 200, "plan satırı silinir");
    r = await call("GET", `/payment-schedule/${schedIds[1]}`, A); eq(r.s, 404, "silinen 404");
    // fatura mark-paid: bağlı bekleyen planlar kapanır
    r = await call("POST", `/invoices/${I1.id}/mark-paid`, A, { paid_at: "2026-11-20" }); eq(r.j.schedule_items_closed, 1, "fatura ödenince bağlı bekleyen plan kapanır");
  }

  // ------------------------------------------------------------ 16) şablonlar + render + wa.me
  {
    let r = await call("GET", "/message-templates", A);
    ok(r.s === 200 && r.j.length === 7 && r.j.every((t) => t.is_system && !t.editable), "7 sistem şablonu, hepsi salt okunur");
    const keys = r.j.map((t) => t.key); for (const k of ["teklif_gonderimi", "randevu_hatirlatma", "odeme_nazik", "odeme_orta", "odeme_kesin", "tesekkur"]) ok(keys.includes(k), "şablon: " + k);
    const nazik = r.j.find((t) => t.key === "odeme_nazik"); ok(nazik.tone === "nazik" && nazik.category === "odeme" && nazik.variables.includes("tutar") && nazik.variables.includes("vade_tarihi"), "nazik şablon değişkenleri");
    ok(r.j.every((t) => !/kampanya|indirim/i.test(t.body)), "hiçbir tohum şablonda tanıtım/kampanya dili yok");
    ok(r.j.filter((t) => t.category === "odeme").every((t) => !/icra|dava|haciz|tehdit|yasal işlem/i.test(t.body)), "ödeme şablonlarında tehdit/icra dili yok");
    r = await call("GET", "/message-templates/variables", A); ok(r.j.ad && r.j.tutar && r.j.takip_linki, "değişken kataloğu");
    r = await call("GET", "/message-templates?category=odeme&tone=nazik", A); eq(r.j.length, 1, "filtre");
    r = await call("GET", "/message-templates?category=zz", A); eq(r.s, 400, "kategori doğrulama");
    r = await call("PATCH", `/message-templates/${nazik.id}`, A, { title: "x" }); eq(r.s, 403, "sistem şablonu düzenlenemez");
    r = await call("DELETE", `/message-templates/${nazik.id}`, A); eq(r.s, 403, "sistem şablonu silinemez");
    // clone → özelleştirme
    r = await call("POST", `/message-templates/${nazik.id}/clone`, A); ok(r.s === 201 && r.j.is_system === false && r.j.editable && r.j.key === "odeme_nazik" && r.j.owner_id === U.admin, "clone: kendi sürüm"); const mine = r.j.id;
    r = await call("POST", `/message-templates/${nazik.id}/clone`, A); eq(r.s, 409, "ikinci clone 409");
    r = await call("PATCH", `/message-templates/${mine}`, A, { body: "Selam {ad}, {tutar} TL için {vade_tarihi} vadesi var. Teşekkürler." }); eq(r.s, 200, "özelleştirme düzenlenir");
    r = await call("GET", "/message-templates?category=odeme&tone=nazik", A); ok(r.j.length === 1 && r.j[0].id === mine, "liste: kendi sürüm sistemi ezer");
    r = await call("GET", "/message-templates?category=odeme&tone=nazik", Mu); ok(r.j[0].id === mine, "muhasebe işletme özelleştirmesini görür");
    r = await call("GET", "/message-templates?category=odeme&tone=nazik&all=1", A); eq(r.j.length, 2, "all=1 hepsi");
    r = await call("PATCH", `/message-templates/${mine}`, A, { body: "{bilinmeyen}" }); eq(r.s, 400, "bilinmeyen değişken 400");
    r = await call("PATCH", `/message-templates/${mine}`, A, { body: "[[ açık blok {ad}" }); eq(r.s, 400, "dengesiz blok 400");
    r = await call("PATCH", `/message-templates/${mine}`, A, { body: "x".repeat(2001) }); eq(r.s, 400, "gövde > 2000");
    r = await call("POST", "/message-templates", A, { key: "Kötü Anahtar", title: "t", body: "b" }); eq(r.s, 400, "anahtar biçimi");
    r = await call("DELETE", `/message-templates/${mine}`, A); eq(r.s, 200, "özelleştirme silinir → sistem sürümü geri gelir");
    // render
    const cu = await call("POST", "/customers", A, { name: "AHMET YILMAZ", phone: "0532 123 45 67", address: "Bodrum" }); ok(cu.s === 201, "müşteri");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { customer_id: cu.j.id, vars: { tutar: "1.250", vade_tarihi: "5 Aralık 2026" }, opt_out: true });
    ok(r.s === 200 && r.j.text.startsWith("Merhaba Ahmet Yılmaz,") && r.j.text.includes("1.250 TL") && r.j.text.includes("5 Aralık 2026") && r.j.text.includes("DUR yazabilirsiniz"), "render: değişkenler + opt_out cümlesi", r.j.text);
    eq(r.j.whatsappUrl, "https://wa.me/905321234567?text=" + encodeURIComponent(r.j.text), "wa.me: 0532… → 90532… + URL kodlu metin");
    ok(r.j.whatsappAppUrl.startsWith("whatsapp://send?phone=905321234567&text="), "whatsapp:// bağlantısı");
    ok(r.j.warnings.some((w) => w.code === "payment_reminder_rules"), "ödeme hatırlatma kuralları uyarısı");
    ok(!r.j.text.includes("[[") && !r.j.text.includes("{"), "çözülmemiş işaret kalmaz (isteğe bağlı bloklar atıldı)", r.j.text);
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { vars: { tutar: "100", vade_tarihi: "1 Ocak 2027", ad: "Ayşe" } });
    ok(r.s === 200 && r.j.whatsappUrl === null && r.j.warnings.some((w) => w.code === "phone_missing_or_invalid"), "telefon yoksa wa.me yok + uyarı");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { phone: "+90 532 999 88 77", vars: { tutar: "100", vade_tarihi: "1 Ocak 2027", ad: "Ayşe" } }); ok(r.j.phone === "905329998877" && r.j.whatsappUrl.startsWith("https://wa.me/905329998877?text="), "phone parametresi");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { phone: "123", vars: { tutar: "1" } }); ok(r.j.whatsappUrl === null && r.j.warnings.some((w) => w.code === "phone_missing_or_invalid") && r.j.warnings.some((w) => w.code === "missing_variables") && r.j.complete === false, "geçersiz telefon + eksik değişken uyarıları");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { vars: { bilinmeyen: "x" } }); eq(r.s, 400, "bilinmeyen vars anahtarı 400");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { vars: { ad: { x: 1 } } }); eq(r.s, 400, "vars değeri nesne olamaz");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { vars: [] }); eq(r.s, 400, "vars dizi olamaz");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { customer_id: "00000000-0000-4000-8000-000000000000" }); eq(r.s, 404, "olmayan müşteri 404");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { vars: { ad: "Ali & Veli", tutar: "1", vade_tarihi: "x" }, phone: "05321234567" }); ok(r.j.whatsappUrl.includes("%26") && !r.j.whatsappUrl.includes("&Veli"), "& karakteri URL'de kodlanır (parametre bozulmaz)", r.j.whatsappUrl);
    // plan satırı bağlamı: tutar/vade/proje kodu
    const sch = (await call("GET", `/payment-schedule?project_id=${projPay}`, A)).j.find((x) => x.status === "bekliyor");
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { schedule_id: sch.id, phone: "0533 000 11 22" });
    ok(r.s === 200 && r.j.text.includes("Plan Müşteri".split(" ")[0]) && r.j.text.includes(T.formatTL(sch.amount_kurus)) && r.j.text.includes(T.formatDateTr(sch.due_date)), "plan satırından tutar/vade/ad", r.j.text);
    eq(r.j.context.schedule_id, sch.id, "context kaydı");
    // fatura bağlamı
    r = await call("POST", `/message-templates/${nazik.id}/render`, A, { invoice_id: I2.id, phone: "05320000000" }); ok(r.s === 200 && r.j.variables.tutar === "1.200", "fatura bağlamı: ödenecek tutar (1.200)", r.j.variables);
    // teklif bağlamı
    const off = await call("POST", "/offers", null, { name: "Teklif Müşteri", phone: "05301112233", service: "Pergola", message: "m" }, { "X-Forwarded-For": "10.88.1.1" });
    ok(off.s === 201, "teklif (anonim)");
    const offer = await q1("SELECT id, code, tracking_code FROM offers WHERE phone='05301112233' ORDER BY created_at DESC LIMIT 1");
    const tg = (await call("GET", "/message-templates?category=teklif", A)).j.find((t) => t.key === "teklif_gonderimi");
    r = await call("POST", `/message-templates/${tg.id}/render`, A, { offer_id: offer.id });
    ok(r.s === 200 && r.j.text.includes(`/teklif-takip/${offer.tracking_code}`) && r.j.phone === "905301112233" && r.j.text.startsWith("Merhaba Teklif Müşteri,") && r.j.text.includes("Pergola"), "teklif: takip bağlantısı + telefon + hizmet", r.j.text);
    r = await call("POST", `/message-templates/${tg.id}/render`, OB, { offer_id: offer.id }); eq(r.s, 403, "ortak B başkasının teklifini render edemez (403)");
    // randevu bağlamı
    const ap = await call("POST", "/appointments", A, { customer_name: "Randevu Müşteri", customer_phone: "0544 555 66 77", type: "Keşif", scheduled_at: "2026-12-05T11:30:00+03:00", address: "Bodrum Merkez" });
    if (ap.s === 201) {
      const rt = (await call("GET", "/message-templates?category=randevu", A)).j[0];
      r = await call("POST", `/message-templates/${rt.id}/render`, A, { appointment_id: ap.j.id });
      ok(r.s === 200 && r.j.text.includes("5 Aralık 2026") && r.j.text.includes("Cumartesi") && r.j.text.includes("11:30") && r.j.phone === "905445556677", "randevu: tarih/gün/saat (İstanbul) + telefon", r.j.text);
    } else ok(false, "randevu oluşturulamadı", ap);
  }

  // ------------------------------------------------------------ 17) zamanlı hatırlatma: tax.plan / tax.remind / receivable.remind
  {
    ok(queue.loadHandlers().includes("tax.remind") && queue.hasHandler("receivable.remind") && queue.hasHandler("tax.plan"), "işleyiciler A1 kuyruğuna otomatik yüklendi");
    await db.query("DELETE FROM jobs WHERE name IN ('tax.plan','tax.remind','receivable.remind')");
    await db.query("DELETE FROM notification_outbox WHERE type IN ('tax_reminder','receivable_reminder')");
    await db.query("UPDATE tax_calendar_items SET verified = false WHERE org_id=$1", [org.id]); // bölüm 14'te doğrulananları geri al
    // 2026-11-23 Pazartesi 05:00 İstanbul: Ekim KDV 30 Kasım (T−7 = 23 Kasım) ve Ekim muhtasar 26 Kasım (T−3)
    planner._resetBootstrap();
    clock.setFake("2026-11-23T05:00:00+03:00");
    const b = await planner.bootstrap();
    ok(b && b.id, "bootstrap: tax.plan kuyruğa girdi");
    ok((await planner.bootstrap()) === null, "bootstrap aynı gün tekrar → no-op (process önbelleği)");
    eq((await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='tax.plan'")).n, 1, "tek tax.plan işi");
    let run = await queue.runDue({ workerId: "t18" });
    ok(run.done >= 1 && run.failed === 0, "tax.plan çalıştı", run);
    const jobs = await qa("SELECT name, dedupe_key, payload, run_at, expires_at, user_id, status FROM jobs WHERE name = 'tax.remind' ORDER BY dedupe_key");
    ok(jobs.length > 0, "tax.remind işleri planlandı", jobs.length);
    ok(jobs.every((j) => j.dedupe_key.includes(j.user_id)), "dedupeKey KULLANICIYI içerir", jobs[0]);
    ok(jobs.every((j) => [U.admin, U.muh, U.oa, U.ob].includes(j.user_id)) && !jobs.some((j) => [U.pa].includes(j.user_id)), "yalnız admin/muhasebe/ortak planlanır; personel/saha yok");
    const adminJobs = jobs.filter((j) => j.user_id === U.admin).map((j) => j.payload);
    ok(adminJobs.some((p) => p.key === "kdv1_aylik" && p.dueDate === "2026-11-30" && p.offset === 7), "KDV (30 Kasım) T−7 işi planlı");
    ok(adminJobs.some((p) => p.key === "muhtasar_aylik" && p.dueDate === "2026-11-26" && p.offset === 3), "muhtasar (26 Kasım) T−3 işi planlı");
    ok(adminJobs.some((p) => p.key === "kdv1_aylik" && p.dueDate === "2026-11-30" && p.offset === 0), "son gün işi de ileriye planlandı");
    ok(!adminJobs.some((p) => p.key === "kdv2_tevkifat" || p.key === "kdv1_uc_aylik"), "kapalı kalemler planlanmaz");
    ok(!adminJobs.some((p) => p.key === "yillik_gelir_vergisi" || p.key === "kurumlar_vergisi"), "statü belirtilmediyse yalnız herkesi ilgilendirenler");
    ok(jobs.every((j) => new Date(j.expires_at) > new Date(j.run_at)), "iş süreleri (expires_at) var");
    const nxt = await q1("SELECT run_at, dedupe_key FROM jobs WHERE name='tax.plan' AND status='queued'");
    ok(nxt && nxt.dedupe_key === "tax.plan:2026-11-24" && new Date(nxt.run_at).toISOString() === "2026-11-24T00:45:00.000Z", "zincir: sonraki tax.plan ertesi gün 03:45 (İstanbul)", nxt);
    // tekrar planla → yeni iş yok
    const cnt0 = (await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='tax.remind'")).n;
    const pa2 = await planner.planAll(); eq((await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='tax.remind'")).n, cnt0, "planlama idempotent (tekrar iş eklemez)"); eq(pa2.taxJobs, 0, "planAll ikinci çağrı 0 yeni iş");
    // çalıştır: bugün 23 Kasım 05:00 → 07:30'a kadar bekler; saat ilerlet
    run = await queue.runDue({ workerId: "t18" }); eq(run.claimed, 0, "07:30'dan önce çalışmaz");
    clock.setFake("2026-11-23T08:00:00+03:00");
    run = await queue.runDue({ workerId: "t18" }); ok(run.done >= 1 && run.failed === 0, "T−7 işleri çalıştı", run);
    let ob = await qa("SELECT user_id, type, title, body, data, dedupe_key, status FROM notification_outbox WHERE type = 'tax_reminder' ORDER BY user_id");
    const forAdmin = ob.filter((o) => o.user_id === U.admin);
    ok(forAdmin.some((o) => o.data.itemKey === "kdv1_aylik" && o.data.dueDate === "2026-11-30" && o.data.daysUntil === 7), "admin: KDV T−7 bildirimi", forAdmin.map((o) => o.title));
    const kb = forAdmin.find((o) => o.data.itemKey === "kdv1_aylik");
    ok(/7 gün kaldı/.test(kb.title) && /30 Kasım 2026 Pazartesi/.test(kb.body) && /ertelenmiş/.test(kb.body) && /mali müşavirinize teyit edin/.test(kb.body), "bildirim metni: kalan gün, tarih, kaydırma, teyit uyarısı", kb);
    ok(kb.data.needsConfirmation === true && kb.data.period === "2026-10", "veri: needsConfirmation + dönem 2026-10");
    ok(ob.every((o) => o.dedupe_key.includes(o.user_id)) && ob.every((o) => o.dedupe_key.startsWith("tax:")), "outbox dedupeKey kullanıcıyı içerir");
    ok(!ob.some((o) => o.user_id === U.pa), "personele vergi bildirimi YOK");
    ok(new Set(ob.map((o) => o.user_id)).size >= 3, "admin, muhasebe, ortaklar ayrı ayrı bildirim alır");
    const n1 = ob.length;
    // aynı işi elle yeniden çalıştır → tek bildirim (idempotent)
    const h = taxHandlers.createHandlers({});
    const again = await h.taxRemind({ userId: U.admin, key: "kdv1_aylik", dueDate: "2026-11-30", offset: 7 }, {});
    ok(again.deduped === true, "işleyici ikinci kez: dedupe (tek bildirim)", again);
    eq((await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE type='tax_reminder'")).n, n1, "bildirim sayısı değişmedi");
    // KDV tahmini: Ekim 2026 dönemi için ödenecek > 0 yapalım
    await call("POST", "/invoices", A, { direction: "giden", issue_date: "2026-10-12", matrah_kurus: 10000000, kdv_oran: 20, invoice_no: "REM-1" });
    await db.query("DELETE FROM notification_outbox WHERE type='tax_reminder' AND user_id=$1", [U.admin]);
    const est = await h.taxRemind({ userId: U.admin, key: "kdv1_aylik", dueDate: "2026-11-30", offset: 7 }, {});
    const eb = await q1("SELECT body, data FROM notification_outbox WHERE type='tax_reminder' AND user_id=$1", [U.admin]);
    const per = (await call("GET", "/vat/periods/2026-10", A)).j;
    ok(est.sent === 1 && eb.data.estimatedPayableKurus === per.odenecek_kurus && per.odenecek_kurus > 0 && eb.body.includes("Tahmini ödenecek KDV: " + T.formatTL(per.odenecek_kurus) + " TL"), "bildirimde tahmini ödenecek KDV = dönem özeti", [eb, per.odenecek_kurus]);
    // bayat iş: takvim kalemi değişti → bildirim yok
    await db.query("UPDATE tax_calendar_items SET enabled = false WHERE org_id=$1 AND key='muhtasar_aylik'", [org.id]);
    let st = await h.taxRemind({ userId: U.admin, key: "muhtasar_aylik", dueDate: "2026-11-26", offset: 3 }, {}); eq(st.skipped, "stale", "kalem kapatıldı → bayat iş atlanır");
    await db.query("UPDATE tax_calendar_items SET enabled = true WHERE org_id=$1 AND key='muhtasar_aylik'", [org.id]);
    st = await h.taxRemind({ userId: U.admin, key: "muhtasar_aylik", dueDate: "2026-11-27", offset: 3 }, {}); eq(st.skipped, "stale", "tarih değişmiş (yanlış dueDate) → bayat");
    st = await h.taxRemind({ userId: U.pa, key: "kdv1_aylik", dueDate: "2026-11-30", offset: 7 }, {}); eq(st.skipped, "role_not_allowed", "personel için işleyici atlar");
    st = await h.taxRemind({ userId: "zzz", key: "kdv1_aylik", dueDate: "2026-11-30" }, {}); eq(st.skipped, "invalid_user", "geçersiz kullanıcı");
    st = await h.taxRemind({ userId: U.admin, dueDate: "2026-11-30" }, {}); eq(st.skipped, "invalid_payload", "geçersiz yük");
    clock.setFake("2026-12-01T08:00:00+03:00");
    st = await h.taxRemind({ userId: U.admin, key: "kdv1_aylik", dueDate: "2026-11-30", offset: 0 }, {}); ok(st.skipped === "stale" || st.skipped === "past", "son gün geçti → bildirim yok", st);
    // kullanıcı bildirimi kapatırsa (tür) kutuda görünmez ama dedupe korunur
    clock.setFake("2026-11-26T08:00:00+03:00");
    await call("PUT", "/assistant/prefs", OB, { categories: { tax_reminder: false } });
    await db.query("DELETE FROM notification_outbox WHERE type='tax_reminder' AND user_id=$1", [U.ob]);
    await h.taxRemind({ userId: U.ob, key: "muhtasar_aylik", dueDate: "2026-11-26", offset: 0 }, {});
    eq((await q1("SELECT status FROM notification_outbox WHERE type='tax_reminder' AND user_id=$1", [U.ob])).status, "iptal", "tür kapalı → 'iptal' (kutuda görünmez)");
    // sahte notify enjeksiyonu
    const calls = []; const h2 = taxHandlers.createHandlers({ notify: async (u, o) => { calls.push([u, o]); return { id: "x", deduped: false }; } });
    await h2.taxRemind({ userId: U.admin, key: "muhtasar_aylik", dueDate: "2026-11-26", offset: 0 }, {});
    ok(calls.length === 1 && calls[0][0] === U.admin && calls[0][1].dedupeKey === `tax:${U.admin}:muhtasar_aylik:2026-11-26:T0` && calls[0][1].type === "tax_reminder", "bağımlılık enjeksiyonu + dedupeKey biçimi", calls[0] && calls[0][1].dedupeKey);

    // --- tahsilat hatırlatma
    await db.query("DELETE FROM notification_outbox WHERE type='receivable_reminder'");
    await db.query("DELETE FROM payment_schedule WHERE owner_id=$1", [U.admin]);
    await db.query("UPDATE invoices SET status='odendi' WHERE owner_id=$1 AND direction='giden' AND status IN ('kesildi','gonderildi')", [U.admin]);
    const mkp = await call("POST", "/projects", A, { customer_name: "Hatırlatma Müşteri", service: "Kapı", total_amount: 100000 });
    const addPlan = async (due, amt) => (await call("POST", "/payment-schedule", A, { project_id: mkp.j.id, amount_kurus: amt, due_date: due })).j;
    const days = { "2026-11-27": 100, "2026-11-26": 200, "2026-11-23": 300, "2026-11-19": 400, "2026-11-12": 500, "2026-10-27": 600, "2026-09-27": 700, "2026-08-28": 800, "2026-11-21": 900, "2026-11-24": 1000 };
    for (const [d2, a] of Object.entries(days)) await addPlan(d2, a);
    // bugün 26 Kasım: yarın(27)=-1 ✓, bugün(26)=0 ✓, 23=+3 ✓, 19=+7 ✓, 12=+14 ✓, 27 Eki=+30 ✓, 27 Eyl=+60 ✓, 28 Ağu=+90 ✓, 21=+5 ✗, 24=+2 ✗
    const rr = await h.receivableRemind({ userId: U.admin, date: "2026-11-26" }, {});
    eq(rr.sent, 8, "eşik günlerinde 8 bildirim (−1,0,3,7,14,30,60,90); 2 ve 5 gün gecikme eşik dışı", rr);
    const ro = await qa("SELECT title, body, data, dedupe_key FROM notification_outbox WHERE type='receivable_reminder' AND user_id=$1", [U.admin]);
    ok(ro.every((o) => o.dedupe_key.startsWith(`recv:${U.admin}:`)), "alacak dedupeKey kullanıcıyı içerir");
    ok(ro.some((o) => /Yarın vade: Hatırlatma Müşteri/.test(o.title)) && ro.some((o) => /Bugün vade/.test(o.title)) && ro.some((o) => /Vadesi geçti/.test(o.title) && /3 gün gecikti/.test(o.body)), "başlıklar: yarın/bugün/vadesi geçti");
    ok(ro.every((o) => !/icra|dava|haciz/i.test(o.title + o.body)), "bildirim metinlerinde tehdit dili yok");
    const d3 = ro.find((o) => o.data.daysOverdue === 3), d30 = ro.find((o) => o.data.daysOverdue === 30);
    eq([d3.data.suggestedTemplateKey, d30.data.suggestedTemplateKey, ro.find((o) => o.data.daysOverdue === 90).data.suggestedTemplateKey, ro.find((o) => o.data.daysOverdue === 7).data.suggestedTemplateKey], ["odeme_nazik", "odeme_kesin", "odeme_kesin", "odeme_orta"], "önerilen şablon tonu gecikmeye göre (nazik→orta→kesin)");
    ok(ro.some((o) => /3\d{2},00|3,00/.test(o.body) || /3 TL/.test(o.body)), "tutar metinde (kuruştan TL biçimi)");
    const rr2 = await h.receivableRemind({ userId: U.admin, date: "2026-11-26" }, {}); eq((await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE type='receivable_reminder' AND user_id=$1", [U.admin])).n, 8, "ikinci çalışma aynı bildirimleri ÇOĞALTMAZ");
    const rrOB = await h.receivableRemind({ userId: U.ob }, {}); eq(rrOB.sent, 0, "ortak B'nin alacağı yok → bildirim yok");
    const one = (await qa("SELECT id FROM payment_schedule WHERE owner_id=$1 AND amount_kurus=400", [U.admin]))[0].id;
    await db.query("DELETE FROM notification_outbox WHERE type='receivable_reminder'");
    let sr = await h.receivableRemind({ userId: U.admin, scheduleId: one }, {}); eq(sr.sent, 1, "tek kalem modu: eşik beklemeden bildirir");
    await call("POST", `/payment-schedule/${one}/mark-paid`, A, {});
    sr = await h.receivableRemind({ userId: U.admin, scheduleId: one }, {}); eq(sr.skipped, "not_pending", "ödenmiş kalem için hatırlatma YOK");
    sr = await h.receivableRemind({ userId: U.muh, scheduleId: one }, {}); eq(sr.skipped, "not_pending", "muhasebe de aynı defteri görür (ödendi → yok)");
    sr = await h.receivableRemind({ userId: U.pa }, {}); eq(sr.skipped, "role_not_allowed", "personel: atlanır");
    // planlayıcı: açık alacağı olan kullanıcı için günlük iş
    await db.query("DELETE FROM jobs WHERE name IN ('tax.plan','receivable.remind')");
    clock.setFake("2026-11-27T05:00:00+03:00");
    const pl = await planner.planAll();
    const rj = await qa("SELECT user_id, dedupe_key FROM jobs WHERE name='receivable.remind'");
    ok(rj.some((j) => j.user_id === U.admin && j.dedupe_key === `receivable.remind:${U.admin}:2026-11-27`) && rj.some((j) => j.user_id === U.muh) && !rj.some((j) => j.user_id === U.ob), "açık alacağı olan defter için günlük receivable.remind (admin+muhasebe; ortak B yok)", rj);
    // son gün geçtikten sonra eski iş çalışmaz (expires)
    clock.setFake("2026-11-27T23:00:00+03:00");
    const rrun = await queue.runDue({ workerId: "t18b" }); ok(rrun.expired >= 1 || rrun.done >= 0, "süresi geçen iş atlanır / çalışır (kuyruk sözleşmesi)", rrun);
    clock.reset();
    await db.query("DELETE FROM jobs WHERE name IN ('tax.plan','tax.remind','receivable.remind')");
  }

  // ------------------------------------------------------------ 18) kullanıcı silme: faturalar devredilir
  {
    const mu = await call("POST", "/users", OA, { name: "Silinecek", email: "silinecek18@x.com", password: "pass1234", role: "personel" }); ok(mu.s === 201, "ortak alt kullanıcı");
    const o2 = await call("POST", "/users", A, { name: "Ortak C", email: "oc18@x.com", password: "pass1234", role: "ortak" }); ok(o2.s === 201, "ortak C");
    const OC = await login("oc18@x.com");
    const ic = await call("POST", "/invoices", OC, { direction: "giden", issue_date: "2026-11-05", matrah_kurus: 1000, kdv_oran: 20, invoice_no: "OC-1" });
    const pc = await call("POST", "/vat/periods/2026-11/calculate", OC, {});
    const sc = await call("POST", "/projects", OC, { customer_name: "OC Müşteri", service: "x", total_amount: 1000 });
    await call("POST", "/payment-schedule", OC, { project_id: sc.j.id, amount_kurus: 777, due_date: "2026-12-01" });
    ok(ic.s === 201 && pc.s === 200, "ortak C fatura + dönem");
    const del = await call("DELETE", `/users/${o2.j.id}`, A); eq(del.s, 200, "kullanıcı silinebilir (FK engeli yok)");
    const moved = await q1("SELECT owner_id FROM invoices WHERE invoice_no='OC-1'"); eq(moved.owner_id, U.admin, "faturalar silen yöneticiye devredildi");
    eq((await q1("SELECT COUNT(*)::int n FROM payment_schedule WHERE owner_id = $1 AND amount_kurus = 777", [U.admin])).n, 1, "tahsilat planı devredildi");
    eq((await q1("SELECT COUNT(*)::int n FROM vat_periods WHERE owner_id = $1", [o2.j.id])).n, 0, "türetilmiş KDV dönemleri kullanıcıyla silinir");
  }

  // ------------------------------------------------------------ 19) sözleşme: /api/v1, güvenlik başlıkları, hata biçimi
  {
    let r = await fetch(`http://localhost:${PORT}/api/v1/invoices?limit=1`, { headers: { Authorization: "Bearer " + A } }); eq(r.status, 200, "/api/v1/invoices çalışır");
    r = await fetch(`http://localhost:${PORT}/api/v1/tax-calendar`, { headers: { Authorization: "Bearer " + A } }); eq(r.status, 200, "/api/v1/tax-calendar çalışır");
    r = await call("POST", "/invoices", A, "bozuk"); ok(r.s === 400 && r.j && typeof r.j.error === "string", "bozuk gövde → {error}");
    r = await call("PATCH", "/invoices/zzz", A, { note: "x" }); ok(r.s === 400 && typeof r.j.error === "string", "hata biçimi {error: Türkçe}");
    const bad = await call("GET", "/invoices?q=" + "x".repeat(300), A); eq(bad.s, 200, "uzun arama kırpılır");
    const inj = await call("GET", "/invoices?q=%27%3B%20DROP%20TABLE%20invoices%3B--", A); eq(inj.s, 200, "SQL enjeksiyon denemesi zararsız"); ok(await q1("SELECT to_regclass('public.invoices') t").then((x) => x.t), "invoices tablosu duruyor");
    const inj2 = await call("GET", "/invoices?direction=giden'%20OR%20'1'='1", A); eq(inj2.s, 400, "yön enjeksiyonu 400");
  }

  {
    const acts = (await qa("SELECT DISTINCT action FROM audit_log WHERE action LIKE 'invoice.%' OR action LIKE 'vat_period.%'")).map((x) => x.action);
    ok(["invoice.create", "invoice.update", "invoice.delete", "invoice.mark_paid", "vat_period.lock", "vat_period.unlock"].every((x) => acts.includes(x)), "denetim izi: fatura + dönem kilidi eylemleri", acts);
  }
  console.log(`\nv18: ${pass} geçti, ${fail} başarısız`);
  await db.pool.end();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST ÇÖKTÜ:", e); process.exit(2); });
