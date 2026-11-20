/**
 * Müdür motoru kuralları M7 ve M8 (design-assistant.md §1.3) — SAF fonksiyonlar; veri çekimi çağıranın işidir.
 * Çıktı `insight` biçimindedir: {rule_key, severity, fingerprint, evidence, suggested_actions, confirmation}.
 * Eşikler başlangıç varsayımıdır (insight_rule_config ile org bazında ayarlanabilir: thresholds parametresi).
 */
const { daysBetween, addDays, daysInMonth, fmt } = require("./dates");

const DEFAULTS = {
  m7: { warnDays: 7, criticalDays: 30, monthEndDays: 5 },
  m8: { warnDays: 7, remindDays: [7, 3], criticalDays: 1 },
};

/** Haftanın pazartesisi — fingerprint'te "aynı insight tekrar gönderilmez" için */
function weekStart(day) {
  const dow = (new Date(day + "T00:00:00Z").getUTCDay() + 6) % 7; // Pzt=0
  return addDays(day, -dow);
}

/**
 * M7 Faturasız tahsilat: iş başına Σ ödeme − Σ giden fatura (ikisi de KDV DAHİL brüt; KDV oranı varsayılmaz).
 * Faturalar en eski ödemeleri önce kapatır (FIFO); kapatılmamış ilk ödemenin tarihi "faturasız yaş"ı verir.
 * Uyarı: yaş > 7 gün. Kritik: yaş > 30 gün ya da (uyarı koşulu + ay sonuna < 5 gün).
 * @param projects [{project_id, code, customer_name, payments:[{day:'YYYY-MM-DD', kurus}], invoicedKurus}]
 */
function m7UnbilledCollections(projects, today, thresholds = DEFAULTS.m7) {
  const out = [];
  const dim = daysInMonth(+today.slice(0, 4), +today.slice(5, 7));
  const daysToMonthEnd = dim - +today.slice(8, 10);
  for (const p of projects) {
    const pays = [...p.payments].sort((a, b) => (a.day < b.day ? -1 : a.day > b.day ? 1 : 0));
    const paid = pays.reduce((s, x) => s + x.kurus, 0);
    let covered = p.invoicedKurus;
    let oldest = null, uncovered = 0;
    for (const x of pays) {
      if (covered >= x.kurus) { covered -= x.kurus; continue; }
      const open = x.kurus - covered; covered = 0;
      uncovered += open; if (!oldest) oldest = x.day;
    }
    if (uncovered <= 0 || !oldest) continue;
    const age = daysBetween(oldest, today);
    if (age <= thresholds.warnDays) continue;
    const critical = age > thresholds.criticalDays || daysToMonthEnd < thresholds.monthEndDays;
    out.push({
      rule_key: "M7", severity: critical ? "critical" : "warn",
      fingerprint: `M7:${p.project_id}:${weekStart(today)}`,
      evidence: { project_id: p.project_id, project_code: p.code || null, customer_name: p.customer_name || null, uncoveredKurus: uncovered, paymentsKurus: paid, invoicedKurus: p.invoicedKurus, oldestUncoveredDate: oldest, ageDays: age, basis: "brüt (KDV dahil) karşılaştırma" },
      suggested_actions: ["Fatura kaydı ekle"],
      confirmation: { needed: true, reasons: ["Ödeme-fatura eşleşmesi tahminidir; avans/kapora için belge kuralı mali müşavire teyit edilmeli"] },
    });
  }
  return out.sort((a, b) => b.evidence.uncoveredKurus - a.evidence.uncoveredKurus);
}

/**
 * M8 KDV: ödenecek KDV son gününe yaklaşırken uyarı.
 *   warn: son güne ≤ 7 gün (T−7, T−3 hatırlatma eşikleri `remindDays`)
 *   critical: son güne ≤ 1 gün VE ödenecek > ay sonu nakit tahmini (cashForecastKurus verilmişse)
 * @param {{period:{key}, odenecekKurus, hesaplananKurus, indirilecekKurus, oncekiDevredenKurus, devredenKurus}} r  computePeriod çıktısı + key
 * @param {{dueDate:string, today:string, cashForecastKurus?:number|null, dueNeedsConfirmation?:boolean, docless?:{count,total,amountKurus,totalKurus}}} ctx
 */
function m8VatDeadline(r, ctx, thresholds = DEFAULTS.m8) {
  if (!ctx.dueDate) return null;
  const daysUntil = daysBetween(ctx.today, ctx.dueDate);
  if (daysUntil < 0 || r.odenecekKurus <= 0 || daysUntil > thresholds.warnDays) return null;
  const cash = ctx.cashForecastKurus;
  const shortfall = Number.isInteger(cash) && r.odenecekKurus > cash;
  const critical = daysUntil <= thresholds.criticalDays && shortfall;
  const dl = ctx.docless;
  return {
    rule_key: "M8", severity: critical ? "critical" : "warn",
    fingerprint: `M8:${r.key}:T${daysUntil}`,
    evidence: {
      period: r.key, dueDate: ctx.dueDate, daysUntil, tahmini: true,
      odenecekKurus: r.odenecekKurus, hesaplananKurus: r.hesaplananKurus, indirilecekKurus: r.indirilecekKurus, oncekiDevredenKurus: r.oncekiDevredenKurus,
      cashForecastKurus: Number.isInteger(cash) ? cash : null, cashShortfall: Number.isInteger(cash) ? shortfall : null,
      cashNote: Number.isInteger(cash) ? null : "Nakit tahmini verilmedi; kritik eşik (nakit yetersizliği) değerlendirilemedi",
      doclessExpenseRatio: dl && dl.totalKurus > 0 ? Math.round((dl.amountKurus / dl.totalKurus) * 1000) / 10 : null,
      doclessExpenseCount: dl ? dl.count : null,
    },
    suggested_actions: ["Belgesi olmayan giderleri listele", "Mali müşavire aktar (KDV dönem özeti)"],
    confirmation: { needed: true, reasons: ["Tahmini hesap; beyan sorumluluğu mali müşavirdedir", ...(ctx.dueNeedsConfirmation ? ["Son gün tarihi/takvim kaydı doğrulanmadı"] : [])] },
  };
}

module.exports = { DEFAULTS, weekStart, m7UnbilledCollections, m8VatDeadline };
