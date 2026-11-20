/**
 * Güvenli, bağımlılıksız ZIP okuyucu — YALNIZ WhatsApp dışa aktarma .zip'inden sohbet .txt dosyasını bellekte açar.
 * Hiçbir şey diske yazılmaz; girdi adları yol olarak KULLANILMAZ (yol geçişi mümkün değil).
 *
 * Savunmalar:
 *  - yol geçişi: ".." parçalı, mutlak yollu, ters eğik çizgili, sürücü harfli, NUL içeren herhangi bir girdi → arşiv reddedilir
 *  - zip bombası: bildirilen açılmış boyut sınırı (MAX_TEXT), sıkıştırma oranı sınırı, çıktı boyutu zlib maxOutputLength ile sınırlanır,
 *    gerçek açılan boyut doğrulanır, CRC32 doğrulanır; yalnız TEK bir girdi açılır (iç içe zip/medya hiç açılmaz)
 *  - girdi sayısı sınırı, şifreli girdi / ZIP64 / desteklenmeyen yöntem → ret
 */
const zlib = require("zlib");

const LIMITS = {
  maxEntries: 5000,
  maxTextBytes: 12 * 1024 * 1024,   // açılmış sohbet metni
  maxRatio: 200,                    // açılmış / sıkıştırılmış
};

class ZipError extends Error {
  constructor(code, message) { super(message); this.code = code; this.status = code === "zip_too_large" ? 413 : 400; this.expose = true; }
}

const CRC_TABLE = (() => { const t = new Uint32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(buf) { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }

function unsafeName(name) {
  if (name.includes("\0") || name.includes("\\")) return true;
  if (name.startsWith("/") || /^[A-Za-z]:/.test(name)) return true;
  return name.split("/").some((p) => p === "..");
}

/** buf: ZIP dosyası (Buffer). Dönüş: {name, text(Buffer), entries:n, skipped:n} */
function extractChatText(buf, limits = {}) {
  const L = { ...LIMITS, ...limits };
  if (!Buffer.isBuffer(buf) || buf.length < 22) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
  // EOCD: son 64KB+22 içinde imza ara
  const minPos = Math.max(0, buf.length - 65557);
  let eocd = -1;
  for (let i = buf.length - 22; i >= minPos; i--) if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
  const total = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOff = buf.readUInt32LE(eocd + 16);
  if (total === 0xffff || cdSize === 0xffffffff || cdOff === 0xffffffff) throw new ZipError("zip_unsupported", "ZIP64 arşivler desteklenmiyor.");
  if (total > L.maxEntries) throw new ZipError("zip_too_many", "ZIP içinde çok fazla dosya var. Sohbeti 'Medya olmadan' dışa aktarın.");
  if (cdOff + cdSize > buf.length) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");

  const entries = [];
  let p = cdOff;
  for (let i = 0; i < total; i++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
    const flags = buf.readUInt16LE(p + 8), method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16), csize = buf.readUInt32LE(p + 20), usize = buf.readUInt32LE(p + 24);
    const nlen = buf.readUInt16LE(p + 28), xlen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32);
    const lho = buf.readUInt32LE(p + 42);
    if (p + 46 + nlen > buf.length) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
    const utf8 = (flags & 0x800) !== 0;
    const name = buf.slice(p + 46, p + 46 + nlen).toString(utf8 ? "utf8" : "latin1");
    if (csize === 0xffffffff || usize === 0xffffffff || lho === 0xffffffff) throw new ZipError("zip_unsupported", "ZIP64 arşivler desteklenmiyor.");
    entries.push({ name, flags, method, crc, csize, usize, lho });
    p += 46 + nlen + xlen + clen;
  }
  // yol geçişi: TÜM adlar denetlenir (açılmayacak olanlar dâhil)
  for (const e of entries) if (unsafeName(e.name)) throw new ZipError("zip_path_traversal", "ZIP içinde güvenli olmayan dosya yolu var.");

  const txts = entries.filter((e) => !e.name.endsWith("/") && /\.txt$/i.test(e.name));
  if (!txts.length) throw new ZipError("zip_no_chat", "ZIP içinde sohbet (.txt) dosyası bulunamadı.");
  // tercih: "_chat.txt", yoksa en büyük .txt
  const e = txts.find((x) => /(^|\/)_chat\.txt$/i.test(x.name)) || txts.sort((a, b) => b.usize - a.usize)[0];
  if (e.flags & 1) throw new ZipError("zip_encrypted", "Şifreli ZIP desteklenmiyor.");
  if (e.method !== 0 && e.method !== 8) throw new ZipError("zip_unsupported", "Desteklenmeyen ZIP sıkıştırma yöntemi.");
  if (e.usize > L.maxTextBytes) throw new ZipError("zip_too_large", "Sohbet dosyası çok büyük.");
  if (e.usize > 1024 * 1024 && e.csize > 0 && e.usize / e.csize > L.maxRatio) throw new ZipError("zip_bomb", "Şüpheli sıkıştırma oranı; dosya reddedildi.");

  // yerel başlık
  const lh = e.lho;
  if (lh + 30 > buf.length || buf.readUInt32LE(lh) !== 0x04034b50) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
  const lnlen = buf.readUInt16LE(lh + 26), lxlen = buf.readUInt16LE(lh + 28);
  const dataStart = lh + 30 + lnlen + lxlen;
  if (dataStart + e.csize > buf.length) throw new ZipError("zip_invalid", "Geçersiz ZIP dosyası.");
  const raw = buf.slice(dataStart, dataStart + e.csize);
  let out;
  if (e.method === 0) out = raw;
  else {
    try { out = zlib.inflateRawSync(raw, { maxOutputLength: Math.min(L.maxTextBytes, Math.max(e.usize, 1)) + 1 }); }
    catch (err) {
      if (err && (err.code === "ERR_BUFFER_TOO_LARGE" || /larger than/i.test(err.message || ""))) throw new ZipError("zip_bomb", "Açılan veri bildirilenden büyük; dosya reddedildi.");
      throw new ZipError("zip_invalid", "ZIP içeriği okunamadı.");
    }
  }
  if (out.length > L.maxTextBytes) throw new ZipError("zip_too_large", "Sohbet dosyası çok büyük.");
  if (out.length !== e.usize) throw new ZipError("zip_invalid", "ZIP boyut bilgisi tutarsız.");
  if (crc32(out) !== e.crc) throw new ZipError("zip_invalid", "ZIP içeriği bozuk (CRC).");
  return { name: e.name.split("/").pop(), text: out, entries: entries.length, skipped: entries.length - 1 };
}

module.exports = { extractChatText, ZipError, crc32, LIMITS };
