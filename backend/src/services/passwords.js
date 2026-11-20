// bcrypt maliyet faktörü (BCRYPT_ROUNDS, varsayılan 12; 10..14 arasına sıkıştırılır). Eski (10) özetler girişte aynen doğrulanır.
const BCRYPT_ROUNDS = Math.min(Math.max(parseInt(process.env.BCRYPT_ROUNDS, 10) || 12, 10), 14);
module.exports = { BCRYPT_ROUNDS };
