const planner = require("../planner");
module.exports.register = (registerHandler) => {
  // plan_day: worker her ~10 dk'da bir (idempotent) kuyruğa koyar; gece yarısı geçişi ve yeni kullanıcılar böylece yakalanır
  registerHandler("plan_day", async () => planner.planAll());
};
