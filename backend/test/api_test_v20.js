// v20 testleri: Müdür (M1–M13) + Sekreter brifingi + akşam kapanış + hatırlatma uzantısı + insight uçları. DB + HTTP.
// Önkoşul: TEMİZ veritabanı + migrate + seed (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234); sunucu :4104'te,
//   ASSISTANT_FAKE_NOW=2026-11-25T07:00:00Z ile başlatılmış (sahte saat: Çarşamba 25 Kasım 2026 10:00 İstanbul); cwd = backend klasörü.
// Test sürecinin kendisi de aynı sahte saati kurar (kuyruk/işleyiciler süreç içinde çalıştırılır).
const crypto = require("crypto");
const db = require("../src/db");
const clock = require("../src/assistant/clock");
const queue = require("../src/assistant/queue");
const planner = require("../src/assistant/planner");
const a2planner = require("../src/assistant/reminders/planner");
const engine = require("../src/assistant/manager/engine");
const facts = require("../src/assistant/facts");
const deps = require("../src/assistant/facts/deps");
const morning = require("../src/assistant/briefing/morning");
const closureSvc = require("../src/assistant/closure/service");
const reminderSvc = require("../src/assistant/reminders/service");
const terms = require("../src/assistant/text/terms");
const tr = require("../src/assistant/text/tr");

const PORT = process.env.TEST_PORT || 4104;
const B = `http://localhost:${PORT}/api`;
const D = "2026-11-25";
const FAKE_NOW = process.env.ASSISTANT_FAKE_NOW || "2026-11-25T07:00:00Z";
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 700) : ""); } };
const eq = (a, b, m) => ok(JSON.stringify(a) === JSON.stringify(b), m, { got: a, want: b });
async function call(method, p, token, body, headers = {}) {
  const r = await fetch(B + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...headers }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j };
}
const login = async (e) => (await call("POST", "/auth/login", null, { email: e, password: "pass1234" })).j?.token;
const q1 = async (sql, p) => (await db.query(sql, p)).rows[0];
const qa = async (sql, p) => (await db.query(sql, p)).rows;
const uid = async (e) => (await q1("SELECT id FROM users WHERE email=$1", [e])).id;
const at = (date, hhmm = "12:00") => clock.zonedToUtc(date, hhmm);
const d = (n) => clock.addDays(D, n);
const setNow = (date, hhmm) => clock.setFake(at(date, hhmm));
const IDS = {};
async function sec(name, fn) { try { await fn(); } catch (e) { fail++; console.log(`FAIL: [${name}] istisna:`, e.stack ? e.stack.split("\n").slice(0, 4).join(" | ") : e); } }
const rk = (items, key) => items.filter((i) => i.rule_key === key);

