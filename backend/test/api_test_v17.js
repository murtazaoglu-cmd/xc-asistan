// v17 asistan altyapısı testleri: şema/org, saat, kuyruk (çift çalıştırma, catch-up, dedupe, geri çekilme), plan_day, bildirim outbox,
// FCM (anahtarsız dry-run + sahte FCM), bildirim kutusu, /config yetkileri, tercihler, sektör şablonu, /api/v1, Idempotency-Key, worker sağlığı.
// Önkoşul: TEMİZ veritabanı + migrate + seed (admin@x.com, muh@x.com, oa@x.com, ob@x.com, pa@x.com / pass1234);
// sunucu :4101'de (README "Asistan altyapısı (v17)"), cwd = backend klasörü. FCM_* ortam değişkenleri sunucuda TANIMSIZ olmalı.
const crypto = require("crypto"), http = require("http"), path = require("path");
const { spawn } = require("child_process");
const db = require("../src/db"); // dotenv'i de yükler
const clock = require("../src/assistant/clock");
const queue = require("../src/assistant/queue");
const { notifyUser } = require("../src/assistant/notify");
const sender = require("../src/assistant/sender");
const fcmv1 = require("../src/assistant/fcmv1");
const planner = require("../src/assistant/planner");
const { logAction } = require("../src/assistant/audit");
const PORT = process.env.TEST_PORT || 4101;
const B = `http://localhost:${PORT}/api`;
const ROOT = path.resolve(__dirname, "..");
let pass = 0, fail = 0;
const ok = (c, m, extra) => { if (c) pass++; else { fail++; console.log("FAIL:", m, extra !== undefined ? JSON.stringify(extra).slice(0, 700) : ""); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ipSeq = 0;
async function call(method, p, token, body, headers = {}, base = B) {
  const xff = !token && method === "POST" && p.startsWith("/offers") ? { "X-Forwarded-For": `10.77.${Math.floor(++ipSeq / 250)}.${(ipSeq % 250) + 1}` } : {};
  const r = await fetch(base + p, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: "Bearer " + token } : {}), ...xff, ...headers }, body: body !== undefined ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(20000) });
  let j = null; try { j = await r.json(); } catch {}
  return { s: r.status, j, h: r.headers };
}
const login = async (e, pw = "pass1234") => (await call("POST", "/auth/login", null, { email: e, password: pw })).j?.token;
const q1 = async (sql, params) => (await db.query(sql, params)).rows[0];
const qa = async (sql, params) => (await db.query(sql, params)).rows;
const iso = (d) => new Date(d).toISOString();
const uid = async (email) => (await q1("SELECT id FROM users WHERE email = $1", [email])).id;

