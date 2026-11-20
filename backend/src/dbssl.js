const fs = require("fs");

/**
 * PostgreSQL TLS ayarı (ortam değişkenlerinden). Geriye uyumlu varsayılan: TLS açıkken sertifika DOĞRULANMAZ
 * (eski davranış, rejectUnauthorized:false). Doğrulamayı açmak için:
 *   DB_SSL_REJECT_UNAUTHORIZED=true            (sistem CA'ları ile — örn. yönetilen DB)
 *   DB_SSL_CA=/etc/ssl/db-ca.pem               (özel CA; verilirse doğrulama varsayılan olarak AÇIK olur)
 * DATABASE_SSL=true|false: TLS'i açar/kapatır (verilmezse NODE_ENV=production ise açık).
 */
function buildSslConfig(env = process.env) {
  const enabled = env.DATABASE_SSL ? env.DATABASE_SSL === "true" : env.NODE_ENV === "production";
  if (!enabled) return false;
  const cfg = {};
  if (env.DB_SSL_CA) {
    cfg.ca = /-----BEGIN/.test(env.DB_SSL_CA) ? env.DB_SSL_CA : fs.readFileSync(env.DB_SSL_CA, "utf8");
  }
  const explicit = env.DB_SSL_REJECT_UNAUTHORIZED;
  cfg.rejectUnauthorized = explicit !== undefined && explicit !== "" ? explicit === "true" : !!cfg.ca;
  return cfg;
}

module.exports = { buildSslConfig };
