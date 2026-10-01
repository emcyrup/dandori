// ============================================================================
//  だんどりシリーズ 共通 / AIの下書き
//  supabase/functions/ai/index.ts
//
//  置き場所： Supabase の Edge Function「ai」
//
//  この関数がすること
//   1. ログインしている方かどうかを確かめます
//   2. 数字は、かならずデータベースから取り直します（AIには作らせません）
//   3. 法人ごとに選ばれているAIへ、文章にする依頼だけを出します
//   4. 返ってきた文章を、そのままお返しします
//
//  ★ AIの鍵は、この関数の「Secrets」に入れます。
//    ブラウザには一切出ません。
//      GEMINI_API_KEY / ANTHROPIC_API_KEY / OPENAI_API_KEY
//
//    名前のつづりは、下のどれでも読みます（打ちまちがえても大丈夫なように）。
//      Gemini  : GEMINI_API_KEY / GOOGLE_API_KEY / GEMINI_KEY
//      Claude  : ANTHROPIC_API_KEY / CLAUDE_API_KEY / ANTHROPIC_KEY
//      ChatGPT : OPENAI_API_KEY / OPEN_AI_API_KEY / CHATGPT_API_KEY
//
//  ★ AIは文章を書くだけです。金額・件数は、この関数が渡した数字のままです。
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/*  鍵の名前は、打ちまちがえやすいので、よくある綴りをまとめて見にいきます。
    最初に見つかったものを使います。 */
function envKey(names: string[]): string | null {
  for (const n of names) {
    const v = (Deno.env.get(n) ?? "").trim();
    if (v) return v;
  }
  return null;
}

const KEYNAME: Record<string, string[]> = {
  gemini: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GEMINI_KEY", "GOOGLE_GEMINI_API_KEY"],
  claude: ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "ANTHROPIC_KEY", "CLAUDE_KEY"],
  openai: ["OPENAI_API_KEY", "OPEN_AI_API_KEY", "CHATGPT_API_KEY", "OPENAI_KEY"],
};

/*  鍵が見つからないときの、分かりやすいお知らせ */
function keyMissing(which: string): Error {
  const list = KEYNAME[which] || [];
  return new Error(
    "AIの鍵（キー）が見つかりません。Supabase の Edge Functions →「Secrets」に、" +
    "名前を「" + list[0] + "」にして入れてください。" +
    "（" + list.slice(1).join(" / ") + " という名前でも読みます）",
  );
}

