// Test yardımcısı: elle ZIP üretici (yalnız testler için; üretim kodu zipReader ile OKUR)
const zlib = require("zlib");
const { crc32 } = require("../../src/assistant/importer/zipReader");
function makeZip(entries) { // entries: [{name, data(Buffer), method?:0|8, flags?, fakeUsize?}]
  const locals = [], centrals = []; let off = 0;
  for (const e of entries) {
    const nameB = Buffer.from(e.name, "utf8");
    const method = e.method === undefined ? 8 : e.method;
    const comp = method === 8 ? zlib.deflateRawSync(e.data) : e.data;
    const crc = crc32(e.data);
    const usize = e.fakeUsize !== undefined ? e.fakeUsize : e.data.length;
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE((e.flags || 0) | 0x800, 6); lh.writeUInt16LE(method, 8);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(comp.length, 18); lh.writeUInt32LE(usize, 22); lh.writeUInt16LE(nameB.length, 26);
    const rec = Buffer.concat([lh, nameB, comp]);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE((e.flags || 0) | 0x800, 8); ch.writeUInt16LE(method, 10);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(usize, 24); ch.writeUInt16LE(nameB.length, 28); ch.writeUInt32LE(off, 42);
    locals.push(rec); centrals.push(Buffer.concat([ch, nameB])); off += rec.length;
  }
  const cd = Buffer.concat(centrals), eo = Buffer.alloc(22);
  eo.writeUInt32LE(0x06054b50, 0); eo.writeUInt16LE(entries.length, 8); eo.writeUInt16LE(entries.length, 10); eo.writeUInt32LE(cd.length, 12); eo.writeUInt32LE(off, 16);
  return Buffer.concat([...locals, cd, eo]);
}
module.exports = { makeZip };
