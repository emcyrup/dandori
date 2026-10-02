// ============================================================================
//  ナイトだんどり / ファイル置き場（Supabase Storage の代わり・小さな実装）
//
//  画面の supabase.js が使う Storage の API のうち、だんどりが使うものだけを実装しています。
//    POST   /object/{bucket}/{path}          アップロード（x-upsert: true で上書き）
//    POST   /object/sign/{bucket}/{path}     期限つきリンクを作る
//    GET    /object/sign/{bucket}/{path}?token=…  期限つきリンクでダウンロード
//    GET    /object/authenticated/{bucket}/{path} ログイン中の方がダウンロード
//    POST   /object/list/{bucket}            一覧
//    DELETE /object/{bucket}                 削除（{"prefixes":[…]}）
//    GET    /bucket, GET /bucket/{id}, POST /bucket
//
//  だれが何を見られるかは、Supabase と同じく storage.objects の RLS に任せます。
//  （ログインした方の役割でデータベースに入り、ポリシーに判定してもらう）
//  ファイルの中身は data/storage/<bucket>/<path> に置きます。
// ============================================================================
import http from "node:http";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import crypto from "node:crypto";
import pg from "pg";
import { sign, verify, bearer } from "../lib/jwt.mjs";

const env = process.env;
const PORT = Number(env.STORAGE_PORT || 38034);
const ROOT = path.resolve(env.STORAGE_DIR || path.join(import.meta.dirname, "..", "data", "storage"));
const JWT_SECRET = env.JWT_SECRET;
const LIMIT = Number(env.FILE_SIZE_LIMIT || 50 * 1024 * 1024);
const ROLES = new Set(["anon", "authenticated", "service_role"]);
if (!JWT_SECRET || !env.DATABASE_URL) { console.error("JWT_SECRET / DATABASE_URL が空です"); process.exit(1); }

const pool = new pg.Pool({ connectionString: env.DATABASE_URL, max: 5 });
fs.mkdirSync(ROOT, { recursive: true });

class HttpError extends Error { constructor(status, error, message) { super(message); this.status = status; this.error = error; } }
const E = {
  unauth: () => new HttpError(401, "Unauthorized", "ログインが必要です"),
  denied: () => new HttpError(403, "Unauthorized", "new row violates row-level security policy"),
  notFound: () => new HttpError(404, "not_found", "Object not found"),
  dup: () => new HttpError(400, "Duplicate", "The resource already exists"),
  bad: (m) => new HttpError(400, "InvalidRequest", m),
};

// ---- 小道具
function send(res, status, body, headers = {}) {
  const s = typeof body === "string" ? body : JSON.stringify(body);
  res.writeHead(status, { "Content-Type": typeof body === "string" ? "text/plain; charset=utf-8" : "application/json; charset=utf-8", ...headers });
  res.end(s);
}
function sendError(res, e) {
  if (e instanceof HttpError) return send(res, e.status, { statusCode: String(e.status), error: e.error, message: e.message });
  if (e && e.code === "42501") return send(res, 403, { statusCode: "403", error: "Unauthorized", message: "new row violates row-level security policy", code: "AccessDenied" });
  if (e && e.code === "23505") return send(res, 400, { statusCode: "409", error: "Duplicate", message: "The resource already exists" });
  console.error(e);
  send(res, 500, { statusCode: "500", error: "Internal", message: String(e && e.message || e) });
}
function readBody(req, max = LIMIT) {
  return new Promise((ok, ng) => {
    const parts = []; let n = 0;
    req.on("data", (c) => { n += c.length; if (n > max) { ng(E.bad("ファイルが大きすぎます")); req.destroy(); } else parts.push(c); });
    req.on("end", () => ok(Buffer.concat(parts)));
    req.on("error", ng);
  });
}
async function readJson(req) {
  const b = await readBody(req, 1 << 20);
  if (!b.length) return {};
  try { return JSON.parse(b.toString()); } catch { throw E.bad("JSON が読めません"); }
}
// "docs/2026/a.pdf" → { bucket: "docs", name: "2026/a.pdf" }。危ない文字は断る
function splitKey(rest) {
  const segs = rest.split("/").map((s) => decodeURIComponent(s));
  const bucket = segs.shift();
  if (!bucket || !segs.length || segs.some((s) => !s || s === "." || s === ".." || s.includes("\0"))) throw E.bad("Invalid key");
  if (!/^[A-Za-z0-9_-]+$/.test(bucket)) throw E.bad("Invalid bucket");
  return { bucket, name: segs.join("/") };
}
const diskPath = (bucket, name) => path.join(ROOT, bucket, ...name.split("/"));

