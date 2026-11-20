const db = require("../db");

function badRequest(message) {
  const err = new Error(message);
  err.status = 400;
  return err;
}

/**
 * Adres + konum alanlarını doğrular. Yalnızca gövdede bulunan alanları döner (PATCH için uygun):
 *  - address: metin, en çok 500 karakter; null/"" → temizler
 *  - lat/lng: birlikte gönderilmeli; lat -90..90, lng -180..180; null/"" → ikisini de temizler
 * Hata durumunda {error} döner.
 */
function parseGeoFields(body) {
  const out = {};
  if (body.address !== undefined) {
    if (body.address === null || body.address === "") out.address = null;
    else if (typeof body.address !== "string") return { error: "Adres metin olmalıdır." };
    else {
      const a = body.address.trim();
      if (a.length > 500) return { error: "Adres en çok 500 karakter olabilir." };
      out.address = a || null;
    }
  }
  if (body.lat !== undefined || body.lng !== undefined) {
    const blank = (v) => v === null || v === "";
    if (body.lat === undefined || body.lng === undefined) return { error: "lat ve lng birlikte gönderilmelidir." };
    if (blank(body.lat) && blank(body.lng)) { out.lat = null; out.lng = null; }
    else if (blank(body.lat) || blank(body.lng)) return { error: "lat ve lng birlikte gönderilmelidir." };
    else {
      const lat = Number(body.lat), lng = Number(body.lng);
      if (!Number.isFinite(lat) || lat < -90 || lat > 90) return { error: "Geçersiz enlem (lat): -90 ile 90 arasında olmalıdır." };
      if (!Number.isFinite(lng) || lng < -180 || lng > 180) return { error: "Geçersiz boylam (lng): -180 ile 180 arasında olmalıdır." };
      out.lat = lat; out.lng = lng;
    }
  }
  return { fields: out };
}

/** parseGeoFields çıktısını UPDATE ... SET listesine ekler; yeni parametre indeksini döner */
function pushGeoSets(fields, sets, params, i) {
  for (const k of ["address", "lat", "lng"]) {
    if (fields[k] !== undefined) { sets.push(`${k} = $${i++}`); params.push(fields[k]); }
  }
  return i;
}

/**
 * Liste sorguları için opsiyonel arama + sayfalama parametreleri.
 *  ?q=metin  → arama (en çok 100 karakter)
 *  ?limit=N  → 1..200   |   ?offset=N → ≥0 (limit verilmeden offset gelirse limit=50)
 * Hiçbiri yoksa paged=false ve q=null: eski davranış (tüm kayıtlar, düz dizi).
 */
function parseListParams(req) {
  const q = typeof req.query.q === "string" ? req.query.q.trim().slice(0, 100) : "";
  let limit = null, offset = 0;
  if (req.query.limit !== undefined) {
    limit = Number(req.query.limit);
    if (!Number.isInteger(limit) || limit < 1 || limit > 200) throw badRequest("limit 1 ile 200 arasında bir tam sayı olmalıdır.");
  }
  if (req.query.offset !== undefined) {
    offset = Number(req.query.offset);
    if (!Number.isInteger(offset) || offset < 0) throw badRequest("offset 0 veya daha büyük bir tam sayı olmalıdır.");
    if (limit === null) limit = 50;
  }
  const digits = q.replace(/\D/g, "");
  return {
    q: q || null,
    like: q ? `%${q.replace(/[\\%_]/g, "\\$&")}%` : null,
    digits: digits.length >= 3 ? digits : null,
    limit, offset, paged: limit !== null,
  };
}

/** q araması için "AND (...)" parçası üretir; yeni parametreleri params'a ekler. cols: ILIKE ile aranacak SQL ifadeleri */
function searchClause(pg, cols, phoneCol, params) {
  if (!pg.q) return "";
  params.push(pg.like);
  const likeIdx = params.length;
  let sql = cols.map((c) => `${c} ILIKE $${likeIdx}`).join(" OR ");
  if (phoneCol && pg.digits) {
    params.push(`%${pg.digits}%`);
    sql += ` OR regexp_replace(${phoneCol}, '[^0-9]', '', 'g') LIKE $${params.length}`;
  }
  return ` AND (${sql})`;
}

/** Sayfalı (opsiyonel) çalıştırıcı: X-Total-Count başlığı için toplam da döner */
async function queryList(baseSql, params, orderSql, pg) {
  if (!pg.paged) {
    const { rows } = await db.query(`${baseSql} ${orderSql}`, params);
    return { rows, total: rows.length };
  }
  const [r, c] = await Promise.all([
    db.query(`${baseSql} ${orderSql} LIMIT ${pg.limit} OFFSET ${pg.offset}`, params),
    db.query(`SELECT COUNT(*)::int AS n FROM (${baseSql}) t`, params),
  ]);
  return { rows: r.rows, total: c.rows[0].n };
}

/** Liste yanıtı: gövde her zaman DÜZ DİZİ (eski istemciler bozulmaz); toplam X-Total-Count başlığında */
function sendList(res, pg, result) {
  if (pg.paged || pg.q) res.set("X-Total-Count", String(result.total));
  res.json(result.rows);
}

module.exports = { badRequest, parseGeoFields, pushGeoSets, parseListParams, searchClause, queryList, sendList };
