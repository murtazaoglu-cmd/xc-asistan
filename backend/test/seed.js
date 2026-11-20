process.chdir(process.argv[2]);
require(process.argv[2] + "/node_modules/dotenv").config();
const bcrypt = require(process.argv[2] + "/node_modules/bcryptjs");
const db = require(process.argv[2] + "/src/db");
(async () => {
  const h = await bcrypt.hash("pass1234", 10);
  const ins = async (n, e, r, cb) => (await db.query("INSERT INTO users (name,email,password_hash,role,created_by) VALUES ($1,$2,$3,$4,$5) RETURNING id", [n, e, h, r, cb])).rows[0].id;
  const admin = await ins("Admin", "admin@x.com", "admin", null);
  await ins("Muhasebe", "muh@x.com", "muhasebe", admin);
  const oA = await ins("OrtakA", "oa@x.com", "ortak", admin);
  const oB = await ins("OrtakB", "ob@x.com", "ortak", admin);
  await ins("PersA", "pa@x.com", "personel", oA);
  console.log("seeded");
  process.exit(0);
})();
