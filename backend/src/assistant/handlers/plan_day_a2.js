/**
 * plan_day işleyicisini genişletir (A1'in plan_day.js'inden SONRA yüklenir; aynı adı kaydeden son işleyici geçerlidir):
 * önce A1'in planAll'u (sabah/akşam), ardından A2 ekleri: randevu öncesi hatırlatma, bekleyen hatırlatma güvenlik ağı, haftalık/aylık rapor işleri.
 */
const planner = require("../planner");
const a2 = require("../reminders/planner");

module.exports.register = (registerHandler) => {
  registerHandler("plan_day", async () => {
    const base = await planner.planAll();
    const extra = await a2.planAll();
    return { ...base, a2: extra };
  });
};
