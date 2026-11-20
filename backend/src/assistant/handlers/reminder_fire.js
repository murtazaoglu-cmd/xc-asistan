/**
 * 'reminder.fire': hatırlatma / randevu öncesi bildirimleri. İdempotent (notifyUser dedupeKey).
 *  kind 'reminder'          : kullanıcının hatırlatması zamanı geldi (yalnız hâlâ 'bekliyor' ve zamanı değişmediyse; ertelenen eski iş sessizce atlanır)
 *  kind 'appointment_eve'   : önceki akşam "yarın N randevu" (kullanıcı başına TEK)
 *  kind 'appointment_hour'  : randevudan 60 dk önce (iptal/tamamlanmış/taşınmış randevu için atlanır)
 */
const db = require("../../db");
const clock = require("../clock");
const tr = require("../text/tr");
const { notifyUser } = require("../notify");
const facts = require("../facts");
const { loadTerms } = require("../text/terms");
const { apptItem } = require("../briefing/common");
const { orgIdForUser } = require("../org");

const REMINDER_ACTIONS = [{ id: "done", label: "Tamam", method: "POST", path: "/api/assistant/reminders/:id/complete" }, { id: "snooze_15m", label: "15 dk", method: "POST", path: "/api/assistant/reminders/:id/snooze", body: { preset: "15m" } },
  { id: "snooze_1h", label: "1 saat", method: "POST", path: "/api/assistant/reminders/:id/snooze", body: { preset: "1h" } }, { id: "snooze_tomorrow", label: "Yarın", method: "POST", path: "/api/assistant/reminders/:id/snooze", body: { preset: "tomorrow" } }];

async function loadUser(id) {
  const { rows } = await db.query("SELECT id, name, role, org_id FROM users WHERE id = $1", [id]);
  return rows[0] || null;
}

module.exports.register = (registerHandler) => {
  registerHandler("reminder.fire", async (payload, job) => {
    const now = clock.now();
    const kind = payload.kind || "reminder";

    if (kind === "reminder") {
      const { rows } = await db.query("SELECT * FROM reminders WHERE id = $1", [payload.reminderId]);
      const r = rows[0];
      if (!r || r.status !== "bekliyor" || !r.owner_id) return;
      if (new Date(r.remind_at).getTime() !== new Date(payload.remindAt).getTime()) return; // ertelendi/taşındı: yeni iş çalışacak
      const epoch = Math.floor(new Date(r.remind_at).getTime() / 1000);
      await notifyUser(r.owner_id, {
        type: "reminder", title: r.title, body: r.note || "Hatırlatma zamanı geldi.",
        data: { kind: "reminder", reminder_id: r.id, project_id: r.project_id || null, recurrence: r.recurrence || null, actions: REMINDER_ACTIONS.map((a) => ({ ...a, path: a.path.replace(":id", r.id) })) },
        dedupeKey: `reminder.fire:${r.id}:${epoch}`, sendAt: now,
      });
      await db.query("UPDATE reminders SET fired_at = COALESCE(fired_at, $2) WHERE id = $1", [r.id, now]);
      return;
    }

    const u = await loadUser(payload.userId || job.userId);
    if (!u) return;
    const orgId = u.org_id || (await orgIdForUser(u.id));
    const user = { id: u.id, name: u.name, role: u.role };

    if (kind === "appointment_eve") {
      const ctx = await facts.context.userCtx(user, { date: payload.date, orgId });
      const T = await loadTerms(orgId);
      const list = (await facts.agenda.appointmentsOn(ctx, payload.date)).filter((a) => a.state !== "tamamlandi");
      if (list.length === 0) return;
      const items = list.map(apptItem);
      await notifyUser(u.id, {
        type: "reminder", title: `Yarın ${T.n(list.length, "appointment")}`, body: items.slice(0, 3).map((i) => i.summary).join("; ") + (items.length > 3 ? ` +${items.length - 3}` : ""),
        data: { kind: "appointment_eve", date: payload.date, count: list.length, appointment_ids: list.map((a) => a.id) },
        dedupeKey: `reminder.fire:appt_eve:${u.id}:${payload.date}`,
      });
      return;
    }

    if (kind === "appointment_hour") {
      const { rows } = await db.query(`SELECT a.* FROM appointments a WHERE a.id = $1`, [payload.appointmentId]);
      const a0 = rows[0];
      if (!a0) return;
      const st = facts.context.apptState(a0.status);
      if (st === "iptal" || st === "tamamlandi") return;
      if (new Date(a0.scheduled_at).getTime() !== new Date(payload.scheduledAt).getTime()) return; // taşındı: yeni zamanın işi planlanır
      if (new Date(a0.scheduled_at) <= now) return;
      const full = await require("../../services/appointmentQueries").getAppointment(a0.id);
      const m = require("../facts/agenda").mapAppt(full, clock.IST);
      const it = apptItem(m);
      await notifyUser(u.id, {
        type: "reminder", title: `${m.time} ${m.customer_name || "Randevu"}${m.type ? ` — ${m.type}` : ""}`, body: m.address || (m.service ? m.service : "Yaklaşan randevu"),
        data: { kind: "appointment_hour", appointment_id: a0.id, scheduled_at: m.scheduled_at, actions: it.actions },
        dedupeKey: `reminder.fire:appt60:${a0.id}:${Math.floor(new Date(a0.scheduled_at).getTime() / 1000)}:${u.id}`,
      });
    }
  });
};
