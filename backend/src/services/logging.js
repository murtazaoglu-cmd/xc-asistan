/** Güvenli günlükleme: URL sorgu dizeleri (imza, jeton), takip kodları, e-posta ve DB satır değerleri loglara girmez. */

function redactUrl(url) {
  const pathOnly = String(url || "").split("?")[0];
  return pathOnly.replace(/XCY-[A-Z0-9]+/gi, "[kod]");
}

function scrub(msg) {
  return String(msg || "")
    .replace(/\(([^()]{1,60})\)=\(([^()]{0,200})\)/g, "($1)=([gizli])")   // Postgres: Key (email)=(x@y)
    .replace(/[\w.+-]+@[\w-]+(\.[\w-]+)+/g, "[e-posta]")
    .replace(/Bearer\s+[\w.-]+/gi, "Bearer [gizli]")
    .slice(0, 300);
}

/** Tek satırlık, hassas veri içermeyen hata özeti (pg parameters/detail/where alanları yazılmaz) */
function describeErrorForLog(err) {
  if (!err) return "bilinmeyen hata";
  const name = err.name || "Error";
  const code = err.code ? ` [${err.code}]` : "";
  return `${name}${code}: ${scrub(err.message)}`;
}

function logRequestError(req, err) {
  const stack = String((err && err.stack) || "").split("\n").slice(1, 4).map((l) => l.trim()).join(" | ");
  console.error(`${req.method} ${redactUrl(req.originalUrl)} → ${describeErrorForLog(err)}${stack ? " :: " + stack.replace(/\/[^\s)]*node_modules\//g, "") : ""}`);
}

module.exports = { redactUrl, describeErrorForLog, logRequestError };
