// ============================================================================
//  ナイトだんどり / Edge Functions の振り分け役（AWS 版）
//
//  Supabase のクラウドが裏でやっている仕事を、ここで肩代わりします。
//   1. ログインの鍵（JWT）を確かめる
//      ただし NO_VERIFY_JWT に書いた関数（LINE の受け口）は確かめない
//   2. /ai → 3_サーバー/ai のように、名前で関数を呼び分ける
//
//  Supabase 公式のセルフホスト版 main/index.ts を、だんどり用に小さくしたものです。
// ============================================================================
// 外のライブラリは使わない（起動時にネットから取りに行かずに済むように）
const KEY = crypto.subtle.importKey(
  "raw", new TextEncoder().encode(Deno.env.get("JWT_SECRET") ?? ""),
  { name: "HMAC", hash: "SHA-256" }, false, ["verify"],
);

function b64url(s: string): Uint8Array {
  const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
  return Uint8Array.from(b, (c) => c.charCodeAt(0));
}

// HS256 の署名と期限を確かめる（Supabase の anon / service_role / ログインの鍵）
async function verifyHs256(token: string): Promise<boolean> {
  const p = token.split(".");
  if (p.length !== 3) return false;
  const head = JSON.parse(new TextDecoder().decode(b64url(p[0])));
  if (head.alg !== "HS256") return false;
  const ok = await crypto.subtle.verify("HMAC", await KEY, b64url(p[2]), new TextEncoder().encode(`${p[0]}.${p[1]}`));
  if (!ok) return false;
  const body = JSON.parse(new TextDecoder().decode(b64url(p[1])));
  return typeof body.exp !== "number" || body.exp > Date.now() / 1000;
}

const NO_VERIFY = new Set(
  (Deno.env.get("NO_VERIFY_JWT") ?? "line-webhook").split(",").map((s) => s.trim()).filter(Boolean),
);
const NAME_OK = /^[a-z0-9][a-z0-9_-]*$/;

function fail(status: number, code: string, message: string) {
  return Response.json({ code, message, msg: message }, { status });
}

async function checkJwt(req: Request): Promise<Response | null> {
  const parts = (req.headers.get("authorization") ?? "").trim().split(/\s+/);
  if (parts.length !== 2 || parts[0].toLowerCase() !== "bearer") {
    return fail(401, "UNAUTHORIZED_NO_AUTH_HEADER", "Missing authorization header");
  }
  try {
    if (await verifyHs256(parts[1])) return null;
  } catch (_e) { /* 形がおかしい鍵 */ }
  return fail(401, "UNAUTHORIZED_LEGACY_JWT", "Invalid JWT");
}

Deno.serve(async (req: Request) => {
  const name = new URL(req.url).pathname.split("/")[1] ?? "";
  if (name === "_health") return new Response("ok");
  if (!NAME_OK.test(name) || name === "main") {
    return fail(404, "NOT_FOUND", "Requested function was not found");
  }

  const servicePath = `/home/deno/functions/${name}`;
  try {
    if (!(await Deno.stat(servicePath)).isDirectory) throw new Deno.errors.NotFound();
  } catch (_e) {
    return fail(404, "NOT_FOUND", "Requested function was not found");
  }

  if (req.method !== "OPTIONS" && !NO_VERIFY.has(name)) {
    const ng = await checkJwt(req);
    if (ng) return ng;
  }

  try {
    const env = { ...Deno.env.toObject(), SUPABASE_FUNCTION_SLUG: name };
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath,
      memoryLimitMb: 256,
      workerTimeoutMs: 400_000,
      noModuleCache: false,
      envVars: Object.entries(env),
    });
    return await worker.fetch(req);
  } catch (e) {
    console.error(name, e);
    return fail(500, "EDGE_FUNCTION_ERROR", "Function exited due to an error (please check logs)");
  }
});