(async () => {
  clock.setFake(FAKE_NOW);
  const A = await login("admin@x.com"), M = await login("muh@x.com"), OA = await login("oa@x.com"), OB = await login("ob@x.com"), PA = await login("pa@x.com");
  ok(A && M && OA && OB && PA, "girişler");
  const U = { admin: await uid("admin@x.com"), muh: await uid("muh@x.com"), oa: await uid("oa@x.com"), ob: await uid("ob@x.com"), pa: await uid("pa@x.com") };
  const orgId = (await q1("SELECT id FROM organizations WHERE is_default")).id;
  // saha kullanıcısı (seed'de yok): admin'in parola özetini kopyala
  const h = (await q1("SELECT password_hash FROM users WHERE id=$1", [U.admin])).password_hash;
  U.saha = (await q1("INSERT INTO users (name,email,password_hash,role,created_by) VALUES ('Saha Usta','saha@x.com',$1,'saha',$2) RETURNING id", [h, U.admin])).id;
  const SF = await login("saha@x.com");
  ok(SF, "saha girişi");
  await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");

  // ================= 1) Şema =================
  await sec("sema", async () => {
    for (const t of ["briefings", "insights", "insight_rule_config", "insight_runs", "daily_logs", "followups"]) {
      ok(!!(await q1("SELECT to_regclass($1) t", ["public." + t])).t, `tablo ${t}`);
      const c = await q1(`SELECT is_nullable FROM information_schema.columns WHERE table_name=$1 AND column_name='org_id'`, [t]);
      ok(!!c, `${t}.org_id var`);
    }
    for (const c of ["recurrence", "snoozed_until", "snooze_count", "done_at", "source", "source_key", "fired_at", "offer_id", "appointment_id"]) ok(!!(await q1(`SELECT 1 x FROM information_schema.columns WHERE table_name='reminders' AND column_name=$1`, [c])), `reminders.${c}`);
    for (const [t, c] of [["projects", "cost_confirmed_at"], ["projects", "stage_changed_at"], ["offers", "status_changed_at"]]) ok(!!(await q1(`SELECT 1 x FROM information_schema.columns WHERE table_name=$1 AND column_name=$2`, [t, c])), `${t}.${c}`);
    // varsayılan org tetikleyicisi
    const b = await q1("INSERT INTO briefings (user_id, kind, period_start, title, data) VALUES ($1,'morning','2020-01-01','x','{}') RETURNING org_id", [U.admin]);
    ok(b.org_id === orgId, "briefings varsayılan org");
    let dup = false; try { await db.query("INSERT INTO briefings (user_id, kind, period_start, title, data) VALUES ($1,'morning','2020-01-01','y','{}')", [U.admin]); } catch { dup = true; }
    ok(dup, "briefings (user,kind,period) tekil");
    await db.query("DELETE FROM briefings WHERE period_start='2020-01-01'");
    const f = await q1("INSERT INTO followups (user_id, title, due_date) VALUES ($1,'t','2020-01-01') RETURNING org_id, kind, status", [U.admin]);
    ok(f.org_id === orgId && f.kind === "diger" && f.status === "acik", "followups varsayılanlar");
    await db.query("DELETE FROM followups WHERE due_date='2020-01-01'");
    let bad = false; try { await db.query("INSERT INTO insights (scope_key, rule_key, severity, title, fingerprint, status) VALUES ('business','M1','x','t','f','acik')"); } catch { bad = true; }
    ok(bad, "insights severity CHECK");
    ok(!!(await q1("SELECT 1 x FROM information_schema.columns WHERE table_name='insights' AND column_name='org_id'")), "insights.org_id");
  });

  // ================= 2) Veri (sabit tarihler; hepsi açık zaman damgalı) =================
  // B paketi (schema_v18) kurulu mu? Kuruluysa M7/M8 GERÇEK tablolarla, değilse sentetik alt kümeyle sınanır
  const REAL = { inv: !!(await q1("SELECT to_regclass('public.invoices') t")).t, vat: !!(await q1("SELECT to_regclass('public.vat_periods') t")).t, hol: !!(await q1("SELECT to_regclass('public.holidays_tr') t")).t };
  console.log(`(bilgi) gerçek tablolar: invoices=${REAL.inv} vat_periods=${REAL.vat} holidays_tr=${REAL.hol}`);
  const offer = async (name, phone, status, owner, createdDate, extra = {}) => {
    IDS.seq = (IDS.seq || 0) + 1;
    const code = `T20-${IDS.seq}`;
    return (await q1(`INSERT INTO offers (code, tracking_code, name, phone, service, status, owner_id, created_at, updated_at, status_changed_at, source_site)
                      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$8,$8,$9) RETURNING id`, [code, code + "-t", name, phone, extra.service || "Mutfak", status, owner, at(createdDate, "09:00"), extra.source || null])).id;
  };
  const project = async (code, name, service, stage, total, owner, o) => (await q1(
    `INSERT INTO projects (code, offer_id, customer_name, service, stage, total_amount, owner_id, start_date, end_date, stage_changed_at, cost_confirmed_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`, [code, o.offer || null, name, service, stage, total, owner, at(o.start, "09:00"), o.end ? at(o.end, "09:00") : null, at(o.stageDate || o.start, "09:00"), o.cost ? at(o.cost, "09:00") : null])).id;
  const pay = (pid, amt, date, owner = U.admin) => db.query("INSERT INTO payments (project_id, amount, method, paid_at, owner_id) VALUES ($1,$2,'Nakit',$3,$4)", [pid, amt, at(date), owner]);
  const exp = (cat, amt, date, scope = "genel", pid = null) => db.query("INSERT INTO expenses (project_id, category, amount, expense_date, created_at, scope, owner_id) VALUES ($1,$2,$3,$4,$4,$5,$6)", [pid, cat, amt, at(date), scope, U.admin]);
  const appt = async (type, date, hhmm, o) => (await q1(`INSERT INTO appointments (offer_id, project_id, type, scheduled_at, assigned_user_id, status, owner_id, address, customer_name, customer_phone)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`, [o.offer || null, o.project || null, type, at(date, hhmm), o.assigned || null, o.status || "beklemede", o.owner, o.address === undefined ? "Atatürk Cd. 5" : o.address, o.name, o.phone || null])).id;

  await sec("veri", async () => {
    const oAhmet = await offer("Ahmet Kaya", "05321234567", "Kabul Edildi", U.admin, d(-35));
    const oVeli = await offer("Veli Demir", "05329998877", "Kabul Edildi", U.admin, d(-50));
    IDS.P1 = await project("PRJ-T1", "Ahmet Kaya", "Mutfak", "Teslim", 20000.55, U.admin, { offer: oAhmet, start: d(-30), stageDate: d(-10) });
    IDS.P2 = await project("PRJ-T2", "Veli Demir", "Mutfak", "Teslim", 4000, U.admin, { offer: oVeli, start: d(-45), stageDate: d(-30) });
    IDS.P3 = await project("PRJ-T3", "Su Yıldız", "Kapı", "Üretim", 5000, U.admin, { start: d(-20), end: d(-8) });
    IDS.P4 = [];
    for (let i = 4; i <= 6; i++) IDS.P4.push(await project(`PRJ-T${i}`, `Kapı Müşteri ${i}`, "Kapı", "Üretim", 10000, U.admin, { start: d(-100), cost: d(-50) }));
    IDS.P7 = await project("PRJ-T7", "Onaysız Maliyet", "Kapı", "Üretim", 10000, U.admin, { start: d(-100) });
    IDS.PA1 = await project("PRJ-TA1", "Ortak Müşteri", "Mutfak", "Teslim", 5000, U.oa, { start: d(-30), stageDate: d(-30) });
    await pay(IDS.P1, 3000.0, d(-3)); await pay(IDS.P1, 2550.0, d(-2)); await pay(IDS.P1, 2000.0, d(-1));
    await pay(IDS.P2, 4000, d(-40));
    for (const p of IDS.P4) await exp("Proje gideri", 8000, d(-100), "genel", p);
    await exp("Proje gideri", 9500, d(-100), "genel", IDS.P7);
    await exp("Malzeme", 15000.5, d(-2)); await exp("Market", 3000, d(-2), "ev");
    await exp("Malzeme", 10000, "2026-10-15"); await exp("Malzeme", 10000, "2026-09-15"); await exp("Malzeme", 10000, "2026-08-15");
    // teklifler
    IDS.O1 = await offer("Ayşe Demir", "05331112233", "Teklif Verildi", U.admin, d(-20));
    await db.query("INSERT INTO quotes (offer_id, items, subtotal, tax, total, created_at) VALUES ($1,'[]',3750.42,750.08,4500.50,$2)", [IDS.O1, at(d(-8), "11:00")]);
    IDS.O2 = await offer("Can Öz", "05334445566", "Yeni", null, d(-2));
    IDS.O3 = await offer("Eda Ak", "05337778899", "Keşif Planlandı", U.admin, d(-10));
    await appt("Keşif", d(-3), "10:00", { offer: IDS.O3, owner: U.admin, status: "tamamlandı", name: "Eda Ak", phone: "05337778899" });
    IDS.OA = await offer("Ortak Talep", "05330001122", "Yeni", U.oa, d(-3));
    // randevular
    IDS.AT = await appt("Montaj", D, "14:00", { project: IDS.P1, owner: U.admin, assigned: U.saha, name: "Ahmet Kaya", phone: "05321234567" });
    IDS.AO = await appt("Keşif", D, "16:00", { owner: U.oa, name: "Ortak Müşteri", phone: "05330002233" });
    IDS.AM = await appt("Montaj", d(1), "10:00", { owner: U.admin, assigned: U.saha, name: "Ahmet Kaya", phone: "05321234567", address: null });
    // stok
    await db.query("INSERT INTO materials (name, unit, stock_quantity, low_stock_threshold, owner_id) VALUES ('Silikon','adet',2,5,$1),('Vida','adet',100,10,$1)", [U.admin]);
    ok(true, "veri kuruldu");
  });

  // ================= 3) Facts =================
  await sec("facts", async () => {
    const admin = { id: U.admin, role: "admin", name: "Admin" };
    const ctx = await facts.context.userCtx(admin, { date: D });
    const pnl = await facts.pnl.monthPnl(ctx);
    eq(pnl.collected_kurus, 755000, "monthPnl tahsilat kuruş");
    eq(pnl.expense_kurus, 1500050, "monthPnl işletme gideri (ev hariç)");
    eq(pnl.home_expense_kurus, 300000, "monthPnl ev gideri ayrı");
    eq(pnl.net_kurus, -745050, "monthPnl net (ev hariç)");
    eq(pnl.net_incl_home_kurus, -1045050, "monthPnl net (ev dahil ayrı)");
    const rec = await facts.receivables.receivableAging(ctx);
    const p1 = rec.items.find((x) => x.project_id === IDS.P1);
    ok(p1 && p1.balance_kurus === 1245055 && p1.stage_age_days === 10 && p1.delivered, "alacak: P1 bakiye 12.450,55 / 10 gün", p1);
    ok(!rec.items.some((x) => x.project_id === IDS.PA1), "alacak: ortağın işi işletme defterinde yok");
    const rc = await facts.context.userCtx({ id: U.oa, role: "ortak" }, { date: D });
    const recA = await facts.receivables.receivableAging(rc);
    ok(recA.items.length === 1 && recA.items[0].project_id === IDS.PA1 && recA.items[0].balance_kurus === 500000, "alacak: ortak A yalnız kendi işini görür", recA.items.map((x) => x.project_id));
    const sc = await facts.context.userCtx({ id: U.saha, role: "saha" }, { date: D });
    const ag = await facts.agenda.dayAgenda(sc);
    eq(ag.appointments.map((x) => x.id), [IDS.AT], "gündem: saha yalnız kendine atanan randevuyu görür");
    const ag2 = await facts.agenda.dayAgenda(ctx);
    ok(ag2.appointments.length === 2, "gündem: admin tüm randevuları görür", ag2.appointments.length);
    const agA = await facts.agenda.dayAgenda(rc);
    eq(agA.appointments.map((x) => x.id), [IDS.AO], "gündem: ortak A yalnız kendi randevusunu görür");
    const agB = await facts.agenda.dayAgenda(await facts.context.userCtx({ id: U.ob, role: "ortak" }, { date: D }));
    ok(agB.appointments.length === 0 && agB.new_requests.count === 0, "gündem: ortak B boş (A'nın verisi sızmaz)");
    const ls = await facts.lowstock.lowStock(ctx);
    ok(ls.count === 1 && ls.items[0].name === "Silikon", "düşük stok", ls);
    eq((await facts.lowstock.lowStock(sc)).count, 0, "düşük stok: saha görmez");
    const occ = await facts.occupancy.occupancy(ctx, { workdays: 7 });
    ok(occ.days.length === 7 && occ.empty_days === 6 && !occ.empty_dates.includes(d(1)), "doluluk: 7 iş günü, yarın dolu 6 boş", occ);
    const sf = await facts.funnel.statusCounts(ctx, "biz");
    ok(sf["Teklif Verildi"] === 1 && sf["Yeni"] === 1, "huni sayıları (işletme kapsamı; ortağın talebi hariç)", sf);
    const mp = await facts.pnl.monthPnl(ctx, "2026-10");
    eq(mp.expense_kurus, 1000000, "geçmiş ay gideri");
  });

  // ================= 4) Müdür kuralları: tetiklenen =================
  let biz;
  await sec("kurallar", async () => {
    const s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    for (const k of ["M1", "M2", "M2b", "M3", "M4", "M6", "M6b", "M6c", "M9", "M10", "M11"]) ok(s.rules[k] && s.rules[k].status === "ok" && s.rules[k].count >= 1, `${k} tetiklendi`, s.rules[k]);
    for (const k of ["M3b", "M5", "M12", "M13"]) ok(s.rules[k] && s.rules[k].status === "ok" && s.rules[k].count === 0, `${k} tetiklenmedi (veri/eşik)`, s.rules[k]);
    eq(s.rules.M7.status, REAL.inv ? "ok" : "bagimli", "M7 durumu tabloya göre (invoices " + (REAL.inv ? "var" : "yok") + ")"); eq(s.rules.M8.status, REAL.vat ? "ok" : "bagimli", "M8 durumu tabloya göre (vat_periods " + (REAL.vat ? "var" : "yok") + ")");
    if (!REAL.inv) ok((s.rules.M7.missing || []).includes("invoices") && (s.rules.M8.missing || []).includes("vat_periods"), "bağımlılık eksik tablo adları", { m7: s.rules.M7, m8: s.rules.M8 });
    biz = await engine.list({ id: U.admin, role: "admin" }, orgId, { status: "all", limit: 100, fresh: false });
    const by = (k) => rk(biz, k);
    const m = (i, key) => i.evidence.metrics.find((x) => x.key === key);
    ok(by("M1").length === 1 && by("M1")[0].severity === "critical" && m(by("M1")[0], "net").value === -745050 && m(by("M1")[0], "expense").value === 1500050, "M1 kritik, net -₺7.450,50 (kuruş)", by("M1")[0] && by("M1")[0].evidence.metrics);
    ok(by("M1")[0].body.includes("₺7.450,50") || by("M1")[0].evidence.metrics.some((x) => x.display === "-₺7.450,50"), "M1 metin/dayanak biçimli tutar", by("M1")[0].body);
    const m2 = by("M2")[0];
    ok(by("M2").length === 1 && m2.severity === "warn" && m(m2, "balance").value === 1245055 && m2.body.includes("₺12.450,55") && m2.entity.id === IDS.P1, "M2 uyarı: Ahmet Kaya ₺12.450,55, 10 gün", m2 && m2.body);
    ok(m2.actions.some((a) => a.type === "whatsapp.template" && a.template_code === "odeme_hatirlatma" && a.text.includes("₺12.450,55")), "M2 WhatsApp şablonu kodu + metni");
    ok(m2.actions.some((a) => a.type === "reminder.create") && m2.actions.some((a) => a.type === "call"), "M2 hatırlatma + ara aksiyonları");
    const mb = by("M2b")[0]; ok(mb && mb.severity === "critical" && m(mb, "rate").value === 3983, "M2b tahsilat oranı %39,8", mb && mb.evidence.metrics);
    const m3 = by("M3")[0]; ok(m3 && m3.severity === "warn" && m(m3, "margin").value === 2000 && m(m3, "n").value === 3, "M3 marj %20 (onaysız iş hesaba katılmadı)", m3 && m3.evidence.metrics);
    ok(by("M4")[0].severity === "critical" && m(by("M4")[0], "empty_days").value === 6, "M4 kritik 6 boş gün");
    ok(by("M6")[0].severity === "critical" && by("M6")[0].body.includes("₺4.500,50") && m(by("M6")[0], "age").value === 8, "M6 kritik 8 gün ₺4.500,50");
    ok(by("M6b")[0].severity === "critical" && m(by("M6b")[0], "hours").value === 49, "M6b cevapsız talep 49 saat");
    ok(by("M6c")[0].severity === "warn" && m(by("M6c")[0], "age").value === 3, "M6c keşif sonrası teklif yok 3 gün");
    const m9 = by("M9")[0]; ok(m9 && m9.severity === "warn" && m(m9, "avg3").value === 1000000 && m(m9, "current").value === 1500050 && m(m9, "jump").value === 5001, "M9 Malzeme +%50", m9 && m9.evidence.metrics);
    const m10 = by("M10")[0]; ok(m10 && m10.severity === "warn" && m(m10, "share").value === 6537, "M10 pay %65,4", m10 && m10.evidence.metrics);
    ok(by("M11")[0].severity === "critical" && m(by("M11")[0], "days").value === 8, "M11 geciken iş 8 gün");
    ok(biz.every((i) => i.evidence && i.evidence.metrics.length > 0 && i.evidence.metrics.every((x) => x.display !== undefined) && i.evidence.why), "her insight sayısal dayanak ('Neden?') taşır");
    ok(biz.every((i) => !/undefined|NaN|\[object/.test(i.title + i.body)), "metinlerde undefined/NaN yok");
    ok(!biz.some((i) => JSON.stringify(i.entity).includes(IDS.PA1)) && !biz.some((i) => i.body.includes("Ortak Müşteri")), "işletme insight'larında ortağın verisi yok");
    // sektör sözlüğü: terimler değişince metin değişir
    await db.query("UPDATE org_settings SET sector_dictionary = jsonb_set(COALESCE(sector_dictionary,'{}'::jsonb), '{terms}', '{\"job\":\"Proje\",\"offer\":\"Teklif\"}'::jsonb) WHERE org_id=$1", [orgId]);
    terms._resetCache();
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    const after = await engine.list({ id: U.admin, role: "admin" }, orgId, { status: "all", limit: 100, fresh: false });
    ok(rk(after, "M11")[0].body.toLowerCase().includes("proje") || rk(after, "M11")[0].title.toLowerCase().includes("proje"), "sektör sözlüğü: M11 metni 'proje' terimini kullanır", rk(after, "M11")[0].title);
    await db.query("UPDATE org_settings SET sector_dictionary = sector_dictionary #- '{terms,job}' #- '{terms,offer}' WHERE org_id=$1", [orgId]);
    terms._resetCache();
  });

  // ================= 5) Yaşam döngüsü: dedupe / ertele / kapat / geri bildirim =================
  await sec("yasam", async () => {
    const before = await q1("SELECT COUNT(*)::int n, SUM(occurrences)::int o FROM insights WHERE scope_key='business'");
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    const after = await q1("SELECT COUNT(*)::int n, SUM(occurrences)::int o FROM insights WHERE scope_key='business'");
    ok(after.n === before.n, "dedupe: yeniden hesaplama yinelenen insight üretmez", { before, after });
    // HTTP uçları
    let r = await call("GET", "/assistant/insights", A);
    ok(r.s === 200 && r.j.count === r.j.items.length && r.j.count >= 11, "GET insights (admin)", r.s);
    ok(r.j.items[0].severity === "critical", "insights önem sırasıyla (kritik önce)");
    ok(r.j.items.every((i) => i.status === "acik"), "varsayılan status=acik");
    r = await call("GET", "/assistant/insights?status=ertelendi", A); eq(r.j.items.length, 0, "ertelenen yok");
    r = await call("GET", "/assistant/insights?status=bogus", A); eq(r.s, 400, "geçersiz status 400");
    r = await call("GET", "/assistant/insights?severity=bogus", A); eq(r.s, 400, "geçersiz severity 400");
    eq((await call("GET", "/assistant/insights", M)).j.count, (await call("GET", "/assistant/insights", A)).j.count, "muhasebe = admin (işletme kapsamı)");
    eq((await call("GET", "/assistant/insights", PA)).s, 403, "personel insight göremez");
    eq((await call("GET", "/assistant/insights", SF)).s, 403, "saha insight göremez");
    eq((await call("GET", "/assistant/insights", null)).s, 401, "oturumsuz 401");
    const m6 = (await call("GET", "/assistant/insights", A)).j.items.find((i) => i.rule_key === "M6");
    r = await call("GET", `/assistant/insights/${m6.id}`, A); ok(r.s === 200 && r.j.id === m6.id, "GET insight/:id");
    eq((await call("GET", "/assistant/insights/xyz", A)).s, 400, "geçersiz uuid 400");
    eq((await call("GET", `/assistant/insights/${crypto.randomUUID()}`, A)).s, 404, "olmayan insight 404");
    eq((await call("GET", `/assistant/insights/${m6.id}`, OA)).s, 404, "ortak, işletme insight'ını göremez (404)");
    // ertele
    for (const body of [{}, { days: 0 }, { days: 91 }, { days: "a" }, { days: 1.5 }, { until: "2000-01-01" }, { until: "yarın" }]) eq((await call("POST", `/assistant/insights/${m6.id}/snooze`, A, body)).s, 400, "snooze geçersiz " + JSON.stringify(body));
    r = await call("POST", `/assistant/insights/${m6.id}/snooze`, A, { days: 3 });
    ok(r.s === 200 && r.j.status === "ertelendi" && r.j.snoozed_until === new Date(clock.now().getTime() + 3 * 86400000).toISOString(), "snooze 3 gün", r.j);
    ok(!(await call("GET", "/assistant/insights", A)).j.items.some((i) => i.id === m6.id), "ertelenen açık listede yok");
    ok((await call("GET", "/assistant/insights?status=ertelendi", A)).j.items.some((i) => i.id === m6.id), "ertelenen status=ertelendi'de");
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    eq((await q1("SELECT status FROM insights WHERE id=$1", [m6.id])).status, "ertelendi", "koşul sürerken yeniden hesap ertelemeyi bozmaz");
    // süre dolunca geri gelir (sahte saat ileri)
    const later = new Date(clock.now().getTime() + 3 * 86400000 + 60000);
    await engine.refresh(orgId, "business", { now: later, date: clock.istanbulDateStr(later) });
    const re = await q1("SELECT status, occurrences FROM insights WHERE id=$1", [m6.id]);
    ok(re.status === "acik" && re.occurrences >= 2, "erteleme bitince yeniden açılır", re);
    // geri al: tarihi geri çevir (kalan testler D gününe göre)
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    // kapat → 14 gün susturma
    const m6b = (await call("GET", "/assistant/insights", A)).j.items.find((i) => i.rule_key === "M6b");
    r = await call("POST", `/assistant/insights/${m6b.id}/dismiss`, A);
    ok(r.s === 200 && r.j.status === "kapatildi", "dismiss", r.j);
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    eq((await q1("SELECT status FROM insights WHERE id=$1", [m6b.id])).status, "kapatildi", "kapatılan insight 14 gün yeniden açılmaz");
    ok(!(await call("GET", "/assistant/insights", A)).j.items.some((i) => i.id === m6b.id), "kapatılan açık listede yok");
    // geri bildirim
    const m6c = (await call("GET", "/assistant/insights", A)).j.items.find((i) => i.rule_key === "M6c");
    eq((await call("POST", `/assistant/insights/${m6c.id}/feedback`, A, { verdict: "kötü" })).s, 400, "feedback geçersiz verdict");
    eq((await call("POST", `/assistant/insights/${m6c.id}/feedback`, A, { verdict: "yanlis", note: "x".repeat(501) })).s, 400, "feedback uzun not");
    r = await call("POST", `/assistant/insights/${m6c.id}/feedback`, A, { verdict: "yanlis", note: "Keşif sonrası zaten aradım" });
    ok(r.s === 200 && r.j.feedback === "yanlis" && r.j.status === "kapatildi", "feedback yanlış → kapanır", r.j);
    const m10 = (await call("GET", "/assistant/insights", A)).j.items.find((i) => i.rule_key === "M10");
    r = await call("POST", `/assistant/insights/${m10.id}/feedback`, A, { verdict: "yararli" });
    ok(r.s === 200 && r.j.feedback === "yararli" && r.j.status === "acik", "feedback yararlı açık kalır", r.j);
    const m11 = (await call("GET", "/assistant/insights", A)).j.items.find((i) => i.rule_key === "M11");
    r = await call("POST", `/assistant/insights/${m11.id}/applied`, A); eq(r.j.status, "uygulandi", "applied");
    // ortağın erişimi: başkasının insight'ına işlem 404
    eq((await call("POST", `/assistant/insights/${m11.id}/dismiss`, OA)).s, 404, "ortak başkasının insight'ını kapatamaz");
    eq((await call("POST", `/assistant/insights/${m11.id}/dismiss`, PA)).s, 403, "personel işlem yapamaz");
    r = await call("POST", "/assistant/insights/refresh", A); ok(r.s === 200 && r.j.scope === "business", "refresh ucu", r.j);
    // kapatılanlar geri açılsın (sonraki bölümler için): temizle
    await db.query("DELETE FROM insights WHERE scope_key='business'"); await db.query("DELETE FROM insight_runs");
    await engine.refresh(orgId, "business", { now: clock.now(), date: D });
  });

  // ================= 6) Kural yapılandırması =================
  await sec("kural-cfg", async () => {
    let r = await call("GET", "/assistant/insight-rules", A);
    ok(r.s === 200 && r.j.rules.length === 17, "insight-rules: 17 kural", r.j.rules && r.j.rules.length);
    const st = Object.fromEntries(r.j.rules.map((x) => [x.rule_key, x.status]));
    ok(st.M7 === (REAL.inv ? "aktif" : "bagimli") && st.M8 === (REAL.vat ? "aktif" : "bagimli") && st.M1 === "aktif", "durumlar: M7/M8 bağımlılığa göre, diğerleri aktif", st);
    const dep7 = r.j.rules.find((x) => x.rule_key === "M7").dependency;
    ok(dep7 && dep7.requires.includes("invoices") && dep7.available === REAL.inv && (REAL.inv || dep7.missing.includes("invoices")), "M7 bağımlılık bilgisi", dep7);
    ok(r.j.rules.every((x) => x.params && x.defaults && x.title && x.description), "her kuralın params/defaults/açıklaması var");
    eq((await call("GET", "/assistant/insight-rules", M)).s, 403, "muhasebe kural yapılandıramaz (yalnız admin)");
    eq((await call("GET", "/assistant/insight-rules", OA)).s, 403, "ortak 403");
    eq((await call("PUT", "/assistant/insight-rules", OA, { rules: [{ rule_key: "M6", enabled: false }] })).s, 403, "ortak PUT 403");
    for (const body of [{}, { rules: [] }, { rules: [{ rule_key: "M99", enabled: false }] }, { rules: [{ rule_key: "M6", params: { yok: 1 } }] }, { rules: [{ rule_key: "M6", params: { warn_days: -1 } }] }, { rules: [{ rule_key: "M6" }] }, { rules: [{ rule_key: "M6", enabled: "evet" }] }, { bilinmeyen: 1 }])
      eq((await call("PUT", "/assistant/insight-rules", A, body)).s, 400, "PUT geçersiz " + JSON.stringify(body).slice(0, 60));
    r = await call("PUT", "/assistant/insight-rules", A, { rules: [{ rule_key: "M6", enabled: false }] });
    ok(r.s === 200 && r.j.rules.find((x) => x.rule_key === "M6").status === "kapali", "M6 kapatıldı");
    let s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    eq(s.rules.M6.status, "devre_disi", "kapalı kural çalışmaz");
    const closed = await q1("SELECT status, closed_reason FROM insights WHERE rule_key='M6' AND scope_key='business'");
    ok(closed.status === "kapatildi" && closed.closed_reason === "kural_kapali", "kapalı kuralın insight'ı kapanır", closed);
    await call("PUT", "/assistant/insight-rules", A, { rules: [{ rule_key: "M6", enabled: true, params: { warn_days: 30, critical_days: 40 } }] });
    s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    eq(s.rules.M6.count, 0, "eşik parametresi değişince (30 gün) M6 tetiklenmez");
    await call("PUT", "/assistant/insight-rules", A, { rules: [{ rule_key: "M6", params: { warn_days: 3, critical_days: 7 } }] });
    s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
    eq(s.rules.M6.count, 1, "eşik varsayılana dönünce M6 yeniden tetiklenir");
    r = await call("PUT", "/assistant/insight-rules", A, { calibration_mode: true }); eq(r.j.calibration_mode, true, "kalibrasyon modu açık");
    await call("PUT", "/assistant/insight-rules", A, { calibration_mode: false });
  });

  // ================= 7) Bağımlı kurallar (M7/M8): tablo varsa devreye girer =================
  await sec("m7m8", async () => {
    const created = [];
    if (!REAL.inv) { await db.query("CREATE TABLE invoices (org_id uuid, owner_id uuid, project_id uuid, direction text, status text, odenecek_kurus bigint)"); created.push("invoices"); }
    if (!REAL.vat) { await db.query("CREATE TABLE vat_periods (org_id uuid, owner_id uuid, period_key text, odenecek_kurus bigint, due_date date, status text)"); created.push("vat_periods"); }
    const addInv = (pid, kurus, status) => REAL.inv
      ? db.query("INSERT INTO invoices (owner_id, org_id, direction, issue_date, project_id, matrah_kurus, kdv_oran, kdv_kurus, tutar_kurus, status) VALUES ($1,$2,'giden',$3,$4,$5,0,0,$5,$6)", [U.admin, orgId, D, pid, kurus, status])
      : db.query("INSERT INTO invoices (org_id, owner_id, project_id, direction, status, odenecek_kurus) VALUES ($1,$2,$3,'giden',$4,$5)", [orgId, U.admin, pid, status, kurus]);
    const addVat = (kurus, due, status) => REAL.vat
      ? db.query("INSERT INTO vat_periods (owner_id, org_id, period_key, period_type, year, month, starts_on, ends_on, odenecek_kurus, due_date, status) VALUES ($1,$2,'2026-10','aylik',2026,10,'2026-10-01','2026-10-31',$3,$4,$5)", [U.admin, orgId, kurus, due, status])
      : db.query("INSERT INTO vat_periods (org_id, owner_id, period_key, odenecek_kurus, due_date, status) VALUES ($1,$2,'2026-10',$3,$4,$5)", [orgId, U.admin, kurus, due, status]);
    try {
      deps._reset();
      await db.query("DELETE FROM insights WHERE rule_key IN ('M7','M8')");
      let s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
      eq(s.rules.M7.status, "ok", "M7 tablo gelince aktif"); eq(s.rules.M8.status, "ok", "M8 tablo gelince aktif");
      let list = await engine.list({ id: U.admin, role: "admin" }, orgId, { status: "acik", limit: 100, fresh: false });
      const m7 = rk(list, "M7");
      ok(m7.length === 1 && m7[0].severity === "critical" && m7[0].evidence.metrics.find((x) => x.key === "unbilled").value === 400000 && m7[0].body.includes("₺4.000,00"), "M7 faturasız tahsilat ₺4.000,00 (P2, 40 gün)", m7[0] && m7[0].evidence.metrics);
      await addInv(IDS.P2, 400000, "kesildi");
      await addInv(IDS.P1, 755000, "iptal"); // iptal fatura karşılık sayılmaz
      s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
      eq(s.rules.M7.count, 0, "M7 fatura kesilince (giden, iptal olmayan) tetiklenmez; P1 henüz 3 gün → eşik altı");
      await addVat(600025, d(1), "acik");
      s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
      list = await engine.list({ id: U.admin, role: "admin" }, orgId, { status: "acik", limit: 100, fresh: false });
      const m8 = rk(list, "M8");
      ok(m8.length === 1 && m8[0].severity === "critical" && m8[0].evidence.metrics.find((x) => x.key === "payable").value === 600025 && m8[0].body.includes("₺6.000,25"), "M8 KDV ₺6.000,25, 1 gün kala, nakit yetmez", m8[0] && m8[0].evidence.metrics);
      await db.query("UPDATE vat_periods SET status = 'kilitli'");
      s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
      eq(s.rules.M8.count, 0, "M8 beyan edilmiş (kilitli) dönem için tetiklenmez");
      await db.query("UPDATE vat_periods SET status = 'acik', odenecek_kurus = 0");
      s = await engine.refresh(orgId, "business", { now: clock.now(), date: D });
      eq(s.rules.M8.count, 0, "M8 ödenecek KDV yoksa tetiklenmez");
      const so = await engine.refresh(orgId, `user:${U.oa}`, { now: clock.now(), date: D });
      eq(so.rules.M8.status, "kapsam_disi", "M8 ortak kapsamında çalışmaz (yalnız işletme)");
    } finally {
      if (REAL.inv) await db.query("DELETE FROM invoices WHERE owner_id=$1 AND project_id IN ($2,$3)", [U.admin, IDS.P1, IDS.P2]);
      if (REAL.vat) await db.query("DELETE FROM vat_periods WHERE owner_id=$1 AND period_key='2026-10'", [U.admin]);
      for (const t of created) await db.query(`DROP TABLE IF EXISTS ${t}`);
      deps._reset();
    }
    if (created.includes("invoices")) { const s2 = await engine.refresh(orgId, "business", { now: clock.now(), date: D }); eq(s2.rules.M7.status, "bagimli", "tablo kalkınca M7 yeniden bağımlı"); }
    await db.query("DELETE FROM insights WHERE rule_key IN ('M7','M8')");
  });

  // ================= 8) Rol kapsamı: ortak A ≠ B, saha/personel =================
  await sec("kapsam", async () => {
    await engine.refresh(orgId, `user:${U.oa}`, { now: clock.now(), date: D });
    let r = await call("GET", "/assistant/insights", OA);
    ok(r.s === 200 && r.j.items.length >= 1, "ortak A kendi insight'larını görür", r.j);
    const a = rk(r.j.items, "M2");
    ok(a.length === 1 && a[0].entity.id === IDS.PA1 && a[0].severity === "critical" && a[0].body.includes("₺5.000,00"), "ortak A: M2 yalnız kendi işi (₺5.000,00)", a[0] && a[0].body);
    ok(!r.j.items.some((i) => JSON.stringify(i).includes(IDS.P1)), "ortak A işletmenin işini görmez");
    r = await call("GET", "/assistant/insights", OB); eq(r.j.items.length, 0, "ortak B boş (A'nın verisi sızmaz)");
    const admin = await call("GET", "/assistant/insights?status=all", A);
    ok(!JSON.stringify(admin.j).includes(IDS.PA1), "admin insight'larında ortağın işi yok");
    // brifing kapsamı
    const bA = (await call("GET", "/assistant/briefing/today", A)).j, bOA = (await call("GET", "/assistant/briefing/today", OA)).j, bOB = (await call("GET", "/assistant/briefing/today", OB)).j, bSF = (await call("GET", "/assistant/briefing/today", SF)).j, bPA = (await call("GET", "/assistant/briefing/today", PA)).j;
    const types = (b) => b.data.blocks.map((x) => x.type);
    ok(types(bA).includes("money") && types(bA).includes("attention") && types(bA).includes("low_stock") && types(bA).includes("new_requests"), "admin brifingi tam: para, dikkat, stok, yeni talep", types(bA));
    ok(bA.text.includes("₺") && bA.data.stats.appointments === 2, "admin brifing metni ₺ ve 2 randevu", bA.text);
    const sfTypes = types(bSF);
    ok(!sfTypes.some((t) => ["money", "collections", "low_stock", "new_requests", "attention"].includes(t)), "saha brifinginde finans/stok/yeni talep/dikkat yok", sfTypes);
    eq(bSF.data.stats.appointments, 1, "saha yalnız kendi randevusunu görür");
    ok(!/kurus|₺/.test(JSON.stringify(bSF)), "saha brifingi hiç para içermez");
    ok(!types(bPA).includes("money") && !types(bPA).includes("collections"), "personel brifinginde finans yok", types(bPA));
    eq(bOA.data.stats.appointments, 1, "ortak A brifingi kendi randevusu");
    ok(bOA.text.includes("Ortak Müşteri") && !bOA.text.includes("Ahmet Kaya"), "ortak A brifinginde yalnız kendi verisi", bOA.text);
    ok(bOB.data.empty === true && bOB.text.includes("Sakin bir gün") && bOB.data.stats.appointments === 0, "boş gün: ortak B anlamlı boş metin", bOB.text);
    ok(/₺/.test(bA.text) && bA.title.startsWith("Günaydın"), "başlık 'Günaydın …'", bA.title);
    // dolu brifing yapısı
    const ap = bA.data.blocks.find((x) => x.type === "appointments");
    ok(ap.count === 2 && ap.items[0].actions.call && ap.items[0].actions.whatsapp && ap.items[0].summary.startsWith("14:00"), "randevu kartı: saat, ara/WhatsApp aksiyonu", ap.items[0]);
    ok(bA.data.blocks.find((x) => x.type === "attention").items.length <= 3, "dikkat en çok 3");
    ok(bA.data.v === 1 && bA.data.kind === "morning" && bA.data.date === D && bA.data.weekday === "Çarşamba", "veri sürümü/gün");
    // brifing listesi / okundu
    const lst = await call("GET", "/assistant/briefings", A);
    ok(lst.s === 200 && lst.j.items.length >= 1 && lst.j.items[0].id === bA.id, "briefings listesi");
    eq((await call("GET", "/assistant/briefings?type=weekly", A)).j.items.length, 0, "tür süzgeci");
    eq((await call("GET", "/assistant/briefings?type=x", A)).s, 400, "geçersiz tür 400");
    eq((await call("GET", "/assistant/briefings?limit=1", A)).j.items.length, 1, "limit");
    ok(!(await call("GET", "/assistant/briefings", OA)).j.items.some((x) => x.id === bA.id), "başkasının brifingi listede yok");
    const rd = await call("POST", `/assistant/briefings/${bA.id}/read`, A); ok(rd.s === 200 && rd.j.read_at, "brifing okundu", rd.j);
    eq((await call("POST", `/assistant/briefings/${bA.id}/read`, OA)).s, 404, "başkasının brifingi okunamaz (404)");
    eq((await call("POST", `/assistant/briefings/abc/read`, A)).s, 400, "geçersiz id 400");
    const same = await call("GET", "/assistant/briefing/today", A); eq(same.j.id, bA.id, "briefing/today aynı kaydı döner");
    const fresh = await call("GET", "/assistant/briefing/today?refresh=1", A); eq(fresh.j.live, true, "refresh=1 yeniden üretir");
    eq((await call("GET", "/assistant/briefing/today", null)).s, 401, "brifing oturum ister");
  });

  // ================= 9) Brifing: tatil / Pazar / boş gün (süreç içi) =================
  await sec("tatil", async () => {
    const admin = { id: U.admin, role: "admin", name: "Admin Yönetici" };
    const sun = await morning.build(admin, { date: "2026-11-29", orgId });
    ok(sun.data.day_kind === "pazar" && sun.data.stats.appointments === 0 && sun.bodyText.includes("Pazar"), "Pazar: gün türü belirtilir", sun.bodyText);
    ok(!sun.data.blocks.some((b) => ["money", "low_stock", "new_requests", "question"].includes(b.type)), "Pazar: ayrıntılı bloklar yok");
    const sunB = await morning.build({ id: U.ob, role: "ortak", name: "OrtakB" }, { date: "2026-11-29", orgId });
    ok(sunB.data.empty && sunB.bodyText.includes("dinlenme günü") && sunB.title.includes("dinlenme"), "Pazar + boş: dinlenme günü metni", sunB.bodyText);
    if (REAL.hol) await db.query("INSERT INTO holidays_tr (org_id, day, name, kind) VALUES ($1,'2026-11-26','Test Bayramı','resmi'),($1,'2026-12-03','Arife Yarım Gün','resmi') ON CONFLICT DO NOTHING", [orgId]);
    else await db.query("CREATE TABLE IF NOT EXISTS holidays_tr (day date PRIMARY KEY, name text)").then(() => db.query("INSERT INTO holidays_tr VALUES ('2026-11-26','Test Bayramı') ON CONFLICT DO NOTHING"));
    if (REAL.hol) await db.query("UPDATE holidays_tr SET half_day = true WHERE day = '2026-12-03'");
    deps._reset();
    try {
      const hol = await morning.build(admin, { date: "2026-11-26", orgId });
      ok(hol.data.day_kind === "tatil" && hol.data.holiday === "Test Bayramı" && hol.bodyText.includes("Test Bayramı"), "resmî tatil adı brifingte", hol.bodyText);
      ok(hol.data.stats.appointments === 1 && hol.bodyText.includes("Randevular"), "tatilde kayıtlı randevu yine de gösterilir");
      const empty = await morning.build({ id: U.ob, role: "ortak", name: "OrtakB" }, { date: "2026-11-26", orgId });
      ok(empty.title.includes("Test Bayramı") && empty.data.empty, "tatil + boş: anlamlı başlık", empty.title);
      if (REAL.hol) { const half = await morning.build(admin, { date: "2026-12-03", orgId }); eq(half.data.day_kind, null, "yarım gün (arife) iş günü sayılır, tatil değil"); }
    } finally { if (REAL.hol) await db.query("DELETE FROM holidays_tr WHERE day IN ('2026-11-26','2026-12-03') AND name IN ('Test Bayramı','Arife Yarım Gün')"); else await db.query("DROP TABLE holidays_tr"); deps._reset(); }
    const wk = await morning.build({ id: U.ob, role: "ortak", name: "OrtakB" }, { date: "2026-12-02", orgId });
    ok(wk.data.empty && wk.title.includes("sakin"), "boş iş günü", wk.title);
  });

  // ================= 10) Kuyruk: sabah/akşam zamanlaması, tek 20:30 hatırlatması, idempotency =================
  await sec("zamanlama", async () => {
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox"); await db.query("DELETE FROM briefings WHERE kind <> 'evening'");
    await db.query("DELETE FROM daily_logs");
    setNow(D, "06:00");
    const pl = await planner.planAll();
    ok(pl.planned >= 8, "plan_day: sabah+akşam işleri planlandı", pl);
    let rr = await queue.runDue({ workerId: "t" });
    eq(rr.done, 0, "07:30 öncesi hiçbir iş çalışmaz");
    setNow(D, "07:31");
    rr = await queue.runDue({ workerId: "t" });
    const mor = await qa("SELECT user_id, title, body, data FROM notification_outbox WHERE type='briefing' ORDER BY created_at");
    ok(mor.length === 5 && !mor.some((o) => o.user_id === U.saha), "07:30: admin/muh/ortak×2/personel sabah brifingi aldı (saha yok)", mor.length);
    ok(mor.every((o) => o.data.kind === "morning" && o.data.briefing_id && o.title.startsWith("Günaydın")), "sabah bildirimi: kısa metin + briefing_id");
    const stored = await q1("SELECT COUNT(*)::int n FROM briefings WHERE kind='morning' AND period_start=$1::date", [D]);
    ok(stored.n >= 5, "brifing kaydı saklandı", stored);
    // idempotency: iş iki kez çalışsa tek bildirim
    const jb = await q1("SELECT id FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:${D}`]);
    await db.query("UPDATE jobs SET status='queued', finished_at=NULL, attempts=0, run_at=$2, expires_at=NULL WHERE id=$1", [jb.id, at(D, "07:30")]);
    await queue.runDue({ workerId: "t" });
    eq((await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:${D}`])).n, 1, "işleyici idempotent: iş 2 kez → TEK bildirim");
    eq((await q1("SELECT COUNT(*)::int n FROM briefings WHERE user_id=$1 AND kind='morning' AND period_start=$2::date", [U.admin, D])).n, 1, "brifing satırı tek");
    // akşam kapanış
    setNow(D, "18:29"); rr = await queue.runDue({ workerId: "t" });
    eq((await qa("SELECT 1 FROM notification_outbox WHERE type='closure'")).length, 0, "18:30 öncesi kapanış yok");
    setNow(D, "18:31"); await queue.runDue({ workerId: "t" });
    const clos = await qa("SELECT user_id, title, data FROM notification_outbox WHERE type='closure' ORDER BY created_at");
    ok(clos.length >= 1 && clos.every((c) => c.data.kind === "evening"), "18:30 kapanış bildirimi", clos.length);
    const adminClos = clos.find((c) => c.user_id === U.admin);
    ok(adminClos && adminClos.data.questions >= 3 && adminClos.title.includes("kısa soru"), "admin: sorular üretildi", adminClos);
    const nudge = await qa("SELECT user_id, run_at, status FROM jobs WHERE name='closure.nudge'");
    ok(nudge.length >= 1 && nudge.every((n) => new Date(n.run_at).toISOString() === at(D, "20:30").toISOString()), "tek hatırlatma 20:30'a planlandı", nudge);
    // ortak A (1 randevu) 19:00'da yanıtlar → hatırlatma gelmez
    setNow(D, "19:00");
    const oaLog = await closureSvc.getToday({ id: U.oa, role: "ortak", name: "OrtakA" }, { date: D, orgId });
    const qA = oaLog.questions.find((q) => q.kind === "appointment");
    await closureSvc.submit({ id: U.oa, role: "ortak", name: "OrtakA" }, { answers: [{ question_id: qA.id, choice: "yapildi" }] }, { orgId });
    setNow(D, "20:29"); await queue.runDue({ workerId: "t" });
    eq((await qa("SELECT 1 FROM notification_outbox WHERE data->>'kind'='evening_nudge'")).length, 0, "20:30 öncesi hatırlatma yok");
    setNow(D, "20:31"); await queue.runDue({ workerId: "t" });
    const nudges = await qa("SELECT user_id FROM notification_outbox WHERE data->>'kind'='evening_nudge'");
    ok(nudges.some((n) => n.user_id === U.admin) && !nudges.some((n) => n.user_id === U.oa), "20:30: yanıtlamayana hatırlatma, yanıtlayana yok", nudges.length);
    setNow(D, "21:45"); await queue.runDue({ workerId: "t" });
    setNow(D, "23:30"); await queue.runDue({ workerId: "t" });
    const perUser = await qa("SELECT user_id, COUNT(*)::int n FROM notification_outbox WHERE data->>'kind'='evening_nudge' GROUP BY 1");
    ok(perUser.every((p) => p.n === 1), "hatırlatma kullanıcı başına TEK (ısrar yok)", perUser);
    ok((await q1("SELECT nudged_at FROM daily_logs WHERE user_id=$1 AND log_date=$2::date", [U.admin, D])).nudged_at, "nudged_at işaretlendi");
    // Pazar: plan_day varsayılan tercihlerle iş planlamaz
    await db.query("DELETE FROM jobs");
    setNow("2026-11-29", "06:00"); await planner.planAll();
    eq((await q1("SELECT COUNT(*)::int n FROM jobs WHERE dedupe_key LIKE '%:2026-11-29' AND status='queued'")).n, 0, "Pazar: sabah/akşam işi planlanmaz");
    // haftalık (Pazartesi) / aylık (ayın 1'i)
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
    setNow("2026-11-30", "07:45");
    const pr = await a2planner.planManagerReports();
    eq(pr.weekly, 4, "Pazartesi: admin/muhasebe/ortak×2 için haftalık rapor planlandı (personel/saha yok)");
    await queue.runDue({ workerId: "t" });
    const wk = await qa("SELECT user_id, data FROM notification_outbox WHERE data->>'kind'='weekly'");
    eq(wk.length, 4, "haftalık bildirim 4 kişiye");
    const wb = await q1("SELECT to_char(period_start,'YYYY-MM-DD') ps, body_text, data FROM briefings WHERE user_id=$1 AND kind='weekly'", [U.admin]);
    ok(wb && wb.ps === "2026-11-23" && wb.data.kind === "weekly" && wb.body_text.length > 20, "haftalık rapor: önceki hafta (23 Kas)", wb && wb.ps);
    await a2planner.planManagerReports(); await queue.runDue({ workerId: "t" });
    eq((await qa("SELECT 1 FROM notification_outbox WHERE data->>'kind'='weekly'")).length, 4, "haftalık işi tekrar planlansa da yinelenmez");
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
    setNow("2026-12-01", "07:45");
    const pm = await a2planner.planManagerReports(); eq(pm.monthly, 4, "ayın 1'i: aylık rapor 4 kişiye");
    await queue.runDue({ workerId: "t" });
    const mb = await q1("SELECT to_char(period_start,'YYYY-MM-DD') ps, body_text, data FROM briefings WHERE user_id=$1 AND kind='monthly'", [U.admin]);
    ok(mb && mb.ps === "2026-11-01" && mb.data.kind === "monthly" && mb.body_text.includes("₺7.550,00"), "aylık rapor: Kasım, tahsilat ₺7.550,00", mb && mb.body_text);
    const mo = await q1("SELECT data, body_text FROM briefings WHERE user_id=$1 AND kind='monthly'", [U.oa]);
    ok(mo && !mo.body_text.includes("7.550,00"), "ortak A aylık raporunda işletmenin tutarı yok");
    // son: sahte saati geri kur
    clock.setFake(FAKE_NOW);
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
  });

  // ================= 11) Akşam kapanış akışı =================
  await sec("kapanis", async () => {
    clock.setFake(at(D, "18:35"));
    await db.query("DELETE FROM daily_logs"); await db.query("DELETE FROM followups");
    let r = await call("GET", "/assistant/closure/today", A);
    ok(r.s === 200 && r.j.status === "pending" && r.j.date === D, "closure/today", r.j.status);
    // sunucu saati 10:00 → bugünün soruları aynı gün
    const q = r.j.questions; const kinds = q.map((x) => x.kind);
    eq(kinds, ["appointment", "money", "stage", "cost", "tomorrow"], "soru sırası (değer önceliği) ve en çok 5");
    ok(q.every((x) => x.skippable && Array.isArray(x.options) && x.options.length >= 2), "her soru atlanabilir + chip seçenekleri");
    ok(q[0].options[0].follow_up && q[0].options[0].follow_up.length === 4, "randevu 'Yapıldı' → alt chip'ler");
    ok(r.j.summary_card && r.j.summary_card.appointments.total === 2 && r.j.summary_card.tomorrow.count === 1, "özet kartı", r.j.summary_card);
    const qa_ = (k) => q.find((x) => x.kind === k);
    // doğrulama hataları
    for (const [body, why] of [
      [{ answers: [{ question_id: "yok", choice: "x" }] }, "bilinmeyen soru"],
      [{ answers: [{ question_id: qa_("money").id, choice: "zzz" }] }, "geçersiz seçim"],
      [{ answers: [{ question_id: qa_("stage").id, choice: "evet", amount_kurus: 5 }] }, "tutar yalnız para sorusunda"],
      [{ answers: [{ question_id: qa_("money").id, choice: "tahsilat", amount_kurus: -5 }] }, "negatif tutar"],
      [{ answers: [{ question_id: qa_("money").id, choice: "tahsilat", amount_kurus: 10.5 }] }, "ondalık kuruş"],
      [{ answers: [{ question_id: q[0].id, choice: "ertelendi", follow_up: "anlastik" }] }, "geçersiz follow_up"],
      [{ date: "2026-11-26", answers: [] }, "gelecek gün"], [{ date: "2026-11-01", answers: [] }, "çok eski gün"], [{ yeni: 1 }, "bilinmeyen alan"], [{ answers: "x" }, "answers dizi değil"],
    ]) { const x = await call("POST", "/assistant/closure/answers", A, body); eq(x.s, 400, "closure 400: " + why); }
    const payCount0 = (await q1("SELECT COUNT(*)::int n FROM payments")).n;
    const stage0 = (await q1("SELECT stage FROM projects WHERE id=$1", [IDS.P1])).stage;
    r = await call("POST", "/assistant/closure/answers", A, { answers: [
      { question_id: q[0].id, choice: "yapildi", follow_up: "teklif_verilecek" },
      { question_id: qa_("money").id, choice: "tahsilat", amount_kurus: 150000, project_id: IDS.P1 },
      { question_id: qa_("stage").id, choice: "evet" },
      { question_id: qa_("cost").id, choice: "tamam" },
      { question_id: qa_("tomorrow").id, choice: "hatirlat" },
    ], free_note: "Ahmet Bey ertesi hafta aranacak" });
    ok(r.s === 200, "closure/answers 200", r.j);
    eq((await q1("SELECT status FROM appointments WHERE id=$1", [IDS.AT])).status, "tamamlandı", "randevu durumu doğrudan güncellendi");
    const fu = await qa("SELECT kind, title, to_char(due_date,'YYYY-MM-DD') due, source FROM followups WHERE user_id=$1", [U.admin]);
    ok(fu.length === 1 && fu[0].kind === "teklif" && fu[0].due === d(1) && fu[0].source === "kapanis", "takip oluşturuldu (yarın)", fu);
    ok((await q1("SELECT cost_confirmed_at FROM projects WHERE id=$1", [IDS.P1])).cost_confirmed_at, "maliyet onayı yazıldı");
    const rem = await qa("SELECT title, source, to_char(remind_at AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD HH24:MI') t FROM reminders WHERE owner_id=$1 AND source='brifing'", [U.admin]);
    ok(rem.length === 1 && rem[0].t === `${d(1)} 08:00`, "yarın hazırlık hatırlatması 08:00", rem);
    const props = r.j.closure_proposals;
    ok(props.some((p) => p.type === "payment_create" && p.amount_kurus === 150000 && p.apply.path === `/api/projects/${IDS.P1}/payments` && p.apply.body.amount === 1500), "tahsilat ÖNERİSİ (apply tarifi, tutar 1500)", props);
    ok(props.some((p) => p.type === "project_stage" && p.to === "Tamamlandı"), "aşama ÖNERİSİ");
    eq((await q1("SELECT COUNT(*)::int n FROM payments")).n, payCount0, "tahsilat doğrudan YAZILMADI (öneri)");
    eq((await q1("SELECT stage FROM projects WHERE id=$1", [IDS.P1])).stage, stage0, "aşama doğrudan DEĞİŞMEDİ (öneri)");
    ok(r.j.log.status === "done" && r.j.log.completeness === 100 && r.j.log.free_note.includes("Ahmet"), "kayıt tamamlandı %100 + serbest not", r.j.log.status);
    ok(r.j.summary_card.appointments.done === 2 && r.j.summary_card.followups_created === 1 && r.j.summary_card.text.includes("2 yapıldı"), "gün sonu özeti kartı", r.j.summary_card.text);
    ok(!!(await q1("SELECT 1 x FROM briefings WHERE user_id=$1 AND kind='evening' AND period_start=$2::date", [U.admin, D])), "evening brifing kaydı");
    const dl = await q1("SELECT status, completeness, answers FROM daily_logs WHERE user_id=$1 AND log_date=$2::date", [U.admin, D]);
    ok(dl.status === "done" && Object.keys(dl.answers).length === 5, "daily_logs kaydı", dl.status);
    // aynı yanıt tekrar → idempotent
    r = await call("POST", "/assistant/closure/answers", A, { answers: [{ question_id: q[0].id, choice: "yapildi", follow_up: "teklif_verilecek" }, { question_id: qa_("tomorrow").id, choice: "hatirlat" }] });
    eq(r.s, 200, "tekrar gönderim 200");
    eq((await q1("SELECT COUNT(*)::int n FROM followups WHERE user_id=$1 AND status='acik'", [U.admin])).n, 1, "idempotent: takip yinelenmez");
    eq((await q1("SELECT COUNT(*)::int n FROM reminders WHERE owner_id=$1 AND source='brifing'", [U.admin])).n, 1, "idempotent: hatırlatma yinelenmez");
    // yanıtı değiştir: 'sonra_ara' → eski takip iptal, yenisi
    r = await call("POST", "/assistant/closure/answers", A, { answers: [{ question_id: q[0].id, choice: "yapildi", follow_up: "sonra_ara" }] });
    const fu2 = await qa("SELECT kind, status FROM followups WHERE user_id=$1 ORDER BY created_at", [U.admin]);
    ok(fu2.filter((x) => x.status === "acik").length === 1 && fu2.some((x) => x.status === "iptal"), "yanıt değişince eski takip iptal, tek açık takip", fu2);
    // randevu yok / ertelendi → öneri
    // saha: yalnız kendi sorusu, finans yok
    await appt("Montaj", D, "17:00", { owner: U.admin, assigned: U.saha, name: "Saha İşi", phone: "05350000000" });
    const sf = await call("GET", "/assistant/closure/today", SF);
    ok(sf.s === 200 && sf.j.questions.every((x) => ["appointment", "tomorrow"].includes(x.kind)), "saha kapanışı: yalnız randevu/yarın soruları", sf.j.questions.map((x) => x.kind));
    ok(sf.j.summary_card.money === null, "saha özetinde para yok");
    const sfq = sf.j.questions.find((x) => x.kind === "appointment");
    ok(!sfq.options[0].follow_up, "saha için satış alt chip'i yok");
    r = await call("POST", "/assistant/closure/answers", SF, { answers: [{ question_id: sfq.id, choice: "yapildi" }], finish: true });
    ok(r.s === 200, "saha yanıtı"); 
    // başkasının sorusu: ortak A, admin'in soru kimliğini kullanamaz
    r = await call("POST", "/assistant/closure/answers", OB, { answers: [{ question_id: q[0].id, choice: "yapildi" }] });
    eq(r.s, 400, "ortak B başka kullanıcının sorusunu yanıtlayamaz");
    eq((await call("POST", "/assistant/closure/answers", null, {})).s, 401, "kapanış oturum ister");
    // atlama ve bastırma
    const log = await closureSvc.getToday({ id: U.ob, role: "ortak", name: "OrtakB" }, { date: D, orgId });
    ok(log.questions.some((x) => x.kind === "money"), "ortak B: para sorusu var");
    const rb = await call("POST", "/assistant/closure/answers", OB, { answers: log.questions.map((x) => ({ question_id: x.id, skipped: true })) });
    ok(rb.s === 200 && rb.j.log.status === "skipped" && rb.j.applied.length === 0, "hepsi atlandı → durum skipped, yan etki yok", rb.j.log.status);
    for (const day of [d(-1), d(-2)]) await db.query(`INSERT INTO daily_logs (user_id, log_date, status, answers) VALUES ($1,$2::date,'skipped','{"money":{"skipped":true,"skip_key":"money"}}')`, [U.pa, day]);
    for (const day of [d(-1), d(-2)]) await db.query(`INSERT INTO daily_logs (user_id, log_date, status, answers) VALUES ($1,$2::date,'skipped','{"money":{"skipped":true,"skip_key":"money"}}')`, [U.oa, day]);
    await db.query("DELETE FROM daily_logs WHERE user_id=$1 AND log_date=$2::date", [U.oa, D]);
    const oa2 = await closureSvc.getToday({ id: U.oa, role: "ortak", name: "OrtakA" }, { date: D, orgId });
    ok(!oa2.questions.some((x) => x.kind === "money"), "2 kez atlanan soru 14 gün sorulmaz", oa2.questions.map((x) => x.kind));
    clock.setFake(FAKE_NOW);
  });

  // ================= 12) Hatırlatma: sözleşme, erteleme, tekrar, randevu öncesi =================
  await sec("hatirlatma", async () => {
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
    // mevcut sözleşme bozulmadı
    let r = await call("POST", "/reminders", A, { title: "Eski sözleşme", remind_at: at(D, "15:00").toISOString() });
    ok(r.s === 201 && r.j.status === "bekliyor" && r.j.title === "Eski sözleşme" && r.j.owner_id === U.admin && r.j.recurrence === null, "POST /reminders aynen çalışır", r.j);
    eq((await call("POST", "/reminders", A, { title: "x" })).s, 400, "POST /reminders başlık+tarih zorunlu");
    eq((await call("POST", "/reminders", A, { title: "x", remind_at: "yarın" })).s, 400, "POST /reminders geçersiz tarih");
    eq((await call("POST", "/reminders", A, { title: "x", remind_at: at(D, "15:00").toISOString(), recurrence: "saatlik" })).s, 400, "geçersiz recurrence 400");
    const plain = r.j;
    r = await call("PATCH", `/reminders/${plain.id}`, A, { status: "tamamlandi" }); ok(r.s === 200 && r.j.status === "tamamlandi", "PATCH tamamlandi (tekrarsız)");
    eq((await call("PATCH", `/reminders/${plain.id}`, A, { status: "x" })).s, 400, "PATCH geçersiz durum");
    eq((await call("PATCH", `/reminders/${plain.id}`, OA, { status: "bekliyor" })).s, 403, "başkasının hatırlatıcısı 403");
    ok((await call("GET", "/reminders", A)).j.some((x) => x.id === plain.id), "GET /reminders");
    // tekrar
    r = await call("POST", "/reminders", A, { title: "Günlük kontrol", remind_at: at(D, "16:00").toISOString(), recurrence: "daily" });
    ok(r.s === 201 && r.j.recurrence === "daily", "tekrarlı hatırlatma oluştu"); const rec = r.j;
    ok(!!(await q1("SELECT 1 x FROM jobs WHERE name='reminder.fire' AND payload->>'reminderId'=$1", [rec.id])), "hatırlatma için reminder.fire işi planlandı");
    r = await call("PATCH", `/reminders/${rec.id}`, A, { status: "tamamlandi" });
    ok(r.s === 200 && r.j.status === "tamamlandi", "tekrarlı tamamlandı");
    const next = await q1("SELECT to_char(remind_at AT TIME ZONE 'Europe/Istanbul','YYYY-MM-DD HH24:MI') t, status FROM reminders WHERE owner_id=$1 AND source_key=$2", [U.admin, `rec:${rec.id}`]);
    ok(next && next.t === `${d(1)} 16:00` && next.status === "bekliyor", "sonraki oluşum yarın 16:00", next);
    r = await call("POST", `/assistant/reminders/${rec.id}/complete`, A); ok(r.s === 200 && r.j.already === true, "complete idempotent");
    eq((await q1("SELECT COUNT(*)::int n FROM reminders WHERE source_key=$1", [`rec:${rec.id}`])).n, 1, "tekrar: ikinci tamamlama yeni satır eklemez");
    // erteleme
    r = await call("POST", "/reminders", A, { title: "Ertelenecek", remind_at: at(D, "10:05").toISOString() }); const sn = r.j;
    eq((await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, {})).s, 400, "snooze preset gerekli");
    eq((await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { preset: "haftaya" })).s, 400, "snooze geçersiz preset");
    eq((await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { minutes: 3 })).s, 400, "snooze <5 dk geçersiz");
    eq((await call("POST", `/assistant/reminders/${sn.id}/snooze`, OA, { preset: "15m" })).s, 403, "başkasının hatırlatıcısı ertelenemez");
    r = await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { preset: "15m" });
    ok(r.s === 200 && new Date(r.j.remind_at).toISOString() === at(D, "10:15").toISOString() && r.j.snooze_count === 1, "15 dk erteleme (10:15)", r.j);
    r = await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { preset: "1h" }); eq(new Date(r.j.remind_at).toISOString(), at(D, "11:00").toISOString(), "1 saat erteleme");
    r = await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { preset: "tomorrow" }); eq(new Date(r.j.remind_at).toISOString(), at(d(1), "09:00").toISOString(), "yarın 09:00 erteleme");
    eq(r.j.snooze_count, 3, "erteleme sayacı");
    r = await call("POST", `/assistant/reminders/${sn.id}/snooze`, A, { minutes: 30 }); eq(new Date(r.j.remind_at).toISOString(), at(D, "10:30").toISOString(), "dakika ile erteleme");
    // zamanı gelince TEK bildirim (eski zamanlı iş sessizce atlanır)
    setNow(D, "10:31"); await queue.runDue({ workerId: "t" });
    const fired = await qa("SELECT data FROM notification_outbox WHERE type='reminder' AND data->>'reminder_id'=$1", [sn.id]);
    eq(fired.length, 1, "ertelenen hatırlatma yalnız yeni zamanında TEK kez bildirir");
    ok(fired[0].data.actions.some((a) => a.id === "snooze_15m") && fired[0].data.actions.some((a) => a.id === "done"), "bildirim eylemleri: tamam / ertele");
    await queue.runDue({ workerId: "t" });
    eq((await qa("SELECT 1 FROM notification_outbox WHERE type='reminder' AND data->>'reminder_id'=$1", [sn.id])).length, 1, "tekrar çalıştırma yinelemez");
    r = await call("POST", `/assistant/reminders/${plain.id}/snooze`, A, { preset: "15m" }); eq(r.s, 409, "tamamlanmış hatırlatma ertelenemez (409)");
    clock.setFake(FAKE_NOW);
    // randevu öncesi: akşam 18:00 + 1 saat önce
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
    const cancelled = await appt("Montaj", d(1), "15:00", { owner: U.admin, assigned: U.saha, name: "İptal Edilecek" });
    const pr = await a2planner.planAppointmentReminders();
    ok(pr.eve >= 2 && pr.hour >= 2, "randevu öncesi hatırlatmalar planlandı (admin + saha)", pr);
    const pr2 = await a2planner.planAppointmentReminders(); ok(pr2.eve === 0 && pr2.hour === 0, "yeniden planlama yinelenmez", pr2);
    setNow(D, "17:59"); await queue.runDue({ workerId: "t" });
    eq((await qa("SELECT 1 FROM notification_outbox WHERE data->>'kind'='appointment_eve'")).length, 0, "18:00 öncesi akşam hatırlatması yok");
    setNow(D, "18:01"); await queue.runDue({ workerId: "t" });
    const eve = await qa("SELECT user_id, title FROM notification_outbox WHERE data->>'kind'='appointment_eve'");
    ok(eve.length === 2 && eve.find((e) => e.user_id === U.saha) && eve.every((e) => e.title === "Yarın 2 randevu" || e.title === "Yarın 1 randevu"), "akşam hatırlatması: kullanıcı başına TEK", eve);
    await db.query("UPDATE appointments SET status='iptal' WHERE id=$1", [cancelled]);
    setNow(d(1), "09:01"); await queue.runDue({ workerId: "t" });
    const hr = await qa("SELECT user_id, title, data FROM notification_outbox WHERE data->>'kind'='appointment_hour'");
    ok(hr.length === 2 && hr.every((x) => x.data.appointment_id === IDS.AM && x.title.startsWith("10:00")), "1 saat önce: yalnız iptal olmayan randevu (admin + saha)", hr.map((x) => x.title));
    ok(hr[0].data.actions && hr[0].data.actions.call, "randevu bildirimi ara aksiyonu içerir");
    clock.setFake(FAKE_NOW);
    await db.query("DELETE FROM jobs"); await db.query("DELETE FROM notification_outbox");
  });

  // ================= 13) Takipler =================
  await sec("takip", async () => {
    let r = await call("POST", "/assistant/followups", A, { title: "Ayşe Hanım'ı ara", due_date: d(1), kind: "ara" });
    ok(r.s === 201 && r.j.status === "acik", "takip oluştur", r.j);
    eq((await call("POST", "/assistant/followups", A, { title: "", due_date: d(1) })).s, 400, "takip başlık zorunlu");
    eq((await call("POST", "/assistant/followups", A, { title: "x", due_date: "yarın" })).s, 400, "takip tarih biçimi");
    eq((await call("POST", "/assistant/followups", A, { title: "x", due_date: d(1), kind: "zzz" })).s, 400, "takip tür");
    const id = r.j.id;
    r = await call("GET", "/assistant/followups", A); ok(r.j.items.some((x) => x.id === id), "takip listesi");
    ok(!(await call("GET", "/assistant/followups", OA)).j.items.some((x) => x.id === id), "başkasının takibi görünmez");
    eq((await call("POST", `/assistant/followups/${id}/done`, OA)).s, 404, "başkasının takibi tamamlanamaz");
    r = await call("POST", `/assistant/followups/${id}/snooze`, A, { days: 2 }); ok(r.s === 200 && r.j.status === "ertelendi" && r.j.snoozed_until === d(2), "takip ertele", r.j);
    eq((await call("POST", `/assistant/followups/${id}/snooze`, A, { days: 0 })).s, 400, "takip ertele geçersiz gün");
    r = await call("POST", `/assistant/followups/${id}/done`, A); eq(r.j.status, "yapildi", "takip tamamlandı");
  });

  console.log(`\nv20: ${pass} geçti, ${fail} başarısız`);
  clock.reset();
  await db.pool.end();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST ÇÖKTÜ:", e); process.exit(2); });
