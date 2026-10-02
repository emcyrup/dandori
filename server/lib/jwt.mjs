// ログインの鍵（JWT, HS256）を作る・確かめる。外部ライブラリなし。
import crypto from "node:crypto";

const b64 = (buf) => Buffer.from(buf).toString("base64url");

export function sign(payload, secret) {
  const head = b64(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64(JSON.stringify(payload));
  const sig = crypto.createHmac("sha256", secret).update(`${head}.${body}`).digest("base64url");
  return `${head}.${body}.${sig}`;
}

// 正しければ中身（claims）を返す。だめなら null。
export function verify(token, secret) {
  try {
    const p = String(token || "").split(".");
    if (p.length !== 3) return null;
    const head = JSON.parse(Buffer.from(p[0], "base64url").toString());
    if (head.alg !== "HS256") return null;
    const want = crypto.createHmac("sha256", secret).update(`${p[0]}.${p[1]}`).digest();
    const got = Buffer.from(p[2], "base64url");
    if (want.length !== got.length || !crypto.timingSafeEqual(want, got)) return null;
    const body = JSON.parse(Buffer.from(p[1], "base64url").toString());
    if (typeof body.exp === "number" && body.exp <= Date.now() / 1000) return null;
    return body;
  } catch {
    return null;
  }
}

// "Authorization: Bearer xxx" から鍵を取り出す
export function bearer(req) {
  const m = /^Bearer\s+(\S+)$/i.exec(req.headers.authorization || "");
  return m ? m[1] : null;
}