// ログインした方の役割でデータベースの仕事をする（RLS が効く）
async function asUser(claims, fn) {
  const c = await pool.connect();
  try {
    await c.query("begin");
    const role = ROLES.has(claims && claims.role) ? claims.role : "anon";
    await c.query(`set local role ${role}`);
    await c.query("select set_config('request.jwt.claims', $1, true), set_config('request.jwt.claim.sub', $2, true), set_config('request.jwt.claim.role', $3, true)",
      [JSON.stringify(claims || {}), (claims && claims.sub) || "", role]);
    const r = await fn(c);
    await c.query("commit");
    return r;
  } catch (e) {
    await c.query("rollback").catch(() => {});
    throw e;
  } finally { c.release(); }
}
function auth(req) {
  const tok = bearer(req);
  if (!tok) throw E.unauth();
  const claims = verify(tok, JWT_SECRET);
  if (!claims) throw E.unauth();
  return claims;
}

// ---- アップロードの中身を取り出す（ブラウザは multipart、curl などは生のまま）
async function readUpload(req) {
  const ct = req.headers["content-type"] || "";
  if (ct.startsWith("multipart/form-data")) {
    const raw = await readBody(req);
    let fd;
    try { fd = await new Response(raw, { headers: { "content-type": ct } }).formData(); }
    catch { throw E.bad("multipart の形が読めません（各パートに name= が必要です）"); }
    let file = null, cacheControl = "3600";
    for (const [k, v] of fd.entries()) {
      if (v instanceof Blob) file = v;
      else if (k === "cacheControl") cacheControl = String(v);
    }
    if (!file) throw E.bad("ファイルがありません");
    const buf = Buffer.from(await file.arrayBuffer());
    if (buf.length > LIMIT) throw E.bad("ファイルが大きすぎます");
    return { buf, mimetype: file.type || "application/octet-stream", cacheControl };
  }
  const buf = await readBody(req);
  const cc = /max-age=(\d+)/.exec(req.headers["cache-control"] || "");
  return { buf, mimetype: ct.split(";")[0] || "application/octet-stream", cacheControl: cc ? cc[1] : "3600" };
}

async function streamFile(res, bucket, name, meta, download) {
  const p = diskPath(bucket, name);
  let st; try { st = await fsp.stat(p); } catch { throw E.notFound(); }
  const h = {
    "Content-Type": (meta && meta.mimetype) || "application/octet-stream",
    "Content-Length": st.size,
    "Cache-Control": `max-age=${(meta && meta.cacheControl) || 3600}`,
    ETag: `"${(meta && meta.eTag) || st.mtimeMs}"`,
  };
  if (download !== undefined) h["Content-Disposition"] = `attachment; filename*=UTF-8''${encodeURIComponent(download || path.basename(name))}`;
  res.writeHead(200, h);
  fs.createReadStream(p).pipe(res);
}

