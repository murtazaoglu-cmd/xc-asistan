/**
 * Hatırlatma genişletmesi: erteleme (15 dk / 1 saat / yarın), tekrar (günlük/iş günleri/haftalık/aylık), tamamlama, zamanlama.
 * Mevcut /api/reminders sözleşmesi aynen kalır; alıcı = reminders.owner_id; etkin zaman = remind_at (ertelemede yeni zamana taşınır).
 * Bildirim işi 'reminder.fire' (handlers/reminder_fire.js). Tüm zaman hesapları İstanbul günü/saatiyle ve clock.js üzerinden.
 */
const db = require("../../db");
const clock = require("../clock");
const queue = require("../queue");

const RECURRENCES = ["daily", "weekdays", "weekly", "monthly"];
const SNOOZE_PRESETS = { "15m": 15, "1h": 60, tomorrow: "tomorrow" };
const FIRE_GRACE_MS = 6 * 3600 * 1000; // vadesi bu kadar geçmiş kaçırılmış hatırlatma için bildirim atılmaz

/** Yerel (İstanbul) saatini koruyarak bir sonraki tekrar zamanı. weekdays = Pzt–Cuma. */
function nextOccurrence(remindAt, recurrence, tz = clock.IST) {
  const d = new Date(remindAt);
  const date = clock.zonedDateStr(d, tz);
  const hhmm = new Intl.DateTimeFormat("en-GB", { timeZone: tz, hourCycle: "h23", hour: "2-digit", minute: "2-digit" }).format(d);
  let nd;
  if (recurrence === "daily") nd = clock.addDays(date, 1);
  else if (recurrence === "weekly") nd = clock.addDays(date, 7);
  else if (recurrence === "weekdays") {
    nd = clock.addDays(date, 1);
    for (let i = 0; i < 3 && clock.zonedWeekday(clock.zonedToUtc(nd, "12:00", tz), tz) > 5; i++) nd = clock.addDays(nd, 1);
  } else if (recurrence === "monthly") {
    const [y, m, day] = date.split("-").map(Number);
    const ny = m === 12 ? y + 1 : y, nm = m === 12 ? 1 : m + 1;
    const last = new Date(Date.UTC(ny, nm, 0)).getUTCDate();
    nd = `${ny}-${String(nm).padStart(2, "0")}-${String(Math.min(day, last)).padStart(2, "0")}`;
  } else return null;
  return clock.zonedToUtc(nd, hhmm, tz);
}

/** Ertelemenin yeni zamanı: 15m/1h → şimdi + süre; tomorrow → yarın 09:00 (İstanbul); ya da {minutes} (5–1440) */
function snoozeTarget(preset, now = clock.now(), tz = clock.IST) {
  if (preset === "tomorrow") return clock.zonedToUtc(clock.addDays(clock.zonedDateStr(now, tz), 1), "09:00", tz);
  const min = SNOOZE_PRESETS[preset];
  if (typeof min === "number") return new Date(now.getTime() + min * 60000);
  if (typeof preset === "number" && Number.isInteger(preset) && preset >= 5 && preset <= 1440) return new Date(now.getTime() + preset * 60000);
  return null;
}

/** reminder.fire işini kuyruğa koyar (idempotent: aynı hatırlatma + aynı zaman = tek iş) */
async function schedule(r) {
  if (!r || r.status !== "bekliyor" || !r.owner_id) return null;
  const at = new Date(r.remind_at);
  const now = clock.now();
  return queue.enqueue("reminder.fire", { kind: "reminder", reminderId: r.id, remindAt: at.toISOString(), userId: r.owner_id }, {
    runAt: at < now ? now : at, userId: r.owner_id, orgId: r.org_id || undefined,
    dedupeKey: `reminder.fire:${r.id}:${Math.floor(at.getTime() / 1000)}`, expiresAt: new Date(Math.max(at.getTime(), now.getTime()) + FIRE_GRACE_MS), maxAttempts: 3,
  });
}

async function snooze(r, preset, now = clock.now()) {
  const target = snoozeTarget(preset, now);
  if (!target) return { error: "Geçersiz erteleme: 15m, 1h, tomorrow ya da 5–1440 dakika (minutes)." };
  if (r.status !== "bekliyor") return { error: "Yalnız bekleyen hatırlatma ertelenebilir.", status: 409 };
  const { rows } = await db.query(
    `UPDATE reminders SET remind_at = $2, snoozed_until = $2, snooze_count = snooze_count + 1, fired_at = NULL WHERE id = $1 AND status = 'bekliyor' RETURNING *`, [r.id, target]);
  if (!rows[0]) return { error: "Hatırlatma artık bekleyen durumda değil.", status: 409 };
  await schedule(rows[0]);
  return { reminder: rows[0] };
}

/**
 * Tamamla (idempotent). Tekrarlı ise bir sonraki oluşum ayrı satır olarak eklenir (geçmişte kalan oluşumlar atlanır).
 * → {reminder, next|null, already: bool}
 */
async function complete(r, now = clock.now()) {
  const upd = await db.query(`UPDATE reminders SET status = 'tamamlandi', done_at = $2 WHERE id = $1 AND status = 'bekliyor' RETURNING *`, [r.id, now]);
  if (!upd.rows[0]) { const cur = await db.query("SELECT * FROM reminders WHERE id = $1", [r.id]); return { reminder: cur.rows[0], next: null, already: true }; }
  const done = upd.rows[0];
  let next = null;
  if (done.recurrence) {
    let at = nextOccurrence(done.remind_at, done.recurrence);
    for (let i = 0; at && at <= now && i < 400; i++) at = nextOccurrence(at, done.recurrence);
    if (at) {
      const key = `rec:${done.id}`;
      const ins = await db.query(
        `INSERT INTO reminders (project_id, title, remind_at, note, owner_id, recurrence, source, source_key, offer_id, appointment_id, org_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) ON CONFLICT (owner_id, source_key) WHERE source_key IS NOT NULL DO NOTHING RETURNING *`,
        [done.project_id, done.title, at, done.note, done.owner_id, done.recurrence, done.source, key, done.offer_id, done.appointment_id, done.org_id]);
      next = ins.rows[0] || null;
      if (next) await schedule(next);
    }
  }
  return { reminder: done, next, already: false };
}

/** Sistem/brifing kaynaklı hatırlatma oluştur (kaynak anahtarıyla idempotent) → {reminder, created} */
async function createSystem({ userId, title, remindAt, source = "sistem", sourceKey, note, projectId, offerId, appointmentId, orgId }) {
  const { rows } = await db.query(
    `INSERT INTO reminders (project_id, title, remind_at, note, owner_id, source, source_key, offer_id, appointment_id, org_id)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT (owner_id, source_key) WHERE source_key IS NOT NULL DO NOTHING RETURNING *`,
    [projectId || null, String(title).slice(0, 200), remindAt, note || null, userId, source, sourceKey || null, offerId || null, appointmentId || null, orgId || null]);
  if (rows[0]) { await schedule(rows[0]); return { reminder: rows[0], created: true }; }
  const ex = await db.query("SELECT * FROM reminders WHERE owner_id = $1 AND source_key = $2", [userId, sourceKey]);
  return { reminder: ex.rows[0], created: false };
}

function validRecurrence(v) { return v === null || v === undefined || RECURRENCES.includes(v); }

module.exports = { RECURRENCES, nextOccurrence, snoozeTarget, schedule, snooze, complete, createSystem, validRecurrence, FIRE_GRACE_MS };
