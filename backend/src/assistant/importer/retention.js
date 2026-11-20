/**
 * Saklama ve imha (KVKK): worker'ın günlük housekeeping işi ve testler çağırır. Hiçbir şey dışarı gönderilmez.
 *  - onaylanmamış önizlemeler (ayrıştırılmış ham mesajlar) süresi dolunca silinir
 *  - ham mesaj metni raw_expires_at sonrası SİLİNİR (content=NULL, redacted=true); kabul edilmiş notlar kalır, öneri alıntıları temizlenir
 *  - yazışma retention_until sonrası tümüyle silinir (mesaj/öneri/not zinciri CASCADE)
 *  - bekleyen öneriler/kartlar süresi dolunca 'suresi_doldu'; komut ham metni raw_expires_at sonrası temizlenir
 * Süreler: IMPORT_RETENTION_DAYS (yazışma, varsayılan 730 ≈ 2 yıl), IMPORT_RAW_TEXT_DAYS (ham metin, varsayılan 180).
 */
const db = require("../../db");

const RETENTION_DAYS = () => Math.max(Number(process.env.IMPORT_RETENTION_DAYS) || 730, 1);
const RAW_DAYS = () => Math.max(Number(process.env.IMPORT_RAW_TEXT_DAYS) || 180, 1);

async function purge(now = new Date()) {
  const out = {};
  out.previews = (await db.query("DELETE FROM conversation_imports WHERE status = 'onizleme' AND expires_at < $1", [now])).rowCount;
  // süresi dolan ham metin: önce öneri alıntıları, sonra mesaj içeriği
  await db.query(`UPDATE ai_suggestions SET payload = payload - 'excerpt' - 'address'
                   WHERE source_message_id IN (SELECT id FROM conversation_messages WHERE redacted = false AND raw_expires_at IS NOT NULL AND raw_expires_at < $1)`, [now]);
  out.redacted = (await db.query("UPDATE conversation_messages SET content = NULL, redacted = true WHERE redacted = false AND raw_expires_at IS NOT NULL AND raw_expires_at < $1", [now])).rowCount;
  out.conversations = (await db.query("DELETE FROM conversations WHERE retention_until IS NOT NULL AND retention_until < $1", [now])).rowCount;
  out.suggestions = (await db.query("UPDATE ai_suggestions SET status = 'suresi_doldu', decided_at = $1 WHERE status = 'beklemede' AND expires_at < $1", [now])).rowCount;
  out.actions_expired = (await db.query("UPDATE ai_actions SET status = 'suresi_doldu', decided_at = $1 WHERE status = 'onerildi' AND expires_at < $1", [now])).rowCount;
  out.action_text = (await db.query("UPDATE ai_actions SET raw_text = NULL WHERE raw_text IS NOT NULL AND raw_expires_at IS NOT NULL AND raw_expires_at < $1", [now])).rowCount;
  return out;
}

module.exports = { purge, RETENTION_DAYS, RAW_DAYS };
