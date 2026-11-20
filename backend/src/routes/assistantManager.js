/**
 * Asistan — Müdür / brifing / akşam kapanış / insight / hatırlatma uçları (v20). /api/assistant altına, assistant.js'e EK router olarak bağlanır.
 * Sözleşme: mobile-api-contract-A2.md. Hata biçimi: {"error":"Türkçe mesaj"}.
 */
const express = require("express");
const db = require("../db");
const { requireAuth, requireRole } = require("../middleware/auth");
const clock = require("../assistant/clock");
const { orgIdForUser } = require("../assistant/org");
const { logAction } = require("../assistant/audit");
const store = require("../assistant/briefing/store");
const morning = require("../assistant/briefing/morning");
const closure = require("../assistant/closure/service");
const { engine } = require("../assistant/manager");
const reminderSvc = require("../assistant/reminders/service");
const followupsFacts = require("../assistant/facts/followups");
const facts = require("../assistant/facts");

const router = express.Router();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isGlobal = (u) => u.role === "admin" || u.role === "muhasebe";
const asUser = (u) => ({ id: u.id, name: u.name, role: u.role });
const bad = (res, msg, code = 400) => res.status(code).json({ error: msg });
const KINDS = ["morning", "weekly", "monthly", "evening"];

function paramId(req, res) {
  if (!UUID.test(req.params.id)) { bad(res, "Geçersiz kimlik."); return null; }
  return req.params.id;
}

// ---- brifingler ------------------------------------------------------------------------------------------
/** GET /briefing/today[?refresh=1] — bugünün sabah brifingi; henüz üretilmediyse (08:00 öncesi/kaçırıldı) anında üretilir (bildirimden bağımsız, canlı) */
router.get("/briefing/today", requireAuth, async (req, res) => {
  const date = clock.istanbulDateStr();
  const refresh = req.query.refresh === "1" || req.query.refresh === "true";
  let b = await store.get(req.user.id, "morning", date);
  let live = false;
  if (!b || refresh) {
    const orgId = await orgIdForUser(req.user.id);
    const built = await morning.build(asUser(req.user), { date, orgId });
    b = await store.save({ orgId, userId: req.user.id, kind: "morning", periodStart: date, title: built.title, bodyText: built.bodyText, data: built.data, generatedBy: "on_demand" });
    live = true;
  }
  res.json({ ...b, live });
});

/** GET /briefings?type=morning|weekly|monthly|evening&limit=20 */
router.get("/briefings", requireAuth, async (req, res) => {
  const type = req.query.type;
  if (type !== undefined && !KINDS.includes(type)) return bad(res, `type şunlardan biri olmalı: ${KINDS.join(", ")}.`);
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 20, 1), 100);
  res.json({ items: await store.list(req.user.id, { kind: type, limit }) });
});

router.post("/briefings/:id/read", requireAuth, async (req, res) => {
  const id = paramId(req, res); if (!id) return;
  const b = await store.markRead(req.user.id, id);
  if (!b) return bad(res, "Brifing bulunamadı.", 404);
  res.json(b);
});

// ---- akşam kapanış ---------------------------------------------------------------------------------------
router.get("/closure/today", requireAuth, async (req, res) => {
  const orgId = await orgIdForUser(req.user.id);
  res.json(await closure.getToday(asUser(req.user), { date: clock.istanbulDateStr(), orgId, refresh: req.query.refresh === "1" }));
});

router.post("/closure/answers", requireAuth, async (req, res) => {
  const orgId = await orgIdForUser(req.user.id);
  let r;
  try { r = await closure.submit(asUser(req.user), req.body, { orgId }); }
  catch (e) { if (e.status === 403) return bad(res, e.message, 403); throw e; }
  if (r.error) return bad(res, r.error);
  await logAction({ req, orgId, action: "closure.answers", entityType: "daily_log", entityId: r.log.date, data: { applied: r.applied.length, proposals: r.closure_proposals.length } });
  res.json(r);
});

// ---- insight'lar (müdür) — admin / muhasebe / ortak (kapsam: işletme | yalnız kendi) -------------------------------
const insightRoles = requireRole("admin", "muhasebe", "ortak");
const STATUSES = ["acik", "ertelendi", "kapatildi", "uygulandi", "all"];