// ---- 各 API
async function upload(req, res, rest) {
  const claims = auth(req);
  const { bucket, name } = splitKey(rest);
  const upsert = String(req.headers["x-upsert"] || "").toLowerCase() === "true";
  const { buf, mimetype, cacheControl } = await readUpload(req);
  const metadata = { mimetype, size: buf.length, cacheControl: `max-age=${cacheControl}`, eTag: `"${crypto.createHash("md5").update(buf).digest("hex")}"`, lastModified: new Date().toISOString(), contentLength: buf.length, httpStatusCode: 200 };
  // バケットの有無は（RLS の外で）先に確かめる。中身の可否は RLS に任せる
  const b = await pool.query("select 1 from storage.buckets where id = $1", [bucket]);
  if (!b.rowCount) throw new HttpError(404, "Bucket not found", "Bucket not found");
  const id = await asUser(claims, async (c) => {
    if (upsert) {
      const r = await c.query(
        `insert into storage.objects (bucket_id, name, owner, owner_id, metadata, version)
         values ($1, $2, $3::uuid, $3, $4, $5)
         on conflict (bucket_id, name) do update set metadata = excluded.metadata, version = excluded.version, updated_at = now(), last_accessed_at = now()
         returning id`, [bucket, name, claims.sub || null, metadata, crypto.randomUUID()]);
      if (!r.rowCount) throw E.denied();
      return r.rows[0].id;
    }
    const r = await c.query(
      `insert into storage.objects (bucket_id, name, owner, owner_id, metadata, version) values ($1, $2, $3::uuid, $3, $4, $5) returning id`,
      [bucket, name, claims.sub || null, metadata, crypto.randomUUID()]);
    return r.rows[0].id;
  });
  const p = diskPath(bucket, name);
  await fsp.mkdir(path.dirname(p), { recursive: true });
  await fsp.writeFile(p, buf);
  send(res, 200, { Key: `${bucket}/${name}`, Id: id });
}

async function signUrl(req, res, rest) {
  const claims = auth(req);
  const { bucket, name } = splitKey(rest);
  const body = await readJson(req);
  const expiresIn = Math.min(Math.max(Number(body.expiresIn) || 60, 1), 7 * 86400);
  const found = await asUser(claims, (c) => c.query("select id from storage.objects where bucket_id = $1 and name = $2", [bucket, name]));
  if (!found.rowCount) throw E.notFound();
  const token = sign({ url: `${bucket}/${name}`, iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + expiresIn }, JWT_SECRET);
  send(res, 200, { signedURL: `/object/sign/${bucket}/${name}?token=${token}` });
}

async function getSigned(req, res, rest, query) {
  const { bucket, name } = splitKey(rest);
  const claims = verify(query.get("token"), JWT_SECRET);
  if (!claims || claims.url !== `${bucket}/${name}`) throw new HttpError(400, "InvalidJWT", "リンクの期限が切れています");
  const r = await pool.query("select metadata from storage.objects where bucket_id = $1 and name = $2", [bucket, name]);
  if (!r.rowCount) throw E.notFound();
  await streamFile(res, bucket, name, r.rows[0].metadata, query.has("download") ? query.get("download") : undefined);
}

async function getAuthenticated(req, res, rest, query) {
  const claims = auth(req);
  const { bucket, name } = splitKey(rest);
  const r = await asUser(claims, (c) => c.query("select metadata from storage.objects where bucket_id = $1 and name = $2", [bucket, name]));
  if (!r.rowCount) throw E.notFound();
  await streamFile(res, bucket, name, r.rows[0].metadata, query.has("download") ? query.get("download") : undefined);
}

