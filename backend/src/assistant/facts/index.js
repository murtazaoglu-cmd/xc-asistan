/** Facts servisleri: saf SQL + kuruş. Hepsi kapsam farkındadır (context.js). */
module.exports = {
  context: require("./context"),
  deps: require("./deps"),
  agenda: require("./agenda"),
  followups: require("./followups"),
  receivables: require("./receivables"),
  pnl: require("./pnl"),
  funnel: require("./funnel"),
  occupancy: require("./occupancy"),
  lowstock: require("./lowstock"),
  timeutil: require("./timeutil"),
};