router.get("/insights", requireAuth, insightRoles, async (req, res) => {
  const status = req.query.status || "acik";
  if (!STATUSES.includes(status)) return bad(res, `status şunlardan biri olmalı: ${STATUSES.join(", ")}.`);
  if (req.query.severity !== undefined && !["info", "warn", "critical"].includes(req.query.severity)) return bad(res, "severity info|warn|critical olmalı.");
  const orgId = await orgIdForUser(req.user.id);
  const items = await engine.list(req.user, orgId, { status, severity: req.query.severity, limit: req.query.limit });
  res.json({ items, count: items.length });
});

router.post("/insights/refresh", requireAuth, insightRoles, async (req, res) => {
  const orgId = await orgIdForUser(req.user.id);
  const sk = engine.scopeKeyForUser(req.user);
  const s = await engine.refresh(orgId, sk);
  res.json({ scope: sk, created: s.created, updated: s.updated, reopened: s.reopened, closed: s.closed, rules: s.rules });
});

async function withInsight(req, res, fn) {
  const id = paramId(req, res); if (!id) return;
  const orgId = await orgIdForUser(req.user.id);
  const row = await engine.loadVisible(req.user, orgId, id);
  if (!row) return bad(res, "Öneri bulunamadı.", 404);
  return fn(row, orgId);
}
router.get("/insights/:id", requireAuth, insightRoles, (req, res) => withInsight(req, res, async (row) => res.json(engine.present(row))));
router.post("/insights/:id/snooze", requireAuth, insightRoles, (req, res) => withInsight(req, res, async (row) => {
  const { days, until } = req.body || {};
  if (until !== undefined) {
    const u = new Date(until);
    if (Number.isNaN(u.getTime()) || u <= clock.now() || u > new Date(clock.now().getTime() + 365 * 86400000)) return bad(res, "until gelecekte, en çok 1 yıl sonrası geçerli bir ISO tarih olmalı.");
    return res.json(await engine.snooze(row, { until: u }));
  }
  if (!Number.isInteger(days) || days < 1 || days > 90) return bad(res, "days (1–90 tam sayı) ya da until gerekli.");
  res.json(await engine.snooze(row, { days }));
}));
router.post("/insights/:id/dismiss", requireAuth, insightRoles, (req, res) => withInsight(req, res, async (row) => res.json(await engine.dismiss(row))));
router.post("/insights/:id/applied", requireAuth, insightRoles, (req, res) => withInsight(req, res, async (row) => res.json(await engine.markApplied(row))));
router.post("/insights/:id/feedback", requireAuth, insightRoles, (req, res) => withInsight(req, res, async (row) => {
  const { verdict, note } = req.body || {};
  if (!["yanlis", "alakasiz", "yararli"].includes(verdict)) return bad(res, "verdict yanlis | alakasiz | yararli olmalı.");
  if (note !== undefined && note !== null && (typeof note !== "string" || note.length > 500)) return bad(res, "note en çok 500 karakter olmalı.");
  res.json(await engine.feedback(row, verdict, note));
}));

// ---- kural yapılandırması (yalnız admin) ---------------------------------------------------------------------------
router.get("/insight-rules", requireAuth, requireRole("admin"), async (req, res) => res.json(await engine.rulesView(await orgIdForUser(req.user.id))));
router.put("/insight-rules", requireAuth, requireRole("admin"), async (req, res) => {
  const orgId = await orgIdForUser(req.user.id);
  const r = await engine.saveRules(orgId, req.user.id, req.body);
  if (r.error) return bad(res, r.error);
  await logAction({ req, orgId, action: "insight_rules.update", entityType: "org", entityId: orgId, data: { body: req.body } });
  res.json(await engine.rulesView(orgId));
});

