// ============================================================================
//  だんどりシリーズ 共通 / LINEからの受け口
//  supabase/functions/line-webhook/index.ts
//
//  置き場所： Supabase の Edge Function「line-webhook」
//
//  この関数がすること
//   1. LINE公式アカウントに届いたメッセージを受けとります
//   2. 本当にLINEから来たものかを、署名で確かめます
//   3. 「10/1 10-17」のような文を読んで、シフト希望に入れます
//   4. 読みとった中身を、その場で返信します
//
//  ★ LINEの管理画面で設定する Webhook URL は、法人ごとに変わります：
//       https://＜プロジェクト＞.supabase.co/functions/v1/line-webhook?t=＜法人ID＞
//    ＜法人ID＞は、public.tenant の id です。
//    こうすることで、複数のお店（法人）を1つの関数でさばけます。
//
//  ★ 鍵は public.tenant_secret に入れておきます。
//       line_channel_secret … 署名を確かめるため（LINE Developers の Channel secret）
//       line_channel_token  … 返信するため（Messaging API の長期アクセストークン）
//    この表は、画面から使う鍵では1行も読めません。
//    読めるのは、この関数が使う service_role だけです。
//
//  ★ この関数は「JWT検証なし」で置いてください。
//    LINEからのリクエストには、Supabaseのログイン情報が付かないためです。
//    そのかわり、下の署名の確認で守っています。
//    （Supabase CLI なら： supabase functions deploy line-webhook --no-verify-jwt）
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// ----------------------------------------------------------------- 小道具

function ok(body: unknown = { ok: true }) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function ng(msg: string, code = 400) {
  // LINEには200を返しておかないと、何度も再送されます。
  // 中身でわけがわかるようにしておきます。
  console.error("line-webhook:", msg);
  return new Response(JSON.stringify({ ok: false, error: msg }), {
    status: code,
    headers: { "Content-Type": "application/json" },
  });
}

/** LINEの署名を確かめます（本当にLINEから来たものか） */
async function verify(secret: string, body: string, signature: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(body),
  );
  const expect = btoa(String.fromCharCode(...new Uint8Array(mac)));
  // 長さがちがうだけで落とすと、そこから中身が漏れることがあるので、
  // 最後まで比べてから判断します
  if (expect.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expect.length; i++) {
    diff |= expect.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0;
}

/** 返信します（replyToken は1回だけ・約1分だけ使えます） */
async function reply(token: string, replyToken: string, text: string) {
  const res = await fetch("https://api.line.me/v2/bot/message/reply", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      replyToken,
      messages: [{ type: "text", text: text.slice(0, 4900) }],
    }),
  });
  if (!res.ok) {
    console.error("LINE reply failed:", res.status, await res.text());
  }
}

/** プロフィール（お名前・写真）をとります。とれなくても止めません */
async function profile(token: string, userId: string) {
  try {
    const res = await fetch(`https://api.line.me/v2/bot/profile/${userId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) return {};
    return await res.json();
  } catch {
    return {};
  }
}

const HELP =
  "シフト希望の出しかた\n\n" +
  "このトークに、こんなふうに送ってください。\n\n" +
  "10/1 10-17\n" +
  "10/2 17:00-23:30\n" +
  "10/3 休\n" +
  "10/5 通し\n\n" +
  "何行でもまとめて送れます。\n" +
  "「休」と書いた日は、お休み希望になります。\n" +
  "時間を書かない日は、時間おまかせであつかいます。";

// ----------------------------------------------------------------- 本体

Deno.serve(async (req) => {
  if (req.method !== "POST") return ng("POSTだけを受けつけます", 405);

  const url = new URL(req.url);
  const tenantId = url.searchParams.get("t");
  if (!tenantId) {
    return ng(
      "法人IDがついていません。WebhookのURLの末尾に ?t=法人ID を付けてください",
    );
  }

  const raw = await req.text();
  const signature = req.headers.get("x-line-signature") ?? "";

  const db = createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false },
  });

  // ---- 鍵を読みます -------------------------------------------------------
  const { data: secrets, error: secErr } = await db
    .from("tenant_secret")
    .select("key_name, value")
    .eq("tenant_id", tenantId);

  if (secErr) return ng("鍵が読めませんでした： " + secErr.message, 500);

  const keyOf = (k: string) =>
    (secrets ?? []).find((s: any) => s.key_name === k)?.value ?? null;

  const channelSecret = keyOf("line_channel_secret");
  const channelToken = keyOf("line_channel_token");

  if (!channelSecret) {
    return ng(
      "この法人の line_channel_secret が登録されていません。" +
        "「設定」→「AI・送信」で登録してください",
      500,
    );
  }

  // ---- 本当にLINEから来たものかを確かめます -------------------------------
  if (!signature || !(await verify(channelSecret, raw, signature))) {
    return ng("署名が合いません", 401);
  }

  let payload: any;
  try {
    payload = JSON.parse(raw);
  } catch {
    return ng("中身が読めません");
  }

  const events: any[] = payload?.events ?? [];
  // LINEの疎通確認（イベントが空）にも、200を返しておきます
  if (events.length === 0) return ok({ ok: true, note: "イベントなし" });

  for (const ev of events) {
    const userId = ev?.source?.userId;
    if (!userId) continue;

    // だれのLINEかを控えます（お店の画面で、名簿と結びつけられます）
    let prof: any = {};
    if (channelToken) prof = await profile(channelToken, userId);

    const { data: seen } = await db.rpc("line_seen", {
      p_tenant: tenantId,
      p_line_user_id: userId,
      p_name: prof?.displayName ?? null,
      p_pic: prof?.pictureUrl ?? null,
    });

    const linked = seen?.linked === true;

    // ---- 友だち追加 -------------------------------------------------------
    if (ev.type === "follow") {
      if (channelToken && ev.replyToken) {
        await reply(
          channelToken,
          ev.replyToken,
          linked
            ? `${seen?.name ?? ""} さん\n追加ありがとうございます。\n\n${HELP}`
            : "追加ありがとうございます。\n\n" +
              "はじめに、お店で「このLINEはだれのものか」を登録します。\n" +
              "お手数ですが、お店にひとことお声がけください。\n\n" +
              "登録がすむと、このトークからシフト希望が出せるようになります。",
        );
      }
      continue;
    }

    // ---- 文字のメッセージ -------------------------------------------------
    if (ev.type !== "message" || ev.message?.type !== "text") continue;

    const text: string = ev.message.text ?? "";

    if (/^(ヘルプ|help|使い方|つかいかた|\?|？)$/i.test(text.trim())) {
      if (channelToken && ev.replyToken) {
        await reply(channelToken, ev.replyToken, HELP);
      }
      continue;
    }

    if (!linked) {
      if (channelToken && ev.replyToken) {
        await reply(
          channelToken,
          ev.replyToken,
          "お店の名簿とつながっていないようです。\n" +
            "お手数ですが、このメッセージをお店にお見せください。",
        );
      }
      continue;
    }

    // ---- シフト希望として読みとります -------------------------------------
    const { data: result, error: rpcErr } = await db.rpc("wish_from_line", {
      p_line_user_id: userId,
      p_text: text,
    });

    let msg: string;
    if (rpcErr) {
      console.error("wish_from_line:", rpcErr.message);
      msg =
        "うまく受けとれませんでした。お手数ですが、お店にご連絡ください。";
    } else {
      msg = result?.reply ?? HELP;
    }

    if (channelToken && ev.replyToken) {
      await reply(channelToken, ev.replyToken, msg);
    }
  }

  return ok();
});
