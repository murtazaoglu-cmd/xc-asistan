require("dotenv").config();
const fs = require("fs");
const path = require("path");
const readline = require("readline");
const bcrypt = require("bcryptjs");
const db = require("./db");

/**
 * Şema güncelleyici: schema.sql + schema_v2..vN dosyalarını SAYISAL sırayla, her biri bir kez ve
 * kendi transaction'ında uygular. Uygulananlar schema_migrations tablosunda tutulur.
 *
 * Mevcut kurulum (users tablosu var ama kayıt yok): v11'e kadar olan dosyalar elle uygulanmış kabul
 * edilip kayda geçirilir; yalnızca v12 ve sonrası çalıştırılır.
 */
const BASELINE_THROUGH = 11;

function listMigrations() {
  const files = fs.readdirSync(__dirname).filter((f) => /^schema(_v\d+)?\.sql$/.test(f));
  const num = (f) => (f === "schema.sql" ? 0 : Number(f.match(/_v(\d+)/)[1]));
  return files.sort((a, b) => num(a) - num(b)).map((f) => ({ file: f, n: num(f) }));
}

async function run() {
  await db.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
    name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())`);

  const migrations = listMigrations();
  const applied = new Set((await db.query("SELECT name FROM schema_migrations")).rows.map((r) => r.name));

  if (applied.size === 0) {
    const hasUsers = (await db.query("SELECT to_regclass('public.users') AS t")).rows[0].t;
    if (hasUsers) {
      console.log(`Mevcut kurulum algılandı — v${BASELINE_THROUGH}'e kadar olan şema dosyaları uygulanmış kabul ediliyor.`);
      // Eski kurulumlarda elle uygulanması gereken numarasız yama atlanmış olabilir
      // (push_subscriptions). Yama IF NOT EXISTS ile idempotenttir; v14 bu tabloya ihtiyaç duyar.
      const patchFile = path.join(__dirname, "schema_patch_push.sql");
      if (fs.existsSync(patchFile)) {
        await db.query(fs.readFileSync(patchFile, "utf8"));
        console.log("✔ schema_patch_push.sql (push_subscriptions yaması) uygulandı");
      }
      for (const m of migrations.filter((x) => x.n <= BASELINE_THROUGH)) {
        await db.query("INSERT INTO schema_migrations (name) VALUES ($1) ON CONFLICT DO NOTHING", [m.file]);
        applied.add(m.file);
      }
    }
  }

  for (const m of migrations) {
    if (applied.has(m.file)) continue;
    console.log(`Uygulanıyor: ${m.file}`);
    const sql = fs.readFileSync(path.join(__dirname, m.file), "utf8");
    const client = await db.pool.connect();
    try {
      // v14 kendi BEGIN/COMMIT'ini içerir; diğerleri için dış transaction açılır
      const ownTx = /^\s*BEGIN;/m.test(sql);
      if (!ownTx) await client.query("BEGIN");
      await client.query(sql);
      if (!ownTx) await client.query("COMMIT");
      await client.query("INSERT INTO schema_migrations (name) VALUES ($1)", [m.file]);
      console.log(`✔ ${m.file}`);
    } catch (err) {
      await client.query("ROLLBACK").catch(() => {});
      throw new Error(`${m.file} uygulanamadı: ${err.message}`);
    } finally {
      client.release();
    }
  }
  console.log("✔ Şema güncel.");

  const { rows } = await db.query("SELECT COUNT(*) FROM users");
  if (Number(rows[0].count) === 0) {
    if (!process.stdin.isTTY) {
      console.log("Henüz admin kullanıcı yok; etkileşimli terminalde yeniden çalıştırıp admin oluşturun.");
    } else {
      const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
      const ask = (q) => new Promise((resolve) => rl.question(q, resolve));
      console.log("\nHenüz admin kullanıcı yok. İlk admin hesabını oluşturalım:");
      const name = await ask("Ad Soyad: ");
      const email = (await ask("E-posta: ")).trim().toLowerCase();
      const password = await ask("Şifre: ");
      rl.close();
      const hash = await bcrypt.hash(password, 10);
      await db.query("INSERT INTO users (name, email, password_hash, role) VALUES ($1,$2,$3,'admin')", [name, email, hash]);
      console.log("✔ Admin kullanıcı oluşturuldu.");
    }
  }
  process.exit(0);
}

run().catch((err) => {
  console.error("Migration hatası:", err.message);
  process.exit(1);
});