// ---- hatırlatma: ertele / tamamla --------------------------------------------------------------------------------
async function loadReminder(req, res) {
  const id = paramId(req, res); if (!id) return null;
  const { rows } = await db.query("SELECT * FROM reminders WHERE id = $1", [id]);
  if (!rows[0]) { bad(res, "Hatırlatıcı bulunamadı.", 404); return null; }
  if (!isGlobal(req.user) && String(rows[0].owner_id) !== String(req.user.id)) { bad(res, "Bu hatırlatıcı size ait değil.", 403); return null; }
  return rows[0];
}
/** POST /reminders/:id/snooze {preset: "15m"|"1h"|"tomorrow"} ya da {minutes: 5–1440} */
router.post("/reminders/:id/snooze", requireAuth, async (req, res) => {
  const r = await loadReminder(req, res); if (!r) return;
  const b = req.body || {};
  const preset = b.preset !== undefined ? b.preset : b.minutes;
  if (preset === undefined) return bad(res, "preset (15m | 1h | tomorrow) ya da minutes (5–1440) gerekli.");
  const out = await reminderSvc.snooze(r, preset);
  if (out.error) return bad(res, out.error, out.status || 400);
  res.json(out.reminder);
});
router.post("/reminders/:id/complete", requireAuth, async (req, res) => {
  const r = await loadReminder(req, res); if (!r) return;
  const out = await reminderSvc.complete(r);
  res.json({ reminder: out.reminder, next: out.next, already: out.already });
});

// ---- takipler ---------------------------------------------------------------------------------------------------------
router.get("/followups", requireAuth, async (req, res) => {
  const status = req.query.status || "acik";
  if (!["acik", "yapildi", "ertelendi", "iptal", "all"].includes(status)) return bad(res, "Geçersiz status.");
  const ctx = await facts.context.userCtx(asUser(req.user));
  res.json({ items: await followupsFacts.listFollowups(ctx, { status }) });
});
router.post("/followups", requireAuth, async (req, res) => {
  const b = req.body || {};
  if (typeof b.title !== "string" || !b.title.trim() || b.title.length > 200) return bad(res, "title (1–200 karakter) zorunlu.");
  if (typeof b.due_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(b.due_date)) return bad(res, "due_date YYYY-MM-DD olmalı.");
  const kind = b.kind || "diger";
  if (!["ara", "teklif", "tahsilat", "bilgi", "diger"].includes(kind)) return bad(res, "Geçersiz kind.");
  for (const k of ["offer_id", "project_id"]) if (b[k] !== undefined && b[k] !== null && !UUID.test(b[k])) return bad(res, `${k} geçersiz.`);
  const orgId = await orgIdForUser(req.user.id);
  const { rows } = await db.query(
    `INSERT INTO followups (org_id, user_id, kind, title, due_date, offer_id, project_id, customer_name, customer_phone, source)
     VALUES ($1,$2,$3,$4,$5::date,$6,$7,$8,$9,'kullanici') RETURNING id, kind, title, to_char(due_date,'YYYY-MM-DD') AS due_date, status`,
    [orgId, req.user.id, kind, b.title.trim(), b.due_date, b.offer_id || null, b.project_id || null, b.customer_name ? String(b.customer_name).slice(0, 200) : null, b.customer_phone ? String(b.customer_phone).slice(0, 50) : null]);
  res.status(201).json(rows[0]);
});
router.post("/followups/:id/done", requireAuth, async (req, res) => {
  const id = paramId(req, res); if (!id) return;
  const { rows } = await db.query(`UPDATE followups SET status = 'yapildi', done_at = COALESCE(done_at, $3) WHERE id = $1 AND user_id = $2 RETURNING id, status, done_at`, [id, req.user.id, clock.now()]);
  if (!rows[0]) return bad(res, "Takip bulunamadı.", 404);
  res.json(rows[0]);
});
router.post("/followups/:id/snooze", requireAuth, async (req, res) => {
  const id = paramId(req, res); if (!id) return;
  const days = (req.body || {}).days;
  if (!Number.isInteger(days) || days < 1 || days > 60) return bad(res, "days 1–60 tam sayı olmalı.");
  const until = clock.addDays(clock.istanbulDateStr(), days);
  const { rows } = await db.query(`UPDATE followups SET status = 'ertelendi', snoozed_until = $3::date WHERE id = $1 AND user_id = $2 AND status IN ('acik','ertelendi') RETURNING id, status, to_char(snoozed_until,'YYYY-MM-DD') AS snoozed_until`, [id, req.user.id, until]);
  if (!rows[0]) return bad(res, "Takip bulunamadı.", 404);
  res.json(rows[0]);
});

module.exports = router;
