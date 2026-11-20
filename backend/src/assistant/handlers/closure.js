/**
 * Akşam kapanış: 'closure.evening' (kapanış saati; soruları üretir, bildirim atar, 20:30 hatırlatmasını planlar) ve
 * 'closure.nudge' (yanıt gelmediyse TEK nazik hatırlatma; sonrası ısrar yok — ertesi sabah brifingi "dün kapanış yapılmadı" satırını gösterir).
 */
const db = require("../../db");
const clock = require("../clock");
const queue = require("../queue");
const prefsSvc = require("../prefs");
const { notifyUser } = require("../notify");
const closure = require("../closure/service");
const { orgIdForUser } = require("../org");

const NUDGE_TIME = "20:30";
const NUDGE_MIN_GAP_MS = 60 * 60000;

async function loadUser(id) {
  const { rows } = await db.query("SELECT id, name, role, org_id FROM users WHERE id = $1", [id]);
  return rows[0] || null;
}

module.exports.register = (registerHandler) => {
  registerHandler("closure.evening", async (payload, job) => {
    const userId = payload.userId || job.userId;
    const date = payload.date || clock.istanbulDateStr();
    const u = await loadUser(userId);
    if (!u) return;
    const orgId = u.org_id || (await orgIdForUser(userId));
    const user = { id: u.id, name: u.name, role: u.role };
    const today = await closure.getToday(user, { date, orgId, refresh: true });
    const n = today.questions.length;
    const card = today.summary_card;
    const title = n > 0 ? `Gün sonu: ${n} kısa soru` : "Gün sonu özeti";
    const body = n > 0 ? `${card.text} Günü kapatmak için ${n} soruya göz atın (iki dakika).` : card.text;
    await notifyUser(userId, { type: "closure", title, body: body.slice(0, 300), data: { kind: "evening", date, questions: n }, dedupeKey: `closure.evening:${userId}:${date}`, sendAt: job.runAt });
    if (n > 0) {
      const p = await prefsSvc.getPrefs(userId);
      let at = clock.zonedToUtc(date, NUDGE_TIME, p.tz);
      const minAt = new Date(new Date(job.runAt).getTime() + NUDGE_MIN_GAP_MS);
      if (at < minAt) at = minAt;
      await queue.enqueue("closure.nudge", { userId, date }, { runAt: at, userId, orgId, dedupeKey: `closure.nudge:${userId}:${date}`, expiresAt: new Date(at.getTime() + 60 * 60000), maxAttempts: 2 });
    }
  });

  registerHandler("closure.nudge", async (payload, job) => {
    const userId = payload.userId || job.userId;
    const date = payload.date;
    const log = await closure.readLog(userId, date);
    if (!log || log.status !== "pending" || Object.keys(log.answers || {}).length > 0 || log.nudged_at) return; // yanıt var / zaten hatırlatıldı
    const n = (log.questions || []).length;
    if (n === 0) return;
    await notifyUser(userId, { type: "closure", title: "Gün sonu: kısa bir hatırlatma", body: `${n} soru sizi bekliyor; atlayabilirsiniz.`, data: { kind: "evening_nudge", date, questions: n }, dedupeKey: `closure.nudge:${userId}:${date}`, sendAt: job.runAt });
    await db.query("UPDATE daily_logs SET nudged_at = $3 WHERE user_id = $1 AND log_date = $2::date AND nudged_at IS NULL", [userId, date, clock.now()]);
  });
};
