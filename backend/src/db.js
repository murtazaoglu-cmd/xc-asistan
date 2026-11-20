const { Pool, types } = require("pg");
require("dotenv").config();

// NUMERIC ve COUNT/SUM(bigint) varsayılan olarak string döner; API'de tutarlı sayı olsun.
types.setTypeParser(1700, (v) => (v === null ? null : parseFloat(v))); // NUMERIC
types.setTypeParser(20, (v) => (v === null ? null : parseInt(v, 10))); // BIGINT (COUNT)

const { buildSslConfig } = require("./dbssl");

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: buildSslConfig(process.env), // DATABASE_SSL / DB_SSL_REJECT_UNAUTHORIZED / DB_SSL_CA (README "v16")
  // Ay/gün sınırları İstanbul saatine göre hesaplanır (raporlar, "bu ay" toplamları)
  options: "-c timezone=Europe/Istanbul",
  max: 10,
  idleTimeoutMillis: 30000,
});

pool.on("error", (err) => {
  console.error("Beklenmeyen veritabanı hatası:", err);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};
