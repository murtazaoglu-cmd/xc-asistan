/**
 * Varsayılan (YER TUTUCU) işleyiciler. A2'nin gerçek brifing/kapanış işleyicisi aynı iş adlarını kaydettiğinde bunları EZER
 * (fallback:true → yalnız başka işleyici yoksa geçerli; yükleme sırasından bağımsız).
 * Bildirim kutusuna sektör-nötr basit bir mesaj düşer; dedupeKey sayesinde iş iki kez çalışsa da tek bildirim çıkar.
 */
const { notifyUser } = require("../notify");

module.exports.register = (registerHandler) => {
  registerHandler("briefing.morning", async (payload, job) => {
    const userId = payload.userId || job.userId;
    await notifyUser(userId, {
      type: "briefing", title: "Günaydın", body: "Bugünün gündemini görmek için uygulamayı açın.",
      data: { kind: "morning", date: payload.date, placeholder: true },
      dedupeKey: `briefing.morning:${userId}:${payload.date}`, sendAt: job.runAt,
    });
  }, { fallback: true });
  registerHandler("closure.evening", async (payload, job) => {
    const userId = payload.userId || job.userId;
    await notifyUser(userId, {
      type: "closure", title: "Gün sonu", body: "Bugünü kapatmak için kısa özete göz atın.",
      data: { kind: "evening", date: payload.date, placeholder: true },
      dedupeKey: `closure.evening:${userId}:${payload.date}`, sendAt: job.runAt,
    });
  }, { fallback: true });
};