async function list(req, res, rest) {
  const claims = auth(req);
  const bucket = rest.split("/")[0];
  const body = await readJson(req);
  const prefix = String(body.prefix || "").replace(/^\/+|\/+$/g, "");
  const base = prefix ? prefix + "/" : "";
  const limit = Math.min(Number(body.limit) || 100, 1000), offset = Number(body.offset) || 0;
  const rows = await asUser(claims, (c) => c.query(
    "select id, name, updated_at, created_at, last_accessed_at, metadata from storage.objects where bucket_id = $1 and name like $2 || '%' order by name",
    [bucket, base.replace(/[%_]/g, "\\$&")]));
  const items = new Map();
  for (const o of rows.rows) {
    const tail = o.name.slice(base.length);
    const seg = tail.split("/")[0];
    if (tail.includes("/")) { if (!items.has(seg)) items.set(seg, { name: seg, id: null, updated_at: null, created_at: null, last_accessed_at: null, metadata: null }); }
    else items.set(seg, { name: seg, id: o.id, updated_at: o.updated_at, created_at: o.created_at, last_accessed_at: o.last_accessed_at, metadata: o.metadata });
  }
  let out = [...items.values()];
  const sb = body.sortBy || {};
  if (sb.column && sb.column !== "name") out.sort((a, b) => String(a[sb.column] || "").localeCompare(String(b[sb.column] || "")));
  if (sb.order === "desc") out.reverse();
  send(res, 200, out.slice(offset, offset + limit));
}

async function remove(req, res, rest) {
  const claims = auth(req);
  const bucket = rest.split("/")[0];
  const body = await readJson(req);
  const prefixes = Array.isArray(body.prefixes) ? body.prefixes : [];
  const r = await asUser(claims, (c) => c.query(
    "delete from storage.objects where bucket_id = $1 and name = any($2) returning id, name, bucket_id, metadata", [bucket, prefixes]));
  for (const o of r.rows) await fsp.rm(diskPath(bucket, o.name), { force: true });
  send(res, 200, r.rows);
}

async function buckets(req, res, rest) {
  const claims = auth(req);
  if (req.method === "GET" && !rest) {
    const r = await pool.query("select id, name, owner, public, created_at, updated_at, file_size_limit, allowed_mime_types from storage.buckets order by id");
    return send(res, 200, r.rows);
  }
  if (req.method === "GET") {
    const r = await pool.query("select id, name, owner, public, created_at, updated_at, file_size_limit, allowed_mime_types from storage.buckets where id = $1", [decodeURIComponent(rest)]);
    if (!r.rowCount) throw new HttpError(404, "Bucket not found", "Bucket not found");
    return send(res, 200, r.rows[0]);
  }
  if (req.method === "POST") {
    if (claims.role !== "service_role") throw E.denied();
    const b = await readJson(req);
    if (!/^[A-Za-z0-9_-]+$/.test(b.id || b.name || "")) throw E.bad("Invalid bucket name");
    await pool.query("insert into storage.buckets (id, name, public) values ($1, $1, $2) on conflict (id) do nothing", [b.id || b.name, !!b.public]);
    return send(res, 200, { name: b.id || b.name });
  }
  throw E.bad("Unsupported");
}

http.createServer(async (req, res) => {
  try {
    const u = new URL(req.url, "http://x");
    const p = u.pathname.replace(/^\/+/, "");
    if (p === "status" || p === "health") return send(res, 200, "ok");
    if (p === "bucket" || p.startsWith("bucket/")) return await buckets(req, res, p.slice("bucket/".length));
    if (p.startsWith("object/sign/")) return req.method === "POST" ? await signUrl(req, res, p.slice(12)) : await getSigned(req, res, p.slice(12), u.searchParams);
    if (p.startsWith("object/authenticated/") && req.method === "GET") return await getAuthenticated(req, res, p.slice(21), u.searchParams);
    if (p.startsWith("object/list/") && req.method === "POST") return await list(req, res, p.slice(12));
    if (p.startsWith("object/") && req.method === "POST") return await upload(req, res, p.slice(7));
    if (p.startsWith("object/") && req.method === "DELETE") return await remove(req, res, p.slice(7));
    throw new HttpError(404, "not_found", `この操作には対応していません: ${req.method} /${p}`);
  } catch (e) {
    sendError(res, e);
  }
}).listen(PORT, "127.0.0.1", () => console.log(`storage: 127.0.0.1:${PORT} → ${ROOT}`));
