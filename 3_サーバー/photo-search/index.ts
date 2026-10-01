// ============================================================================
//  だんどりシリーズ 共通 / 背景に使う写真をさがす
//  supabase/functions/photo-search/index.ts
//
//  置き場所： Supabase の Edge Function「photo-search」
//
//  この関数がすること
//   1. ログインしている方かどうかを確かめます
//   2. Pixabay に写真をさがしに行きます
//   3. 見つかったものだけを、きれいにしてお返しします
//
//  ★ 写真をさがす鍵は、この関数の「Secrets」に入れます。
//    ブラウザには一切出ません。
//      PIXABAY_API_KEY
//
//  ★ Pixabay の決まりで、同じ問い合わせは24時間ためておく必要があります。
//    この関数の中で覚えておき、同じ言葉なら聞きに行きません。
//
//  ★ 出どころ（どのページの写真か）も、いっしょにお返しします。
//    画面でお見せするためです。
// ============================================================================

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/* 同じ言葉の結果を、24時間ためておきます（Pixabay の決まりです） */
const CACHE = new Map<string, { at: number; data: unknown }>();
const DAY = 24 * 60 * 60 * 1000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const key = Deno.env.get("PIXABAY_API_KEY") ?? "";
  const auth = req.headers.get("Authorization") ?? "";

  if (!key) {
    return json({
      error: "写真をさがす鍵が入っていません。担当までご連絡ください。",
      code: "no_key",
    }, 503);
  }

  /* ログインしている方かどうかを確かめます */
  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.45.4");
  const db = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: userRes } = await db.auth.getUser();
  if (!userRes?.user) return json({ error: "ログインが必要です" }, 401);

  /* さがす言葉 */
  let q = "";
  if (req.method === "GET") {
    q = new URL(req.url).searchParams.get("q") ?? "";
  } else {
    try { q = ((await req.json())?.q ?? "").toString(); } catch { /* 空でも進みます */ }
  }
  q = q.trim().slice(0, 100);
  if (!q) return json({ error: "さがす言葉を入れてください" }, 400);

  /* 日本語が入っていれば、日本語でさがします */
  const ja = /[ぁ-んァ-ヶ一-龠]/.test(q);
  const cacheKey = (ja ? "ja:" : "en:") + q.toLowerCase();

  const hit = CACHE.get(cacheKey);
  if (hit && Date.now() - hit.at < DAY) {
    return json({ results: hit.data, cached: true });
  }

  const api = "https://pixabay.com/api/?key=" + encodeURIComponent(key) +
    "&q=" + encodeURIComponent(q) +
    "&lang=" + (ja ? "ja" : "en") +
    "&image_type=photo&safesearch=true&orientation=horizontal&per_page=24";

  let r: Response;
  try {
    r = await fetch(api);
  } catch (e) {
    return json({ error: "写真をさがすところにつながりませんでした" }, 502);
  }
  if (!r.ok) {
    const t = await r.text().catch(() => "");
    return json({
      error: "写真をさがせませんでした（" + r.status + "）",
      detail: t.slice(0, 200),
    }, r.status === 429 ? 429 : 502);
  }

  const j = await r.json().catch(() => ({} as any));
  const results = (j.hits ?? []).map((x: any) => ({
    thumb: x.previewURL,
    full:  x.largeImageURL || x.webformatURL,
    title: (x.tags ?? "").split(",")[0]?.trim() ?? "",
    by:    x.user ?? "",
    page:  x.pageURL ?? "",
    from:  "Pixabay",
  })).filter((x: any) => x.thumb && x.full);

  CACHE.set(cacheKey, { at: Date.now(), data: results });
  return json({ results });
});
