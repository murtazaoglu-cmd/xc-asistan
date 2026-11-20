/**
 * Bildirim göndericisi: notification_outbox → FCM HTTP v1.
 * FCM yapılandırılmamışsa (servis hesabı anahtarı yok) DEVRE DIŞI ("dryRun"): hiçbir şey gönderilmez, kayıtlar
 * 'beklemede' kalır ve uygulama içi bildirim kutusundan (GET /api/assistant/inbox) okunur.
 *   sendDue({limit}) → {enabled, claimed, sent, inboxOnly, retried, failed, expired}
 */
const db = require("../db");
const clock = require("./clock");
const fcm = require("./fcmv1");
const prefsSvc = require("./prefs");

const BACKOFF_MS = [60 * 1000, 5 * 60 * 1000, 30 * 60 * 1000];
const MAX_ATTEMPTS = 5;
const LEASE_MS = 2 * 60 * 1000;

async function sendDue(opts = {}) {
  const res = { enabled: fcm.isEnabled(), claimed: 0, sent: 0, inboxOnly: 0, retried: 0, failed: 0, expired: 0 };
  if (!res.enabled) return res;
  const now = clock.now();
  const limit = opts.limit || 50;

  const ex = await db.query(`UPDATE notification_outbox SET status='iptal', last_error='süresi geçti' WHERE status='beklemede' AND expires_at IS NOT NULL AND expires_at <= $1`, [now]);
  res.expired = ex.rowCount;

  const { rows } = await db.query(
    `UPDATE notification_outbox SET locked_until = $2, attempts = attempts + 1
      WHERE id IN (SELECT id FROM notification_outbox WHERE status='beklemede' AND not_before <= $1 AND (locked_until IS NULL OR locked_until <= $1)
                    ORDER BY not_before LIMIT $3 FOR UPDATE SKIP LOCKED)
      RETURNING *`, [now, new Date(now.getTime() + LEASE_MS), limit]);
  res.claimed = rows.length;

  for (const n of rows) {
    const p = await prefsSvc.getPrefs(n.user_id);
    const finish = (channels) => db.query(`UPDATE notification_outbox SET status='gonderildi', sent_at=$2, sent_channels=$3, locked_until=NULL, last_error=NULL WHERE id=$1`, [n.id, now, channels]);
    if (p.channels.push === false) { await finish(["inbox"]); res.inboxOnly++; continue; }
    const { rows: toks } = await db.query(`SELECT id, token FROM device_tokens WHERE user_id = $1 AND disabled_at IS NULL AND platform IN ('android','ios')`, [n.user_id]);
    if (toks.length === 0) { await finish(["inbox"]); res.inboxOnly++; continue; }
    let okCount = 0, retryable = false, lastErr = null;
    for (const t of toks) {
      const r = await fcm.send(t.token, { title: n.title, body: n.body, data: { ...n.data, type: n.type, notification_id: n.id } });
      if (r.ok) { okCount++; continue; }
      lastErr = r.error;
      if (r.invalidToken) await db.query("UPDATE device_tokens SET disabled_at = $2 WHERE id = $1", [t.id, now]);
      else if (!r.permanent) retryable = true;
    }
    if (okCount > 0) { await finish(["push", "inbox"]); res.sent++; }
    else if (retryable && n.attempts < MAX_ATTEMPTS) {
      await db.query(`UPDATE notification_outbox SET locked_until=$2, last_error=$3 WHERE id=$1`, [n.id, new Date(now.getTime() + BACKOFF_MS[Math.min(n.attempts - 1, 2)]), lastErr]);
      res.retried++;
    } else if (retryable) {
      await db.query(`UPDATE notification_outbox SET status='basarisiz', locked_until=NULL, last_error=$2 WHERE id=$1`, [n.id, lastErr]);
      res.failed++;
    } else { await finish(["inbox"]); res.inboxOnly++; } // tüm token'lar geçersizdi → yalnız kutu
  }
  return res;
}

module.exports = { sendDue };
