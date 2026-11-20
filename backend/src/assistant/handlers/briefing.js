/**
 * Gerçek brifing işleyicileri (A1'in yer tutucularını EZER): briefing.morning · briefing.weekly · briefing.monthly.
 * İdempotent: briefings upsert (user,kind,period_start) + notifyUser dedupeKey (kullanıcıyı içerir) → iş iki kez çalışsa TEK bildirim.
 * Üretim hata verirse yeniden denenir; son denemede sade bir yedek bildirim atılır ("hiçbir bildirim eksik kalmaz").
 */
const db = require("../../db");
const clock = require("../clock");
const { notifyUser } = require("../notify");
const store = require("../briefing/store");
const morning = require("../briefing/morning");
const reports = require("../briefing/reports");
const { orgIdForUser } = require("../org");

async function loadUser(id) {
  const { rows } = await db.query("SELECT id, name, role, org_id FROM users WHERE id = $1", [id]);
  return rows[0] || null;
}

function makeHandler(kind, builder, fallbackTitle) {
  return async (payload, job) => {
    const userId = payload.userId || job.userId;
    const date = payload.date || clock.istanbulDateStr();
    const u = await loadUser(userId);
    if (!u) return; // kullanıcı silinmiş
    const orgId = u.org_id || (await orgIdForUser(userId));
    const dedupeKey = `briefing.${kind}:${userId}:${date}`;
    let b;
    try {
      b = await builder({ id: u.id, name: u.name, role: u.role }, { date, orgId });
    } catch (err) {
      if (job.attempts < Math.min(job.maxAttempts, 3)) throw err; // yeniden dene
      console.error(`[briefing.${kind}] üretim hatası (yedek bildirim):`, err.message);
      await notifyUser(userId, { type: "briefing", title: fallbackTitle, body: "Gündemi görmek için uygulamayı açın.", data: { kind, date, fallback: true }, dedupeKey, sendAt: job.runAt });
      return;
    }
    const saved = await store.save({ orgId, userId, kind, periodStart: b.data.kind === "monthly" ? `${b.data.period.month}-01` : b.data.kind === "weekly" ? b.data.period.from : date, title: b.title, bodyText: b.bodyText, data: b.data, generatedBy: "job" });
    await notifyUser(userId, {
      type: "briefing", title: b.notification.title, body: b.notification.body,
      data: { kind, date, briefing_id: saved.id, ...(b.data.stats ? { stats: b.data.stats } : {}) },
      dedupeKey, sendAt: job.runAt,
    });
  };
}

module.exports.register = (registerHandler) => {
  registerHandler("briefing.morning", makeHandler("morning", morning.build, "Günaydın"));
  registerHandler("briefing.weekly", makeHandler("weekly", reports.buildWeekly, "Haftalık özet"));
  registerHandler("briefing.monthly", makeHandler("monthly", reports.buildMonthly, "Aylık rapor"));
};
