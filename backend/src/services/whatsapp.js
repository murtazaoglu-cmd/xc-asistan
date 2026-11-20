const axios = require("axios");
const fs = require("fs");
require("dotenv").config();

// WHATSAPP_API_BASE yalnızca test/sahte sunucu içindir; boşsa Meta Graph API kullanılır
const WA_API = `${process.env.WHATSAPP_API_BASE || "https://graph.facebook.com/v19.0"}/${process.env.WHATSAPP_PHONE_NUMBER_ID}`;
const headers = {
  Authorization: `Bearer ${process.env.WHATSAPP_ACCESS_TOKEN}`,
};

/**
 * Verilen numaraya düz metin mesajı gönderir.
 * Not: Kullanıcı son 24 saat içinde firmaya mesaj atmadıysa,
 * Meta serbest metin mesajını değil, önceden onaylı bir "template" mesajını kabul eder.
 */
async function sendText(toPhone, message) {
  const payload = {
    messaging_product: "whatsapp",
    to: normalizePhone(toPhone),
    type: "text",
    text: { body: message },
  };
  const { data } = await axios.post(`${WA_API}/messages`, payload, { headers });
  return data;
}

/**
 * Yerel diskteki bir PDF dosyasını WhatsApp'a yükler ve döndürülen media_id ile
 * müşteriye doküman olarak gönderir.
 */
async function sendDocument(toPhone, filePath, fileName, caption) {
  const FormData = require("form-data");
  const form = new FormData();
  form.append("messaging_product", "whatsapp");
  form.append("file", fs.createReadStream(filePath));
  form.append("type", "application/pdf");

  const uploadRes = await axios.post(`${WA_API}/media`, form, {
    headers: { ...headers, ...form.getHeaders() },
  });
  const mediaId = uploadRes.data.id;

  const payload = {
    messaging_product: "whatsapp",
    to: normalizePhone(toPhone),
    type: "document",
    document: { id: mediaId, filename: fileName, caption },
  };
  const { data } = await axios.post(`${WA_API}/messages`, payload, { headers });
  return data;
}

/**
 * Firmaya (admin) yeni teklif geldiğinde anlık bildirim gönderir.
 */
async function notifyAdminNewOffer(offer) {
  if (!process.env.ADMIN_WHATSAPP_NUMBER) return { skipped: true }; // numara tanımsızsa sessizce atla (eskiden her tekliften sonra "Bildirim hatası" logu düşerdi)
  const msg =
    `🔔 Yeni Teklif Talebi\n\n` +
    `Ad: ${offer.name}\n` +
    `Telefon: ${offer.phone}\n` +
    `Hizmet: ${offer.service}\n` +
    `Bölge: ${offer.region || "-"}\n` +
    `Not: ${offer.message || "-"}\n\n` +
    `Panelden görüntüle: ${process.env.APP_URL}/admin/offers/${offer.id}`;
  return sendText(process.env.ADMIN_WHATSAPP_NUMBER, msg);
}

/**
 * Gönderim hatasını kullanıcıya gösterilebilir Türkçe metne çevirir (token/URL gibi ayrıntılar sızmaz).
 * Meta hata kodları: 131047/131026 = 24 saat penceresi dışı / ulaşılamıyor, 190 = token geçersiz, 100/131009 = parametre.
 */
function describeError(err) {
  const meta = err && err.response && err.response.data && err.response.data.error;
  if (meta) {
    const code = meta.code;
    if (code === 131047) return "WhatsApp 24 saat kuralı: müşteri son 24 saatte yazmadığı için serbest mesaj/doküman gönderilemedi (onaylı şablon gerekir).";
    if (code === 131026) return "Mesaj müşterinin WhatsApp numarasına ulaştırılamadı (numara WhatsApp kullanmıyor olabilir).";
    if (code === 190) return "WhatsApp erişim anahtarı (token) geçersiz veya süresi dolmuş.";
    return `WhatsApp hatası${code ? " (" + code + ")" : ""}: ${String(meta.message || "bilinmeyen hata").slice(0, 200)}`;
  }
  if (err && err.code === "ECONNREFUSED") return "WhatsApp servisine bağlanılamadı.";
  if (err && err.code === "ENOTFOUND") return "WhatsApp servisine bağlanılamadı (ağ/DNS hatası).";
  if (!process.env.WHATSAPP_PHONE_NUMBER_ID || !process.env.WHATSAPP_ACCESS_TOKEN) return "WhatsApp yapılandırılmamış (WHATSAPP_PHONE_NUMBER_ID / WHATSAPP_ACCESS_TOKEN).";
  return `WhatsApp gönderilemedi${err && err.code ? " (" + String(err.code).slice(0, 30) + ")" : ""}.`;
}

function normalizePhone(phone) {
  // WhatsApp Cloud API, ülke koduyla ve rakamlardan oluşan format bekler (örn. 905321112233)
  let digits = phone.replace(/\D/g, "");
  if (digits.startsWith("0")) digits = "90" + digits.slice(1);
  if (!digits.startsWith("90") && digits.length === 10) digits = "90" + digits;
  return digits;
}

module.exports = { sendText, sendDocument, notifyAdminNewOffer, normalizePhone, describeError };
