/**
 * Onaylanan komutu MEVCUT REST uçlarından (aynı yetki/sahiplik/doğrulama/aktivite günlüğü kodu) çalıştırır.
 * Neden döngü-geri (loopback) HTTP: iş mantığı route dosyalarında yaşar; kopyalamak yerine gerçek uç çağrılır → asistan ile panel
 * AYNI kuralları uygular ve ikisi ayrışamaz. İsteği imzalayan jeton YALNIZ onay veren kullanıcıya ait, 60 sn ömürlüdür
 * (yetki yükseltme yok; kullanıcının rolü/token_version'ı olduğu gibi geçerlidir).
 * Taban adres: isteğin geldiği yuva (req.socket.local*) ya da ASSISTANT_INTERNAL_BASE.
 */
const jwt = require("jsonwebtoken");

function baseFor(req) {
  if (process.env.ASSISTANT_INTERNAL_BASE) return process.env.ASSISTANT_INTERNAL_BASE.replace(/\/+$/, "");
  const s = req && req.socket;
  let host = (s && s.localAddress) || "127.0.0.1";
  const port = (s && s.localPort) || process.env.PORT || 4000;
  host = host.replace(/^::ffff:/, "");
  if (host === "::" || host === "0.0.0.0") host = "127.0.0.1";
  if (host === "::1") host = "[::1]";
  else if (host.includes(":")) host = `[${host}]`;
  return `http://${host}:${port}`;
}

/** @returns {Promise<{ok:boolean,status:number,body:any}>} */
async function callApi(req, user, method, path, body) {
  const token = jwt.sign({ id: user.id, name: user.name, role: user.role, tv: user.tv || 0, cl: "web" }, process.env.JWT_SECRET, { algorithm: "HS256", expiresIn: 60 });
  let res;
  try {
    res = await fetch(baseFor(req) + "/api" + path, {
      method,
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + token, "X-Assistant-Internal": "1" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
  } catch (err) {
    return { ok: false, status: 502, body: { error: "İşlem şu an uygulanamadı (dahili çağrı başarısız)." } };
  }
  let j = null; try { j = await res.json(); } catch { /* yanıt gövdesiz */ }
  return { ok: res.ok, status: res.status, body: j };
}

module.exports = { callApi, baseFor };