//  ★ AIのモデルは、提供元の都合で入れ替わります。
//    古くなって使えなくなったときは、設定 →「AI」のモデル欄に
//    新しい名前を入れれば、この関数を入れ直さなくても動きます。
const DEFAULT_MODEL: Record<string, string> = {
  gemini: "gemini-3.8-flash",
  claude: "claude-sonnet-4-5",
  openai: "gpt-4.1-mini",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/* ------------------------------------------------------------------ 指示文 */

const TONE: Record<string, string> = {
  polite: "ていねいな、やわらかい日本語で書いてください。",
  plain: "短く、事実だけを並べた日本語で書いてください。",
};

const COMMON_RULES = `
守っていただきたいこと:
- わたしが渡した数字だけを使ってください。数字を足したり、丸めたり、推測したりしないでください。
- 渡していないことは書かないでください。「おそらく」「〜と思われます」は使わないでください。
- 絵文字と記号の装飾は使わないでください。
- 見出しは使わず、そのまま読める文章にしてください。
`;

function prompt(kind: string, d: Record<string, any>, tone: string): string {
  const t = TONE[tone] ?? TONE.polite;
  const yen = (n: number) => "¥" + Number(n || 0).toLocaleString("ja-JP");

  if (kind === "night_report") {
    const cats = (d.by_category ?? [])
      .map((x: any) => `${x.name} ${yen(x.amount)}`).join(" / ") || "なし";
    const casts = (d.casts ?? [])
      .map((x: any) => `${x.name}（本指名${x.nominations}本・売上${yen(x.sales)}）`)
      .join(" / ") || "なし";
    const diff = Number(d.sales || 0) - Number(d.prev_week_sales || 0);

    return `あなたは、日本のナイトビジネスのお店で日報を書く、経験のある店長です。
${t}
${COMMON_RULES}
以下の数字から、その日の日報を200〜300字で書いてください。
最後に、明日に向けて気をつけたいことを1つだけ、短く添えてください。

店舗: ${d.store}
営業日: ${d.date}（${d.weekday}）
売上: ${yen(d.sales)}
組数: ${d.groups}組 / 人数: ${d.guests}名
まだ開いている卓: ${d.open_tables}卓
出勤したキャスト: ${d.attendance}名
未回収のツケ（累計）: ${yen(d.receivable)}
何で売れたか: ${cats}
キャスト別: ${casts}
先週の同じ曜日の売上: ${yen(d.prev_week_sales)}（今日との差: ${diff >= 0 ? "+" : ""}${yen(diff)}）`;
  }

  if (kind === "cast_report") {
    const casts = (d.by_cast ?? [])
      .map((x: any) => `${x.name}（${x.bookings}本・本指名${x.nominations}本・${yen(x.sales)}）`)
      .join(" / ") || "なし";
    const media = (d.by_media ?? [])
      .map((x: any) => `${x.name} ${x.bookings}件（${yen(x.sales)}）`).join(" / ") || "なし";
    const diff = Number(d.sales || 0) - Number(d.prev_week_sales || 0);

    return `あなたは、日本の派遣型・店舗型のお店で日報を書く、経験のある店長です。
${t}
${COMMON_RULES}
以下の数字から、その日の日報を200〜300字で書いてください。
最後に、明日に向けて気をつけたいことを1つだけ、短く添えてください。

店舗: ${d.store}
営業日: ${d.date}（${d.weekday}）
受付: ${d.bookings}件（成立 ${d.done}件 / キャンセル ${d.cancels}件）
売上: ${yen(d.sales)}／キャストさまへの報酬: ${yen(d.back)}
出勤したキャスト: ${d.casts_on}名
キャスト別: ${casts}
媒体別: ${media}
先週の同じ曜日の売上: ${yen(d.prev_week_sales)}（今日との差: ${diff >= 0 ? "+" : ""}${yen(diff)}）`;
  }

  if (kind === "cast_reception") {
    return `あなたは、日本の派遣型のお店で、キャストさまへ連絡を入れる受付の担当です。
${t}
${COMMON_RULES}
以下の内容から、キャストさまへそのまま送れる連絡文を、120字以内で書いてください。
必要なのは「開始の時刻・コース・場所・お迎えの時刻」です。
お客様のお名前は出さないでください。

開始: ${d.start}から${d.minutes}分（${d.course ?? "コース未定"}）
指名: ${d.nomination ?? "なし"}
エリア: ${d.area ?? "未定"}
ご案内先: ${d.place ?? "未定"}
お迎え: ${d.depart ? `${d.depart}に${d.vehicle ?? "お車"}` : "未定"}
お客様のご利用回数: ${d.customer_visits ?? "不明"}回
うかがっていること: ${d.customer_ng ?? "とくになし"}
受付のメモ: ${d.memo ?? "なし"}`;
  }

  throw new Error("その種類の下書きは、まだ用意していません");
}

/* ------------------------------------------------------------ AIを呼ぶ部分 */

//  モデル名が入れ替わっていたときに、実際に使えた名前を覚えておきます
let LAST_MODEL = "";

/*  Google に「いま使えるモデル」を聞いて、いちばん新しい flash を選びます。
    モデル名は提供元の都合で入れ替わるので、名前が変わっても動き続けるように、
    ここで選び直せるようにしています。 */
async function geminiPickModel(key: string): Promise<string | null> {
  try {
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models?key=${key}&pageSize=200`,
    );
    if (!r.ok) return null;
    const j = await r.json();
    const names: string[] = (j?.models ?? [])
      .filter((m: any) =>
        (m?.supportedGenerationMethods ?? []).includes("generateContent"))
      .map((m: any) => String(m?.name ?? "").replace(/^models\//, ""))
      .filter((n: string) => n && !/vision|embedding|aqa|image|tts|live/i.test(n));

    //  数字の大きいもの（新しいもの）を先に。flash を優先します。
    const score = (n: string) => {
      const v = (n.match(/(\d+(?:\.\d+)?)/) ?? ["0"])[0];
      return parseFloat(v) * 10 +
        (/flash/i.test(n) ? 5 : 0) +
        (/latest|preview|exp/i.test(n) ? -1 : 0);
    };
    names.sort((a, b) => score(b) - score(a));
    return names[0] ?? null;
  } catch {
    return null;
  }
}

async function geminiOnce(model: string, text: string, key: string) {
  const r = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text }] }],
        generationConfig: { temperature: 0.4, maxOutputTokens: 800 },
      }),
    },
  );
  const j = await r.json();
  return { ok: r.ok, status: r.status, j };
}

async function callGemini(model: string, text: string): Promise<string> {
  const key = envKey(KEYNAME.gemini);
  if (!key) throw keyMissing("gemini");

  let res = await geminiOnce(model, text, key);

  //  「そのモデルは無い」と言われたら、いま使えるものを聞いて、もう一度だけ試します
  const msg0 = res.j?.error?.message ?? "";
  if (!res.ok && /not found|no longer available|not supported|deprecated/i.test(msg0)) {
    const alt = await geminiPickModel(key);
    if (alt && alt !== model) {
      const retry = await geminiOnce(alt, text, key);
      if (retry.ok) {
        LAST_MODEL = alt;
        res = retry;
      } else {
        throw new Error(
          "「" + model + "」は使えなくなっていました。" +
          "いま使えるのは「" + alt + "」のようですが、それでも動きませんでした。" +
          "（提供元からのお知らせ： " + (retry.j?.error?.message ?? msg0) + "）",
        );
      }
    } else {
      throw new Error(msg0 || `Gemini エラー (${res.status})`);
    }
  }

  if (!res.ok) {
    throw new Error(res.j?.error?.message ?? `Gemini エラー (${res.status})`);
  }
  const out = res.j?.candidates?.[0]?.content?.parts
    ?.map((p: any) => p.text).join("") ?? "";
  if (!out) throw new Error("AIからの返事が空でした");
  return out.trim();
}

async function callClaude(model: string, text: string): Promise<string> {
  const key = envKey(KEYNAME.claude);
  if (!key) throw keyMissing("claude");
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": key,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 800,
      temperature: 0.4,
      messages: [{ role: "user", content: text }],
    }),
  });
  const j = await r.json();
  if (!r.ok) {
    const m = j?.error?.message ?? `Claude エラー (${r.status})`;
    if (r.status === 429 || /credit balance|insufficient/i.test(m)) {
      throw new Error(
        "Claude（Anthropic）の残高がありません。" +
        "Anthropic Console の Billing で残高を入れるか、" +
        "設定 →「AI」を Gemini に切りかえてください。",
      );
    }
    if (r.status === 401 || /invalid.*api.*key|authentication/i.test(m)) {
      throw new Error(
        "Claude（Anthropic）の鍵が違うようです。" +
        "Supabase の Secrets に入れた ANTHROPIC_API_KEY を見なおしてください。",
      );
    }
    throw new Error(m);
  }
  const out = (j?.content ?? []).filter((c: any) => c.type === "text")
    .map((c: any) => c.text).join("");
  if (!out) throw new Error("AIからの返事が空でした");
  return out.trim();
}

async function callOpenAI(model: string, text: string): Promise<string> {
  const key = envKey(KEYNAME.openai);
  if (!key) throw keyMissing("openai");
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify({
      model,
      temperature: 0.4,
      max_tokens: 800,
      messages: [{ role: "user", content: text }],
    }),
  });
  const j = await r.json();
  if (!r.ok) {
    const m = j?.error?.message ?? `OpenAI エラー (${r.status})`;
    const code = j?.error?.code ?? "";
    //  「残高ぎれ」は、そのままだと分かりにくいので言いかえます
    if (r.status === 429 || /insufficient_quota|exceeded your current quota|billing/i.test(m + code)) {
      throw new Error(
        "ChatGPT（OpenAI）の残高がありません。" +
        "OpenAI は、ChatGPT の月ぎめとは別に、前払いの残高が要ります。" +
        "残高を入れるか、設定 →「AI」を Gemini に切りかえてください。",
      );
    }
    if (r.status === 401 || /invalid_api_key|Incorrect API key/i.test(m + code)) {
      throw new Error(
        "ChatGPT（OpenAI）の鍵が違うようです。" +
        "Supabase の Secrets に入れた OPENAI_API_KEY を見なおしてください。",
      );
    }
    if (/does not exist|do not have access to the model/i.test(m)) {
      throw new Error(
        "いま選ばれているモデル「" + model + "」は、このアカウントでは使えません。" +
        "設定 →「AI」のモデル欄を gpt-4.1-mini などに直してください。",
      );
    }
    throw new Error(m);
  }
  const out = j?.choices?.[0]?.message?.content ?? "";
  if (!out) throw new Error("AIからの返事が空でした");
  return out.trim();
}

/* ------------------------------------------------------------------ 本体 */

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POSTで呼んでください" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const auth = req.headers.get("Authorization") ?? "";

  // ログインしている方として動きます（見える範囲は、その方の権限のままです）
  const db = createClient(url, anon, { global: { headers: { Authorization: auth } } });

  const { data: userRes } = await db.auth.getUser();
  if (!userRes?.user) return json({ error: "ログインが必要です" }, 401);

  let body: any = {};
  try { body = await req.json(); } catch { /* 空でも進みます */ }
  const kind = String(body.kind ?? "");
  const storeId = body.store_id ?? null;
  const date = body.date ?? null;
  const bookingId = body.booking_id ?? null;

  // ---- 法人の設定（どのAIを使うか） -------------------------------------
  const { data: st, error: stErr } = await db.rpc("ai_settings_get");
  if (stErr) return json({ error: stErr.message }, 400);

  const provider = st?.ai_provider ?? "off";
  if (provider === "off") {
    return json({
      error: "AIの下書きは、まだ使わない設定になっています。" +
             "設定 →「AI・送信」から、使うAIを選んでください。",
    }, 400);
  }
  const model = st?.ai_model || DEFAULT_MODEL[provider];
  const tone = st?.ai_tone ?? "polite";

  // ---- 材料を取り直します（数字はここで確定します） ----------------------
  let input: any = null;
  let inErr: any = null;
  if (kind === "night_report") {
    ({ data: input, error: inErr } =
      await db.rpc("night_report_input", { p_store: storeId, p_date: date }));
  } else if (kind === "cast_report") {
    ({ data: input, error: inErr } =
      await db.rpc("cast_report_input", { p_store: storeId, p_date: date }));
  } else if (kind === "cast_reception") {
    ({ data: input, error: inErr } =
      await db.rpc("cast_reception_input", { p_booking: bookingId }));
  } else {
    return json({ error: "その種類の下書きは、まだ用意していません" }, 400);
  }
  if (inErr) return json({ error: inErr.message }, 400);

  // ---- AIに頼みます ------------------------------------------------------
  const text = prompt(kind, input, tone);
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const log = service ? createClient(url, service) : null;

  try {
    let out = "";
    if (provider === "gemini") out = await callGemini(model, text);
    else if (provider === "claude") out = await callClaude(model, text);
    else if (provider === "openai") out = await callOpenAI(model, text);
    else throw new Error("そのAIは選べません");

    if (log) {
      const { data: me } = await db.from("staff").select("id,tenant_id")
        .eq("auth_user_id", userRes.user.id).maybeSingle();
      await log.from("ai_log").insert({
        tenant_id: me?.tenant_id ?? null,
        store_id: storeId,
        staff_id: me?.id ?? null,
        kind, provider, model,
        in_chars: text.length, out_chars: out.length, ok: true,
      });
    }

    //  モデルが入れ替わっていた場合は、実際に使えた名前もお返しします
    return json({
      text: out, provider,
      model: (provider === "gemini" && LAST_MODEL) ? LAST_MODEL : model,
      switched: (provider === "gemini" && LAST_MODEL && LAST_MODEL !== model)
        ? LAST_MODEL : null,
      input,
    });
  } catch (e) {
    let msg = e instanceof Error ? e.message : String(e);
    //  AIのモデルが入れ替わったときは、何をすればよいかをそのまま出します
    if (/no longer available|not found|is not supported|deprecated|decommission/i.test(msg)) {
      msg = "いま選ばれているAIのモデル「" + model + "」が、提供元で使えなくなっています。" +
            "設定 →「AI」の<モデル>の欄に、新しい名前を入れて保存してください。" +
            "（提供元からのお知らせ： " + msg + "）";
    }
    if (log) {
      const { data: me } = await db.from("staff").select("id,tenant_id")
        .eq("auth_user_id", userRes.user.id).maybeSingle();
      await log.from("ai_log").insert({
        tenant_id: me?.tenant_id ?? null,
        store_id: storeId,
        staff_id: me?.id ?? null,
        kind, provider, model,
        in_chars: text.length, out_chars: 0, ok: false, error: msg,
      });
    }
    return json({ error: msg }, 502);
  }
});
