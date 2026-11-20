/**
 * Girdi doğrulama yardımcıları (v16 güvenlik sertleştirmesi). Hepsi sınırlı uzunlukta, geri izleme (backtracking)
 * riski olmayan, doğrusal zamanlı kontroller kullanır — kullanıcı girdisi üzerinde karmaşık regex çalıştırılmaz.
 */

const EMAIL_LOCAL_RE = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]{1,64}$/;
const DNS_LABEL_RE = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/;

/**
 * Tek bir e-posta adresini doğrular. Dönüş:
 *  - { value: null }      → boş/yok (alan temizlenir)
 *  - { value: "a@b.com" } → geçerli, kırpılmış adres
 *  - { error: true }      → geçersiz (dizi/nesne, >254 karakter, virgül/noktalı virgül/boşluk/<>, hatalı alan adı)
 * Görünen-ad biçimi ("Ali <ali@x.com>") ve çoklu adres bilinçli olarak KABUL EDİLMEZ.
 */
function parseEmail(v) {
  if (v === undefined || v === null) return { value: null };
  if (typeof v !== "string") return { error: true };
  const s = v.trim();
  if (s === "") return { value: null };
  if (s.length > 254) return { error: true };
  const at = s.indexOf("@");
  if (at < 1 || at !== s.lastIndexOf("@")) return { error: true };
  const local = s.slice(0, at), domain = s.slice(at + 1);
  if (!EMAIL_LOCAL_RE.test(local) || local.startsWith(".") || local.endsWith(".") || local.includes("..")) return { error: true };
  if (domain.length > 253) return { error: true };
  const labels = domain.split(".");
  if (labels.length < 2 || !labels.every((l) => DNS_LABEL_RE.test(l))) return { error: true };
  if (!/^[A-Za-z]{2,63}$/.test(labels[labels.length - 1])) return { error: true };
  return { value: s };
}

// Web Push servis sağlayıcıları (tarayıcıların kullandığı uç noktalar). Ek alan adları: PUSH_ENDPOINT_HOSTS (virgüllü; "*.ornek.com" desteklenir)
const PUSH_HOST_PATTERNS = [
  /^fcm\.googleapis\.com$/,
  /^android\.googleapis\.com$/,
  /^[a-z0-9-]+\.push\.services\.mozilla\.com$/,
  /^[a-z0-9-]+(\.[a-z0-9-]+)*\.notify\.windows\.com$/,
  /^web\.push\.apple\.com$/,
  /^[a-z0-9-]+\.push\.apple\.com$/,
];
function extraPushHosts() {
  return String(process.env.PUSH_ENDPOINT_HOSTS || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
}

/** Push abonelik uç noktası güvenli mi: https, kimlik bilgisi/özel port yok, IP değil, bilinen push servisi alan adı */
function isAllowedPushEndpoint(endpoint) {
  if (typeof endpoint !== "string" || endpoint.length > 2048) return false;
  let u;
  try { u = new URL(endpoint); } catch { return false; }
  if (u.protocol !== "https:" || u.username || u.password) return false;
  if (u.port && u.port !== "443") return false;
  const host = u.hostname.toLowerCase();
  if (!host || host.endsWith(".") || host.includes(":") || /^[0-9.]+$/.test(host)) return false; // IP literal / IPv6 / sondaki nokta
  if (PUSH_HOST_PATTERNS.some((re) => re.test(host))) return true;
  return extraPushHosts().some((h) => (h.startsWith("*.") ? host.endsWith(h.slice(1)) && host.length > h.length - 1 : host === h));
}

/** Herkese açık, https, IP/özel alan adı olmayan bir bağlantı mı (müşteri fotoğraf bağlantıları için) */
function isPublicHttpsUrl(s) {
  if (typeof s !== "string" || s.length > 500) return false;
  let u;
  try { u = new URL(s.trim()); } catch { return false; }
  if (u.protocol !== "https:" || u.username || u.password) return false;
  if (u.port && u.port !== "443") return false;
  const host = u.hostname.toLowerCase();
  if (!host || host.includes(":") || /^[0-9.]+$/.test(host) || host.startsWith("[")) return false; // IP literal / IPv6
  if (!host.includes(".") || host.endsWith(".")) return false;
  if (/(^|\.)(localhost|local|localdomain|internal|intranet|lan|home|corp|test|invalid)$/.test(host)) return false;
  if (/^(0x[0-9a-f]+|\d+)(\.|$)/.test(host)) return false; // sayısal/hex IP biçimleri
  return true;
}

/** Fotoğraf bağlantısı dizisini temizler: ≤10, yalnız geçerli genel https adresleri (diğerleri sessizce atılır) */
function cleanPhotoUrls(arr) {
  if (!Array.isArray(arr)) return [];
  return arr.filter(isPublicHttpsUrl).map((s) => s.trim()).slice(0, 10);
}

const SOURCE_SITES = ["controlx", "xmetal", "nicebodrum"];
function normalizeSourceSite(v) {
  return typeof v === "string" && SOURCE_SITES.includes(v) ? v : "controlx";
}

/** İsteğe bağlı metin alanı: string değilse hata; null/boş → null; max'ı aşarsa hata (truncate=true ise kırpılır) */
function text(v, max, { truncate = false } = {}) {
  if (v === undefined || v === null) return { value: null };
  if (typeof v !== "string") return { error: true };
  const s = v.trim();
  if (s === "") return { value: null };
  if (s.length > max) return truncate ? { value: s.slice(0, max) } : { error: true };
  return { value: s };
}

const WEAK_PASSWORDS = new Set(["123456", "1234567", "12345678", "123456789", "1234567890", "password", "parola", "sifre", "şifre", "qwerty", "qwerty123", "111111", "000000", "abc123", "iloveyou", "12341234", "11111111", "password1"]);

/** Şifre doğrulaması: string, en az PASSWORD_MIN_LENGTH (varsayılan 6, alt sınır 6), bcrypt için ≤72 bayt, yaygın şifreler yasak */
function validatePassword(pw) {
  const min = Math.max(6, Number(process.env.PASSWORD_MIN_LENGTH) || 6);
  if (typeof pw !== "string") return "Şifre metin olmalıdır.";
  if (pw.length < min) return `Şifre en az ${min} karakter olmalıdır.`;
  if (Buffer.byteLength(pw, "utf8") > 72) return "Şifre en çok 72 bayt (yaklaşık 72 karakter) olabilir.";
  if (WEAK_PASSWORDS.has(pw.toLowerCase())) return "Bu şifre çok yaygın; daha güçlü bir şifre seçin.";
  return null;
}

module.exports = { parseEmail, isAllowedPushEndpoint, isPublicHttpsUrl, cleanPhotoUrls, normalizeSourceSite, SOURCE_SITES, text, validatePassword };