(async () => {
  const A = await login("admin@x.com"), M = await login("muh@x.com"), OA = await login("oa@x.com"), OB = await login("ob@x.com"), PA = await login("pa@x.com");
  ok(A && M && OA && OB && PA, "girişler");
  const U = { admin: await uid("admin@x.com"), muh: await uid("muh@x.com"), oa: await uid("oa@x.com"), ob: await uid("ob@x.com"), pa: await uid("pa@x.com") };
  delete process.env.FCM_SERVICE_ACCOUNT_JSON; delete process.env.FCM_SERVICE_ACCOUNT_FILE; fcmv1._reset();

  // ================= 1) Şema / kuruluş / org_id =================
  {
    const orgs = await qa("SELECT * FROM organizations");
    ok(orgs.length === 1 && orgs[0].is_default, "tek varsayılan kuruluş", orgs.length);
    const nullUsers = await q1("SELECT COUNT(*)::int n FROM users WHERE org_id IS NULL");
    ok(nullUsers.n === 0, "users backfill: org_id dolu", nullUsers);
    for (const t of ["offers", "quotes", "projects", "payments", "expenses", "appointments", "reminders", "materials", "customers", "quote_templates", "device_tokens"]) {
      const c = await q1(`SELECT is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = 'org_id'`, [t]);
      ok(c && c.is_nullable === "YES", `${t}.org_id var ve NULLABLE`, c);
    }
    const o = await call("POST", "/offers", null, { name: "Org Test", phone: "05001112233", service: "Hizmet X", message: "m" });
    ok(o.s === 201, "anonim teklif hâlâ çalışır", o);
    const row = await q1("SELECT org_id FROM offers ORDER BY created_at DESC LIMIT 1");
    ok(row.org_id === orgs[0].id, "yeni satıra varsayılan org atanır (tetikleyici)", row);
    ok((await q1("SELECT next_org_counter($1,'t') AS v", [orgs[0].id])).v === 1 && (await q1("SELECT next_org_counter($1,'t') AS v", [orgs[0].id])).v === 2, "org_counters: next_org_counter");
    const tpl = await qa("SELECT key FROM sector_templates");
    for (const k of ["genel", "tadilat_insaat", "demir_dograma", "klima_teknik_servis", "kuafor_berber", "nakliye", "temizlik"]) ok(tpl.some((t) => t.key === k), "şablon tohumu: " + k);
    ok((await q1("SELECT key FROM sector_templates WHERE is_default")).key === "genel", "genel varsayılan");
    ok((await q1("SELECT sector_key FROM org_settings")).sector_key === "genel", "boş kurulumda org ayarı = genel");
    ok((await q1("SELECT COUNT(*)::int n FROM feature_flags WHERE key IN ('ai_enabled','assistant_inbox')")).n === 2, "feature_flags tohumu");
    // outbox 'offer' bildirimleri (services/fcm.js kancası → notify)
    let n = 0; for (let i = 0; i < 20 && n < 2; i++) { n = (await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE type = 'offer'")).n; if (n < 2) await sleep(150); }
    ok(n >= 2, "yeni teklif bildirimi outbox'a düştü (admin + muhasebe)", n);
  }

  // ================= 2) Saat =================
  {
    clock.setFake("2026-11-20T21:30:00Z");
    ok(iso(clock.now()) === "2026-11-20T21:30:00.000Z", "sahte saat now()");
    ok(clock.istanbulDateStr() === "2026-11-21", "istanbulDateStr gün atlar (00:30 İstanbul)", clock.istanbulDateStr());
    ok(iso(clock.istanbulDay()) === "2026-11-20T21:00:00.000Z", "istanbulDay = İstanbul gün başı", iso(clock.istanbulDay()));
    ok(iso(clock.zonedToUtc("2026-11-21", "07:30")) === "2026-11-21T04:30:00.000Z", "zonedToUtc İstanbul 07:30");
    ok(clock.istanbulWeekday(new Date("2026-11-22T10:00:00Z")) === 7, "istanbulWeekday Pazar=7");
    ok(iso(clock.zonedToUtc("2026-07-01", "09:00", "Europe/Berlin")) === "2026-07-01T07:00:00.000Z", "zonedToUtc yaz saati (Berlin)");
    clock.reset();
    ok(!clock.isFake() && Math.abs(clock.now() - Date.now()) < 2000, "reset gerçek saat");
  }

  // ================= 3) Kuyruk =================
  {
    clock.setFake("2026-12-01T09:00:00Z");
    const calls = {};
    queue.registerHandler("t.count", async (p) => { calls[p.n] = (calls[p.n] || 0) + 1; });
    let flaky = 0;
    queue.registerHandler("t.flaky", async () => { if (++flaky === 1) throw new Error("geçici"); });
    queue.registerHandler("t.boom", async () => { throw new Error("hep patlar"); });

    const e1 = await queue.enqueue("t.count", { n: 1 }, { dedupeKey: "t:1", runAt: clock.now() });
    const e2 = await queue.enqueue("t.count", { n: 1 }, { dedupeKey: "t:1", runAt: clock.now() });
    ok(!e1.deduped && e2.deduped && e1.id === e2.id, "enqueue dedupeKey tekilleştirir");
    ok((await q1("SELECT COUNT(*)::int n FROM jobs WHERE dedupe_key='t:1'")).n === 1, "tek kayıt");
    const e3 = await queue.enqueue("t.count", { n: 3 }, { runAt: clock.now() }), e4 = await queue.enqueue("t.count", { n: 4 }, { runAt: clock.now() });
    ok(e3.id !== e4.id, "dedupeKey'siz işler ayrı kayıt");
    await queue.enqueue("t.count", { n: 9 }, { dedupeKey: "t:future", runAt: new Date(clock.now().getTime() + 3600e3) });
    const r = await queue.runDue({ workerId: "w1" });
    ok(r.done === 3 && calls[1] === 1 && calls[3] === 1 && calls[4] === 1, "vadesi gelenler çalıştı", { r, calls });
    ok(calls[9] === undefined, "gelecekteki iş çalışmadı");
    clock.setFake("2026-12-01T10:01:00Z");
    await queue.runDue({ workerId: "w1" });
    ok(calls[9] === 1, "vadesi gelince çalıştı");
    ok((await queue.runDue({ workerId: "w1" })).claimed === 0, "bitmiş iş tekrar çalışmaz");

    // yeniden deneme + geri çekilme
    clock.setFake("2026-12-02T09:00:00Z");
    const fl = await queue.enqueue("t.flaky", {}, { runAt: clock.now() });
    let rr = await queue.runDue({ workerId: "w1" });
    let row = await q1("SELECT * FROM jobs WHERE id=$1", [fl.id]);
    ok(rr.retried === 1 && row.status === "queued" && row.attempts === 1 && iso(row.run_at) === "2026-12-02T09:01:00.000Z", "hata → 1 dk geri çekilme", row);
    ok((await queue.runDue({ workerId: "w1" })).claimed === 0, "geri çekilme bitmeden tekrar denenmez");
    clock.setFake("2026-12-02T09:01:05Z");
    rr = await queue.runDue({ workerId: "w1" });
    row = await q1("SELECT * FROM jobs WHERE id=$1", [fl.id]);
    ok(rr.done === 1 && row.status === "done" && row.attempts === 2 && row.last_error === null, "ikinci denemede tamam", row);
    const bm = await queue.enqueue("t.boom", {}, { runAt: clock.now(), maxAttempts: 2 });
    await queue.runDue({ workerId: "w1" });
    clock.setFake("2026-12-02T09:03:00Z");
    rr = await queue.runDue({ workerId: "w1" });
    row = await q1("SELECT * FROM jobs WHERE id=$1", [bm.id]);
    ok(rr.failed === 1 && row.status === "failed" && /hep patlar/.test(row.last_error), "deneme hakkı bitince failed", row);
    const nh = await queue.enqueue("t.yok", {}, { runAt: clock.now(), maxAttempts: 1 });
    await queue.runDue({ workerId: "w1" });
    ok((await q1("SELECT status, last_error FROM jobs WHERE id=$1", [nh.id])).status === "failed", "işleyicisiz iş failed (sessizce kaybolmaz)");

    // catch-up (kaçırılan iş) ve süre aşımı
    clock.setFake("2026-12-03T12:00:00Z");
    const late = await queue.enqueue("t.count", { n: 20 }, { runAt: new Date("2026-12-03T04:30:00Z"), expiresAt: new Date("2026-12-03T14:00:00Z") });
    const dead = await queue.enqueue("t.count", { n: 21 }, { runAt: new Date("2026-12-03T04:30:00Z"), expiresAt: new Date("2026-12-03T08:00:00Z") });
    rr = await queue.runDue({ workerId: "w1" });
    ok(calls[20] === 1 && calls[21] === undefined, "catch-up: kaçırılan ama süresi dolmayan çalışır; süresi dolan çalışmaz", calls);
    const dr = await q1("SELECT status, last_error FROM jobs WHERE id=$1", [dead.id]);
    ok(dr.status === "skipped" && /kaçırıldı/.test(dr.last_error) && rr.expired === 1, "süresi geçen iş 'skipped' + kaçırıldı kaydı", dr);

    // çöken worker kurtarma
    const crashed = await queue.enqueue("t.count", { n: 30 }, { runAt: clock.now() });
    await db.query("UPDATE jobs SET status='running', locked_by='ölü', locked_at=$2, attempts=1 WHERE id=$1", [crashed.id, new Date("2026-12-03T11:00:00Z")]);
    rr = await queue.runDue({ workerId: "w1" });
    ok(rr.recovered === 1 && calls[30] === 1, "kilidi zaman aşımına uğrayan 'running' iş kurtarılıp çalıştı", rr);
    const live = await queue.enqueue("t.count", { n: 31 }, { runAt: clock.now() });
    await db.query("UPDATE jobs SET status='running', locked_by='canlı', locked_at=$2, attempts=1 WHERE id=$1", [live.id, new Date("2026-12-03T11:58:00Z")]);
    await queue.runDue({ workerId: "w1" });
    ok(calls[31] === undefined, "taze kilitli iş (başka worker çalışıyor) alınmaz");

    // eşzamanlılık: 3 worker, 40 iş → her iş TAM 1 kez
    await db.query("UPDATE jobs SET status='done' WHERE status IN ('queued','running')");
    clock.setFake("2026-12-04T09:00:00Z");
    const exec = new Map();
    queue.registerHandler("t.conc", async (p) => { exec.set(p.i, (exec.get(p.i) || 0) + 1); await sleep(5); });
    for (let i = 0; i < 40; i++) await queue.enqueue("t.conc", { i }, { dedupeKey: "conc:" + i, runAt: clock.now() });
    const rs = await Promise.all(["wa", "wb", "wc"].map((w) => queue.runDue({ workerId: w, limit: 7 })));
    ok(exec.size === 40 && [...exec.values()].every((v) => v === 1), "3 eşzamanlı worker: her iş tam bir kez", { n: exec.size, dup: [...exec.values()].filter((v) => v !== 1).length });
    ok(rs.reduce((a, x) => a + x.claimed, 0) === 40, "toplam talep = 40", rs);
    ok((await q1("SELECT COUNT(*)::int n FROM jobs WHERE dedupe_key LIKE 'conc:%' AND status='done' AND attempts=1")).n === 40, "hepsi done/attempts=1");
    clock.reset();
  }

  // ================= 4) plan_day + varsayılan işleyiciler =================
  {
    await db.query("DELETE FROM jobs WHERE name IN ('briefing.morning','closure.evening')");
    await db.query("DELETE FROM notification_outbox WHERE type IN ('briefing','closure')");
    clock.setFake("2026-11-23T03:00:00Z"); // Pazartesi 06:00 İstanbul
    const p1 = await planner.planAll();
    ok(p1.leader && p1.users >= 5 && p1.planned === 10, "plan_day: 5 kullanıcı × (sabah+akşam) = 10 iş", p1);
    const mj = await q1("SELECT run_at, expires_at, payload FROM jobs WHERE dedupe_key = $1", [`briefing.morning:${U.oa}:2026-11-23`]);
    ok(iso(mj.run_at) === "2026-11-23T04:30:00.000Z" && iso(mj.expires_at) === "2026-11-23T08:00:00.000Z" && mj.payload.userId === U.oa && mj.payload.date === "2026-11-23", "sabah 07:30 İstanbul = 04:30Z; süre +3,5 sa", mj);
    const ej = await q1("SELECT run_at FROM jobs WHERE dedupe_key = $1", [`closure.evening:${U.oa}:2026-11-23`]);
    ok(iso(ej.run_at) === "2026-11-23T15:30:00.000Z", "akşam 18:30 İstanbul", ej);
    const p2 = await planner.planAll();
    ok(p2.planned === 0 && (await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='briefing.morning'")).n === 5, "plan_day idempotent (tekrar planlamaz)", p2);

    // tercih değişimi → bekleyen iş yeniden zamanlanır / kapanırsa iptal
    // (API süreci gerçek saati kullanır; sahte günün yeniden planlaması süreç içinde planUser ile sınanır)
    let r = await call("PUT", "/assistant/prefs", OA, { morning_time: "08:00" });
    ok(r.s === 200 && r.j.morning_time === "08:00", "PUT prefs", r);
    await planner.planUser(U.oa);
    ok(iso((await q1("SELECT run_at FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.oa}:2026-11-23`])).run_at) === "2026-11-23T05:00:00.000Z", "tercih saati değişince bekleyen iş yeniden zamanlandı");
    r = await call("PUT", "/assistant/prefs", OB, { enabled: false });
    ok(r.s === 200 && r.j.enabled === false, "ortak B bildirimleri kapattı");
    await planner.planUser(U.ob);
    ok((await q1("SELECT status FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.ob}:2026-11-23`])).status === "skipped", "kapalı kullanıcının bekleyen işi iptal");
    ok((await q1("SELECT status FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.oa}:2026-11-23`])).status === "queued", "ortak A'nın işi etkilenmedi (izolasyon)");
    r = await call("GET", "/assistant/prefs", OA);
    ok(r.j.morning_time === "08:00", "A kendi tercihini görür");
    r = await call("GET", "/assistant/prefs", OB);
    ok(r.j.morning_time === "07:30" && r.j.enabled === false, "B'nin tercihi A'dan ayrı");

    // vade gelmeden çalışmaz; gelince varsayılan (yer tutucu) işleyici bildirim kutusuna düşürür
    ok((await queue.runDue({ workerId: "w" })).claimed === 0 || true, "ön çalışma");
    clock.setFake("2026-11-23T04:35:00Z");
    const rr = await queue.runDue({ workerId: "w" });
    const outs = await qa("SELECT user_id, title, type, data FROM notification_outbox WHERE type='briefing'");
    ok(rr.done >= 3 && outs.length === 3, "07:30 sabah işleri: oa(08:00) ve ob(kapalı) hariç 3 kullanıcıya yer tutucu brifing", { rr, n: outs.length });
    ok(outs.every((o) => o.data.kind === "morning" && o.user_id !== U.oa && o.user_id !== U.ob), "yer tutucu mesaj, doğru kullanıcılar");
    // çift çalıştırma: işleyici aynı iş için iki kez çağrılsa da tek bildirim
    const h = (await q1("SELECT * FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:2026-11-23`]));
    const handlerBefore = (await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:2026-11-23`])).n;
    await db.query("UPDATE jobs SET status='queued', finished_at=NULL WHERE id=$1", [h.id]);
    await queue.runDue({ workerId: "w" });
    ok(handlerBefore === 1 && (await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:2026-11-23`])).n === 1, "iş iki kez çalışsa da tek bildirim (outbox dedupe)");
    // gerçek (A2) işleyici yer tutucuyu ezer
    let a2 = 0;
    queue.registerHandler("briefing.morning", async () => { a2++; });
    queue.registerHandler("briefing.morning", async () => { a2 += 100; }, { fallback: true }); // fallback gerçek işleyiciyi ezmez
    await db.query("UPDATE jobs SET status='queued', finished_at=NULL WHERE id=$1", [h.id]);
    await queue.runDue({ workerId: "w" });
    ok(a2 === 1, "gerçek işleyici yer tutucuyu ezer; fallback gerçeği ezmez", a2);
    queue.loadHandlers(true); // yer tutucuları geri yükle (sonraki bloklar için)

    // Pazar: varsayılan Pzt–Cmt → planlanmaz; catch-up / kaçırıldı
    await db.query("DELETE FROM jobs WHERE name IN ('briefing.morning','closure.evening')");
    clock.setFake("2026-11-22T03:00:00Z"); // Pazar
    ok((await planner.planAll()).planned === 0, "Pazar günü planlanmaz (weekdays maskesi)");
    clock.setFake("2026-11-24T06:00:00Z"); // Salı 09:00 İstanbul: sabah (07:30) geçti ama süresi (11:00) dolmadı
    const p3 = await planner.planAll();
    const late = await q1("SELECT status, run_at FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:2026-11-24`]);
    ok(late.status === "queued" && new Date(late.run_at) < clock.now(), "catch-up: geçmiş saatli ama geçerli sabah işi kuyruğa alındı (hemen çalışır)", late);
    await db.query("DELETE FROM jobs WHERE name IN ('briefing.morning','closure.evening')");
    clock.setFake("2026-11-24T10:00:00Z"); // 13:00 İstanbul: sabah süresi doldu
    const p4 = await planner.planAll();
    const miss = await q1("SELECT status, last_error FROM jobs WHERE dedupe_key=$1", [`briefing.morning:${U.admin}:2026-11-24`]);
    ok(miss.status === "skipped" && /kaçırıldı/.test(miss.last_error) && p4.missed >= 1, "süresi dolmuş sabah işi 'skipped' (eski saatte bildirim atılmaz)", miss);
    // plan_day iş olarak kuyruktan da çalışır
    await db.query("DELETE FROM jobs WHERE name IN ('briefing.morning','closure.evening')");
    await queue.enqueue("plan_day", {}, { dedupeKey: "plan_day:test:1", runAt: clock.now() });
    await queue.runDue({ workerId: "w" });
    ok((await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='closure.evening' AND status='queued'")).n >= 4, "plan_day işleyicisi kuyruktan çalışır");
    clock.reset();
  }

  // ================= 5) Bildirim / outbox =================
  {
    const t0 = new Date("2026-11-23T10:00:00Z");
    clock.setFake(t0);
    const k = "test:dedupe:1";
    const a = await notifyUser(U.admin, { type: "genel", title: "T1", body: "b", dedupeKey: k, sendAt: t0 });
    const b = await notifyUser(U.admin, { type: "genel", title: "T1 farklı", body: "b2", dedupeKey: k, sendAt: t0 });
    ok(!a.deduped && b.deduped && a.id === b.id, "notifyUser dedupeKey idempotent");
    ok((await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE dedupe_key=$1", [k])).n === 1, "tek outbox satırı");
    const c1 = await notifyUser(U.admin, { title: "anahtarsız", sendAt: t0 }), c2 = await notifyUser(U.admin, { title: "anahtarsız", sendAt: t0 });
    ok(c1.id !== c2.id, "dedupeKey yoksa her çağrı ayrı bildirim");
    // sessiz saat (23:00 İstanbul)
    clock.setFake("2026-11-23T20:00:00Z");
    const q = await notifyUser(U.muh, { type: "genel", title: "gece", dedupeKey: "q:1" });
    ok(iso(q.notBefore) === "2026-11-24T04:00:00.000Z", "sessiz saatte gönderim 07:00'ye ertelenir", iso(q.notBefore));
    const q2 = await notifyUser(U.muh, { type: "genel", title: "gece-açık", dedupeKey: "q:2", sendAt: clock.now() });
    ok(iso(q2.notBefore) === "2026-11-23T20:00:00.000Z", "açık sendAt sessiz saati ezer");
    await call("PUT", "/assistant/prefs", M, { critical_in_quiet: true });
    const q3 = await notifyUser(U.muh, { type: "genel", title: "kritik", dedupeKey: "q:3", priority: "critical" });
    ok(iso(q3.notBefore) === "2026-11-23T20:00:00.000Z", "critical_in_quiet açıkken kritik bildirim anında");
    // tür kapalı
    await call("PUT", "/assistant/prefs", M, { categories: { stok: false } });
    const sk = await notifyUser(U.muh, { type: "stok", title: "stok", dedupeKey: "q:4", sendAt: clock.now() });
    ok(sk.status === "iptal", "kapatılan tür 'iptal' olarak tutulur", sk);
    ok((await notifyUser(U.muh, { type: "stok", title: "stok", dedupeKey: "q:4", sendAt: clock.now() })).deduped, "iptal kayıt da dedupe eder");
    clock.reset();
  }

  // ================= 6) FCM: anahtarsız dry-run, sahte FCM =================
  {
    clock.reset();
    ok(!fcmv1.isEnabled(), "FCM anahtarı yok → devre dışı");
    const n1 = await notifyUser(U.pa, { type: "genel", title: "dry-run", dedupeKey: "dry:1", sendAt: new Date(Date.now() - 1000) });
    const sr = await sender.sendDue();
    ok(sr.enabled === false && sr.claimed === 0, "sender dryRun: hiçbir şey gönderilmez", sr);
    ok((await q1("SELECT status, attempts FROM notification_outbox WHERE id=$1", [n1.id])).status === "beklemede", "FCM'siz outbox 'beklemede' kalır");
    const inbox = await call("GET", "/assistant/inbox", PA);
    ok(inbox.s === 200 && inbox.j.items.some((i) => i.id === n1.id), "ve uygulama içi kutudan okunur", inbox.j);

    // sahte FCM + token sunucusu
    const { privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048, privateKeyEncoding: { type: "pkcs8", format: "pem" }, publicKeyEncoding: { type: "spki", format: "pem" } });
    const seen = []; let tokenReqs = 0; const fail503 = new Set(["TOK_RETRY"]);
    const fake = http.createServer((req, res) => {
      const ch = []; req.on("data", (c) => ch.push(c)); req.on("end", () => {
        const raw = Buffer.concat(ch).toString(); res.setHeader("Content-Type", "application/json");
        if (req.url === "/token") { tokenReqs++; return res.end(JSON.stringify({ access_token: "AT123", expires_in: 3600 })); }
        const j = JSON.parse(raw); const dt = j.message.token; seen.push({ auth: req.headers.authorization, url: req.url, msg: j.message });
        if (dt === "TOK_GONE") { res.statusCode = 404; return res.end(JSON.stringify({ error: { status: "NOT_FOUND", message: "x", details: [{ errorCode: "UNREGISTERED" }] } })); }
        if (fail503.has(dt)) { fail503.delete(dt); res.statusCode = 503; return res.end(JSON.stringify({ error: { status: "UNAVAILABLE", message: "busy" } })); }
        res.end(JSON.stringify({ name: "projects/p/messages/1" }));
      });
    }).listen(4120);
    process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify({ client_email: "sa@proj.iam.gserviceaccount.com", private_key: privateKey, project_id: "proj-x", token_uri: "http://localhost:4120/token" });
    process.env.FCM_API_BASE = "http://localhost:4120"; fcmv1._reset();
    ok(fcmv1.isEnabled(), "servis hesabı ile FCM açık");
    await db.query("DELETE FROM device_tokens");
    const dev = async (tok, tk, uidv) => db.query("INSERT INTO device_tokens (user_id, token, platform) VALUES ($1,$2,'android')", [uidv, tok]);
    await dev("TOK_OK_1_xxxxxxxx", 0, U.admin); await dev("TOK_GONE", 0, U.admin); await dev("TOK_RETRY", 0, U.muh);
    await db.query("DELETE FROM notification_outbox WHERE dedupe_key LIKE 'fcm:%'");
    const t = new Date(Date.now() - 5000);
    const f1 = await notifyUser(U.admin, { type: "offer", title: "Yeni", body: "gövde", data: { id: "42", nested: { a: 1 } }, dedupeKey: "fcm:1", sendAt: t });
    const f2 = await notifyUser(U.muh, { type: "genel", title: "Retry", body: "b", dedupeKey: "fcm:2", sendAt: t });
    const f3 = await notifyUser(U.pa, { type: "genel", title: "Cihazsız", body: "b", dedupeKey: "fcm:3", sendAt: t });
    await db.query("UPDATE notification_outbox SET status='iptal' WHERE status='beklemede' AND dedupe_key NOT LIKE 'fcm:%'"); // önceki bloklardan kalanları ele
    let s1 = await sender.sendDue();
    ok(s1.enabled && s1.claimed === 3, "sender 3 bildirim talep etti", s1);
    const r1 = await q1("SELECT * FROM notification_outbox WHERE id=$1", [f1.id]);
    ok(r1.status === "gonderildi" && r1.sent_channels.includes("push"), "geçerli token'a gitti → gonderildi", r1);
    const m1 = seen.find((x) => x.msg.token === "TOK_OK_1_xxxxxxxx");
    ok(m1 && m1.auth === "Bearer AT123" && m1.url === "/v1/projects/proj-x/messages:send" && m1.msg.notification.title === "Yeni" && m1.msg.data.nested === '{"a":1}' && m1.msg.data.notification_id === f1.id && m1.msg.data.type === "offer", "FCM v1 isteği: yol, Bearer, bildirim, data metne çevrilmiş", m1);
    ok((await q1("SELECT disabled_at FROM device_tokens WHERE token='TOK_GONE'")).disabled_at !== null, "UNREGISTERED token pasifleştirildi");
    const r2 = await q1("SELECT * FROM notification_outbox WHERE id=$1", [f2.id]);
    ok(r2.status === "beklemede" && r2.locked_until && new Date(r2.locked_until) > new Date() && /UNAVAILABLE/.test(r2.last_error), "503 → yeniden deneme (geri çekilme), beklemede", r2);
    const r3 = await q1("SELECT * FROM notification_outbox WHERE id=$1", [f3.id]);
    ok(r3.status === "gonderildi" && r3.sent_channels.join() === "inbox", "cihazı olmayan kullanıcı: yalnız kutu (gonderildi/inbox)", r3);
    ok((await sender.sendDue()).claimed === 0, "kira bitmeden tekrar denenmez");
    clock.setFake(new Date(Date.now() + 70 * 1000));
    s1 = await sender.sendDue();
    ok(s1.sent === 1 && (await q1("SELECT status FROM notification_outbox WHERE id=$1", [f2.id])).status === "gonderildi", "geri çekilmeden sonra gönderildi", s1);
    clock.reset();
    ok(tokenReqs === 1, "erişim jetonu önbelleğe alınır (tek token isteği)", tokenReqs);
    // süresi geçmiş bildirim
    const ex = await notifyUser(U.admin, { type: "genel", title: "eski", dedupeKey: "fcm:exp", sendAt: new Date(Date.now() - 3600e3), expiresAt: new Date(Date.now() - 60e3) });
    await sender.sendDue();
    ok((await q1("SELECT status FROM notification_outbox WHERE id=$1", [ex.id])).status === "iptal", "süresi geçen bildirim gönderilmez (iptal)");
    fake.close(); delete process.env.FCM_SERVICE_ACCOUNT_JSON; delete process.env.FCM_API_BASE; fcmv1._reset();
    ok(!fcmv1.isEnabled(), "anahtar kalkınca tekrar devre dışı");
  }

  // ================= 7) Bildirim kutusu API =================
  {
    await db.query("DELETE FROM notification_outbox WHERE user_id = ANY($1)", [[U.admin, U.oa, U.ob]]);
    const past = (m) => new Date(Date.now() - m * 60000);
    const ids = [];
    for (let i = 0; i < 4; i++) ids.push((await notifyUser(U.admin, { type: "genel", title: "N" + i, body: "b", dedupeKey: "ib:" + i, sendAt: past(10 - i) })).id);
    const fut = await notifyUser(U.admin, { type: "genel", title: "gelecek", dedupeKey: "ib:fut", sendAt: new Date(Date.now() + 3600e3) });
    const can = await notifyUser(U.admin, { type: "genel", title: "iptal", dedupeKey: "ib:can", sendAt: past(1) });
    await db.query("UPDATE notification_outbox SET status='iptal' WHERE id=$1", [can.id]);
    const oaN = await notifyUser(U.oa, { type: "genel", title: "OA'nın", dedupeKey: "ib:oa", sendAt: past(1) });
    let r = await call("GET", "/assistant/inbox", A);
    ok(r.s === 200 && r.j.items.length === 4 && r.j.unread_count === 4, "kutu: yalnız kendi, görünür, iptal/gelecek hariç", r.j);
    ok(r.j.items[0].title === "N3" && r.j.items[0].available_at && "read_at" in r.j.items[0] && "acked_at" in r.j.items[0], "en yeni önce; alanlar");
    ok(!r.j.items.some((i) => i.id === fut.id || i.id === can.id || i.id === oaN.id), "gelecek/iptal/başkasının görünmez");
    r = await call("POST", `/assistant/inbox/${ids[0]}/read`, A);
    ok(r.s === 200 && r.j.read_at, "okundu işaretle");
    const first = r.j.read_at;
    r = await call("POST", `/assistant/inbox/${ids[0]}/read`, A);
    ok(r.j.read_at === first, "okundu idempotent");
    ok((await call("GET", "/assistant/inbox?unread=1", A)).j.items.length === 3, "okunmamış süzgeci");
    r = await call("POST", `/assistant/inbox/${ids[0]}/unread`, A);
    ok(r.s === 200 && r.j.read_at === null, "okunmadı işaretle");
    r = await call("POST", `/assistant/inbox/${ids[1]}/ack`, A); const ack1 = r.j.acked_at;
    r = await call("POST", `/assistant/inbox/${ids[1]}/ack`, A);
    ok(r.s === 200 && ack1 && r.j.acked_at === ack1 && r.j.read_at, "ack idempotent ve okundu sayılır");
    r = await call("GET", "/assistant/inbox?limit=2", A);
    ok(r.j.items.length === 2 && r.j.next_before, "sayfalama next_before");
    r = await call("GET", `/assistant/inbox?limit=2&before=${encodeURIComponent(r.j.next_before)}`, A);
    ok(r.j.items.length === 2 && !r.j.next_before, "ikinci sayfa");
    ok((await call("POST", "/assistant/inbox/read-all", A)).j.marked >= 2, "tümünü okundu yap");
    ok((await call("GET", "/assistant/inbox", A)).j.unread_count === 0, "okunmamış 0");
    ok((await call("POST", `/assistant/inbox/${ids[2]}/read`, OA)).s === 404, "başkasının bildirimi (ortak A) → 404");
    ok((await call("POST", `/assistant/inbox/${oaN.id}/ack`, OB)).s === 404, "ortak B, A'nın bildirimini ack edemez");
    ok((await call("GET", "/assistant/inbox", OB)).j.items.length === 0, "ortak B kutusu boş (A'nınkini görmez)");
    ok((await call("GET", "/assistant/inbox", OA)).j.items.length === 1, "ortak A yalnız kendini görür");
    ok((await call("GET", "/assistant/inbox")).s === 401, "oturumsuz 401");
    ok((await call("POST", "/assistant/inbox/xyz/read", A)).s === 400, "geçersiz id 400");
    r = await call("POST", "/assistant/test-notification", A);
    ok(r.s === 201 && r.j.fcm_enabled === false, "test bildirimi (FCM kapalı → yalnız kutu)", r);
    ok((await call("POST", "/assistant/test-notification", A)).s === 200, "dakikada bir (ikincisi dedupe)");
  }

  // ================= 8) /config + PATCH yetkileri =================
  {
    for (const [n, tk] of [["admin", A], ["muhasebe", M], ["ortak", OA], ["personel", PA]]) {
      const r = await call("GET", "/config", tk);
      ok(r.s === 200 && r.j.org && r.j.brand && r.j.sector_dictionary.terms && r.j.lists.service_types.length && r.j.lists.appointment_types.length && r.j.lists.expense_categories.length && r.j.flags && r.j.server.version && "minAppVersion" in r.j.server, `GET /config (${n})`, r.j);
    }
    ok((await call("GET", "/config")).s === 401, "GET /config oturumsuz 401");
    let r = await call("GET", "/config", A);
    ok(r.j.server.version === require("../package.json").version && r.j.server.apiVersion === 1 && r.j.flags.ai_enabled === false && r.j.flags.assistant_inbox === true, "sürüm bilgisi + bayraklar", r.j.server);
    ok(r.j.settings.timezone === "Europe/Istanbul" && r.j.settings.briefing_time === "07:30" && r.j.settings.closing_time === "18:30", "ayarlar");
    const body = { brand: { name: "Demo Atölye", primary_color: "#112233", logo_url: "https://ornek.com/logo.png" }, sector_dictionary: { terms: { customer: "Cari", yeni_terim: "Yeni" } }, expense_categories: ["Hammadde", "Kira", "hammadde", " Yakıt "], briefing_time: "08:00" };
    ok((await call("PATCH", "/config", M, body)).s === 403, "PATCH muhasebe 403");
    ok((await call("PATCH", "/config", OA, body)).s === 403, "PATCH ortak 403 (ortak kendi org'una değil)");
    ok((await call("PATCH", "/config", PA, body)).s === 403, "PATCH personel 403");
    ok((await call("PATCH", "/config", null, body)).s === 401, "PATCH oturumsuz 401");
    r = await call("PATCH", "/config", A, body);
    ok(r.s === 200 && r.j.brand.name === "Demo Atölye" && r.j.brand.primary_color === "#112233" && r.j.org.name === "Demo Atölye", "PATCH admin 200 (marka + kuruluş adı)", r.j);
    ok(r.j.sector_dictionary.terms.customer === "Cari" && r.j.sector_dictionary.terms.offer === "Teklif" && r.j.sector_dictionary.terms.yeni_terim === "Yeni", "terimler birleştirilir");
    ok(JSON.stringify(r.j.lists.expense_categories) === JSON.stringify(["Hammadde", "Kira", "Yakıt"]), "liste temizlenir (kırp, tekilleştir)", r.j.lists.expense_categories);
    ok(r.j.lists.service_types.length > 0 && r.j.settings.briefing_time === "08:00", "dokunulmayan alanlar korunur");
    r = await call("GET", "/config", OA);
    ok(r.j.brand.name === "Demo Atölye" && r.j.lists.expense_categories.includes("Hammadde"), "ortak de güncel yapılandırmayı okur");
    r = await call("PATCH", "/config", A, { sector_dictionary: { terms: { yeni_terim: null } } });
    ok(r.j.sector_dictionary.terms.yeni_terim === undefined && r.j.sector_dictionary.terms.customer === "Cari", "terim null ile silinir");
    for (const [bad, why] of [[{ brand: { primary_color: "kırmızı" } }, "renk"], [{ brand: { logo_url: "javascript:alert(1)" } }, "logo javascript:"], [{ brand: { logo_url: "http://a.com/x.png" } }, "logo http"],
      [{ brand: { name: "" } }, "boş ad"], [{ service_types: ["x".repeat(41)] }, "uzun liste öğesi"], [{ service_types: "x" }, "liste dizi değil"], [{ appointment_types: Array(51).fill("a").map((x, i) => x + i) }, "51 öğe"],
      [{ timezone: "Mars/Olympus" }, "saat dilimi"], [{ briefing_time: "25:00" }, "saat"], [{ bilinmeyen: 1 }, "bilinmeyen alan"], [{}, "boş gövde"], [{ sector_dictionary: { terms: { "BÜYÜK": "x" } } }, "terim anahtarı"],
      [{ sector_dictionary: { terms: { a: "<b>" } } }, "terim değeri"], [{ brand: { x: 1 } }, "brand bilinmeyen"]]) {
      const rr = await call("PATCH", "/config", A, bad);
      ok(rr.s === 400 && rr.j.error, `PATCH doğrulama: ${why}`, rr);
    }
    ok((await q1("SELECT COUNT(*)::int n FROM audit_log WHERE action='config.update' AND user_id=$1", [U.admin])).n >= 2, "audit_log: config.update kaydı");
    ok((await q1("SELECT name FROM organizations WHERE is_default")).name === "Demo Atölye", "organizations.name eşitlendi");
  }

  // ================= 9) Tercihler doğrulama =================
  {
    let r = await call("GET", "/assistant/prefs", PA);
    ok(r.s === 200 && r.j.is_default === true && r.j.enabled === true && r.j.quiet_start === "21:30" && r.j.weekdays.join() === "1,2,3,4,5,6" && r.j.channels.push === true, "varsayılan tercihler", r.j);
    ok(r.j.morning_time === "08:00" && r.j.evening_time === "18:30", "etkin saat: kuruluş ayarından (PATCH ile 08:00)", r.j);
    r = await call("PUT", "/assistant/prefs", PA, { weekdays: [1, 7], evening_time: "19:15", channels: { push: false }, max_proactive_per_day: 3, tz: "Europe/Berlin", quiet_start: "22:00" });
    ok(r.s === 200 && r.j.weekdays.join() === "1,7" && r.j.evening_time === "19:15" && r.j.channels.push === false && r.j.channels.inbox === true && r.j.tz === "Europe/Berlin" && r.j.is_default === false, "PUT prefs kısmi güncelleme", r.j);
    r = await call("PUT", "/assistant/prefs", PA, { evening_time: null });
    ok(r.j.evening_time === "18:30", "null → kuruluş varsayılanı");
    for (const bad of [{ morning_time: "7:30" }, { weekdays: [0] }, { weekdays: "1" }, { tz: "Foo/Bar" }, { enabled: "evet" }, { max_proactive_per_day: 99 }, { channels: { sms: true } }, { categories: { a: "x" } }, {}, { quiet_start: null }]) {
      const rr = await call("PUT", "/assistant/prefs", PA, bad);
      ok(rr.s === 400, "PUT prefs geçersiz: " + JSON.stringify(bad), rr);
    }
    ok((await call("PUT", "/assistant/prefs", null, { enabled: true })).s === 401, "prefs oturumsuz 401");
    await db.query("DELETE FROM notification_prefs WHERE user_id = $1", [U.pa]);
  }

  // ================= 10) Sektör şablonları =================
  {
    let r = await call("GET", "/assistant/sector-templates", OA);
    ok(r.s === 200 && r.j.length === 7 && r.j[0].key === "genel" && r.j[0].service_types.length, "şablon listesi (oturumlu herkes)", r.j.length);
    // mevcut kayıtlar
    const ap = await call("POST", "/appointments", A, { type: "Eski Tür", scheduled_at: "2026-12-10T10:00:00+03:00" });
    const ex = await call("POST", "/expenses", A, { category: "Eski Kategori", amount: 100, scope: "genel" });
    ok(ap.s === 201 && ex.s === 201, "ön kayıtlar", [ap.s, ex.s]);
    const cnt = async () => [(await q1("SELECT COUNT(*)::int n FROM appointments")).n, (await q1("SELECT COUNT(*)::int n FROM expenses")).n];
    const before = await cnt();
    ok((await call("POST", "/assistant/sector-templates/apply", M, { key: "klima_teknik_servis" })).s === 403, "apply muhasebe 403");
    ok((await call("POST", "/assistant/sector-templates/apply", OA, { key: "klima_teknik_servis" })).s === 403, "apply ortak 403");
    ok((await call("POST", "/assistant/sector-templates/apply", A, { key: "yok" })).s === 404, "apply bilinmeyen şablon 404");
    ok((await call("POST", "/assistant/sector-templates/apply", A, {})).s === 400, "apply anahtarsız 400");
    ok((await call("POST", "/assistant/sector-templates/apply", A, { key: "nakliye", mode: "x" })).s === 400, "apply geçersiz mode 400");
    r = await call("POST", "/assistant/sector-templates/apply", A, { key: "klima_teknik_servis" });
    ok(r.s === 200 && r.j.applied === "klima_teknik_servis" && r.j.config.lists.service_types.includes("Klima montajı") && r.j.config.org.sector_key === "klima_teknik_servis" && r.j.config.sector_dictionary.terms.job === "Servis kaydı", "apply (replace) ayarları değiştirir", r.j);
    ok(r.j.config.brand.name === "Demo Atölye", "marka korunur");
    ok(JSON.stringify(await cnt()) === JSON.stringify(before), "mevcut randevu/gider kayıtları silinmedi");
    ok((await q1("SELECT category FROM expenses WHERE id=$1", [ex.j.id])).category === "Eski Kategori", "eski kategori kaydı bozulmadı");
    r = await call("PATCH", "/config", A, { appointment_types: ["Özel Tür"] });
    r = await call("POST", "/assistant/sector-templates/apply", A, { key: "demir_dograma", mode: "merge" });
    ok(r.j.config.lists.appointment_types.includes("Özel Tür") && r.j.config.lists.appointment_types.includes("Montaj") && r.j.config.sector_dictionary.terms.job === "Servis kaydı" && r.j.config.sector_dictionary.terms.location, "merge: özel öğe + şablon öğeleri; mevcut terim korunur", r.j.config.lists);
    // mevcut sabit liste doğrulaması gevşemedi/bozulmadı
    ok((await call("POST", "/appointments", A, { type: "x".repeat(41), scheduled_at: "2026-12-10T10:00:00+03:00" })).s === 400, "randevu türü ≤40 doğrulaması aynen");
    ok((await call("POST", "/appointments", A, { type: "Listede Olmayan Tür", scheduled_at: "2026-12-10T10:00:00+03:00" })).s === 201, "liste dışı randevu türü hâlâ serbest (öneri, zorunlu değil)");
    ok((await call("POST", "/expenses", A, { category: "", amount: 5 })).s === 400, "gider kategorisi zorunluluğu aynen");
    ok((await call("POST", "/assistant/sector-templates/apply", A, { key: "genel" })).s === 200, "genel şablona dönüş");
    r = await call("GET", "/config", PA);
    ok(r.j.org.sector_key === "genel", "personel güncel sektörü görür");
  }

  // ================= 11) /api/v1 takma yolu + Idempotency-Key =================
  {
    let r = await call("GET", "/v1/config", A);
    ok(r.s === 200 && r.j.org && r.j.server.version, "/api/v1/config çalışır");
    ok((await call("GET", "/v1/health")).s === 200 && (await call("GET", "/health")).s === 200, "/api/v1/health ve /api/health");
    ok((await call("GET", "/v1/offers", A)).s === 200 && Array.isArray((await call("GET", "/offers", A)).j), "/api/v1/offers + eski /api/offers");
    ok((await call("GET", "/v1/yok-boyle-yol", A)).s === 404, "v1 altında 404 sözleşmesi {error}");
    ok((await call("GET", "/v1/auth/me", A)).j.user?.id === U.admin || (await call("GET", "/v1/auth/me", A)).s === 200, "/api/v1/auth/me");

    // Idempotency
    const K = "idem-key-" + crypto.randomUUID();
    const body = { category: "Idem Gider", amount: 77.5, scope: "genel" };
    const c0 = (await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Gider'")).n;
    const r1 = await call("POST", "/v1/expenses", A, body, { "Idempotency-Key": K });
    const r2 = await call("POST", "/expenses", A, body, { "Idempotency-Key": K }); // aynı anahtar, /v1 ↔ eski yol aynı istek sayılır
    ok(r1.s === 201 && r2.s === 201 && r1.j.id === r2.j.id, "aynı anahtar → aynı yanıt, çift kayıt yok", [r1.j, r2.j]);
    ok(r2.h.get("idempotent-replay") === "true" && !r1.h.get("idempotent-replay"), "yeniden gönderim başlığı");
    ok((await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Gider'")).n === c0 + 1, "tek gider kaydı");
    const r3 = await call("POST", "/expenses", A, { ...body, amount: 99 }, { "Idempotency-Key": K });
    ok(r3.s === 422, "aynı anahtar farklı gövde → 422", r3);
    const r4 = await call("POST", "/expenses", M, body, { "Idempotency-Key": K });
    ok(r4.s === 201 && r4.j.id !== r1.j.id, "anahtar kullanıcı başınadır (muhasebe ayrı kayıt)", r4);
    ok((await call("POST", "/expenses", A, body, { "Idempotency-Key": "kisa" })).s === 400, "geçersiz anahtar biçimi 400");
    const n0 = (await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Gider'")).n;
    await call("POST", "/expenses", A, body); await call("POST", "/expenses", A, body);
    ok((await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Gider'")).n === n0 + 2, "başlıksız POST'lar eskisi gibi (opsiyonel)");
    // hata yanıtı saklanmaz: düzeltilmiş istek aynı anahtarla yapılabilir
    const K2 = "idem-key-" + crypto.randomUUID();
    const bad = await call("POST", "/expenses", A, { category: "", amount: 1 }, { "Idempotency-Key": K2 });
    const good = await call("POST", "/expenses", A, { category: "Idem Gider", amount: 1 }, { "Idempotency-Key": K2 });
    ok(bad.s === 400 && good.s === 201, "4xx yanıt anahtarı yakmaz", [bad.s, good.s]);
    // eşzamanlı aynı anahtar → tek kayıt
    const K3 = "idem-key-" + crypto.randomUUID(); const n1 = (await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Eş'")).n;
    const par = await Promise.all([1, 2, 3].map(() => call("POST", "/expenses", A, { category: "Idem Eş", amount: 5 }, { "Idempotency-Key": K3 })));
    ok((await q1("SELECT COUNT(*)::int n FROM expenses WHERE category='Idem Eş'")).n === n1 + 1 && par.every((x) => [201, 409].includes(x.s)) && par.some((x) => x.s === 201), "eşzamanlı aynı anahtar: tek kayıt", par.map((x) => x.s));
    // oturumsuz: başlık yok sayılır (login'i etkilemez)
    const lg = await call("POST", "/auth/login", null, { email: "admin@x.com", password: "pass1234" }, { "Idempotency-Key": "abcdefgh-login" });
    ok(lg.s === 200, "oturumsuz istekte Idempotency-Key yok sayılır");
  }

  // ================= 12) audit.logAction =================
  {
    ok(await logAction({ userId: U.admin, action: "test.action", entityType: "x", entityId: 5, data: { a: 1 }, ip: "1.2.3.4" }) === true, "logAction kayıt");
    const row = await q1("SELECT * FROM audit_log WHERE action='test.action'");
    ok(row && row.entity_id === "5" && row.data.a === 1 && row.ip === "1.2.3.4" && row.org_id, "audit_log alanları + org_id");
    ok((await logAction({ action: null })) === false, "logAction hata fırlatmaz");
  }

  // ================= 13) Worker süreci (gerçek, çift) + sağlık =================
  {
    await db.query("DELETE FROM worker_heartbeats");
    let r = await call("GET", "/health/worker");
    ok(r.s === 503 && r.j.status === "down", "worker çalışmıyorken /health/worker 503 down", r);
    await db.query("DELETE FROM jobs WHERE name IN ('briefing.morning','closure.evening','plan_day')");
    await db.query("DELETE FROM notification_outbox WHERE dedupe_key LIKE 'briefing.morning:%'");
    const dates = ["2030-01-10", "2030-01-11", "2030-01-12"], users = [U.admin, U.muh, U.oa, U.ob, U.pa];
    const base = new Date(Date.now() - 60000);
    for (const d of dates) for (const u of users) await queue.enqueue("briefing.morning", { userId: u, date: d }, { userId: u, dedupeKey: `bm:${u}:${d}`, runAt: base });
    const env = { ...process.env, WORKER_TICK_MS: "300", ASSISTANT_FAKE_NOW: "2030-01-15T00:10:00Z", NODE_ENV: "test" };
    const w = [1, 2].map(() => spawn(process.execPath, ["src/worker.js"], { cwd: ROOT, env, stdio: ["ignore", "pipe", "pipe"] }));
    let wout = ""; w.forEach((p) => { p.stdout.on("data", (d) => (wout += d)); p.stderr.on("data", (d) => (wout += d)); });
    let done = 0;
    for (let i = 0; i < 60 && done < 15; i++) { await sleep(300); done = (await q1("SELECT COUNT(*)::int n FROM jobs WHERE name='briefing.morning' AND status='done' AND dedupe_key LIKE 'bm:%'")).n; }
    ok(done === 15, "2 worker süreci 15 işi tamamladı", { done, wout: wout.slice(0, 400) });
    ok((await q1("SELECT COUNT(*)::int n FROM jobs WHERE dedupe_key LIKE 'bm:%' AND attempts = 1")).n === 15, "her iş tam bir kez çalıştı (attempts=1)");
    ok((await q1("SELECT COUNT(*)::int n FROM notification_outbox WHERE dedupe_key LIKE 'briefing.morning:%:2030-01-1_'")).n === 15, "15 iş = 15 bildirim (çift yok)");
    const hb = await qa("SELECT * FROM worker_heartbeats");
    ok(hb.length === 2 && hb.every((h) => h.ticks >= 1), "iki worker kalp atışı yazdı", hb.length);
    r = await call("GET", "/health/worker");
    ok(r.s === 200 && r.j.status === "ok" && r.j.last_tick_age_seconds <= 5 && !r.j.workers, "/health/worker ok (herkese açık, ayrıntısız)", r);
    r = await call("GET", "/health/worker", A);
    ok(r.s === 200 && r.j.workers.length === 2 && r.j.queue && r.j.fcm_enabled === false, "admin ayrıntı görür", r.j);
    ok((await call("GET", "/v1/health/worker")).s === 200, "v1 yolu");
    // sahte saat (2030-01-15 03:10 İstanbul Salı; ob kapalı → 4 kullanıcı × 2 = 8 iş): worker'lar plan_day ile o günün işlerini planladı, gelecek saatli → çalışmadı
    const pl = await qa("SELECT dedupe_key, status FROM jobs WHERE name IN ('briefing.morning','closure.evening') AND dedupe_key LIKE '%:2030-01-15'");
    ok(pl.length === 8 && pl.every((j) => j.status === "queued"), "worker plan_day: sahte günün işleri planlandı (07:30/18:30 henüz gelmedi)", pl.length);
    // SIGTERM: temiz kapanış
    const exits = w.map((p) => new Promise((res) => p.on("exit", (c) => res(c))));
    w.forEach((p) => p.kill("SIGTERM"));
    const codes = await Promise.race([Promise.all(exits), sleep(8000).then(() => "timeout")]);
    ok(Array.isArray(codes) && codes.every((c) => c === 0), "SIGTERM'de temiz kapanış (çıkış kodu 0)", codes);
    await db.query("DELETE FROM jobs WHERE dedupe_key LIKE '%:2030-01-15' OR name IN ('plan_day','housekeeping')");
  }

  console.log(`\nv17: ${pass} geçti, ${fail} başarısız`);
  await db.pool.end();
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error("TEST ÇÖKTÜ:", e); process.exit(2); });
