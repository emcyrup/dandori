// ============================================================================
//  だんどりシリーズ 共通 / 送信箱を送り出す
//  supabase/functions/send-outbox/index.ts
//
//  置き場所： Supabase の Edge Function「send-outbox」
//
//  この関数がすること
//   1. public.outbox の「送信待ち」を取り出します
//   2. 法人ごとの鍵を読んで、LINE または メールで送ります
//   3. 結果（送信済み／失敗）を、送信箱に書き戻します
//
//  ★ LINEのトークンとメールの鍵は、public.tenant_secret に入っています。
//    この表は、画面から使う鍵（anon / authenticated）では1行も読めません。
//    読めるのは、この関数が使う service_role だけです。
//
//  呼び方は2つあります。
//   ・画面の「今すぐ送る」ボタン（ログインしている方の鍵で呼ばれます）
//     → その方の法人ぶんだけを送ります
//   ・pg_cron から service_role で呼ぶ（016_ai_send.sql の最後に手順あり）
//     → すべての法人ぶんを送ります
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_TRIES = 3;      // これを超えたら、手で送り直していただきます
const BATCH = 50;         // 1回で送る上限

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/* ------------------------------------------------------------------ LINE */

async function sendLine(token: string, to: string, text: string) {
  const r = await fetch("https://api.line.me/v2/bot/message/push", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ to, messages: [{ type: "text", text: text.slice(0, 4900) }] }),
  });
  if (!r.ok) {
    const t = await r.text();
    if (r.status === 400 && t.includes("Invalid to")) {
      throw new Error("LINEの送り先が正しくありません。友だち登録をご確認ください。");
    }
    if (r.status === 401 || r.status === 403) {
      throw new Error("LINEのトークンが正しくありません。設定を確かめてください。");
    }
    throw new Error(`LINE エラー (${r.status}) ${t.slice(0, 200)}`);
  }
}

/* ------------------------------------------------------------------ メール */

async function sendResend(
  key: string, from: string, fromName: string,
  to: string, subject: string, text: string, replyTo?: string | null,
) {
  // 差出人は「お店の名前 <アドレス>」の形にします。
  // こうすると、受けとった方の一覧に、アドレスではなくお店の名前が出ます。
  const sender = fromName ? `${fromName} <${from}>` : from;
  const body: Record<string, unknown> = {
    from: sender, to: [to], subject, text,
  };
  if (replyTo) body.reply_to = replyTo;

  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify(body),
  });
  if (!r.ok) {
    const t = await r.text();
    if (r.status === 401 || r.status === 403) {
      throw new Error("メールの鍵が正しくありません。設定を確かめてください。");
    }
    throw new Error(`Resend エラー (${r.status}) ${t.slice(0, 200)}`);
  }
}

async function sendSendgrid(
  key: string, from: string, fromName: string,
  to: string, subject: string, text: string, replyTo?: string | null,
) {
  const payload: Record<string, unknown> = {
    personalizations: [{ to: [{ email: to }] }],
    from: { email: from, name: fromName || undefined },
    subject,
    content: [{ type: "text/plain", value: text }],
  };
  if (replyTo) payload.reply_to = { email: replyTo };

  const r = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
    body: JSON.stringify(payload),
  });
  if (!r.ok && r.status !== 202) {
    const t = await r.text();
    if (r.status === 401 || r.status === 403) {
      throw new Error("メールの鍵が正しくありません。設定を確かめてください。");
    }
    throw new Error(`SendGrid エラー (${r.status}) ${t.slice(0, 200)}`);
  }
}

/* ------------------------------------------------------------------ 本体 */

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!service) return json({ error: "この関数の設定が足りません" }, 500);

  const db = createClient(url, service);

  // 呼び出した方が分かる場合は、その法人ぶんだけにしぼります
  let onlyTenant: string | null = null;
  const auth = req.headers.get("Authorization") ?? "";
  if (auth && !auth.includes(service)) {
    const asUser = createClient(url, anon, { global: { headers: { Authorization: auth } } });
    const { data: u } = await asUser.auth.getUser();
    if (u?.user) {
      const { data: me } = await db.from("staff")
        .select("tenant_id, role, is_active")
        .eq("auth_user_id", u.user.id).maybeSingle();
      if (!me || !me.is_active) return json({ error: "ログインが必要です" }, 401);
      if (me.role !== "owner" && me.role !== "manager") {
        return json({ error: "送信は、店長以上の権限が必要です" }, 403);
      }
      onlyTenant = me.tenant_id;
    }
  }

  // ---- 送信待ちを取り出します -------------------------------------------
  let q = db.from("outbox").select("*")
    .eq("status", "queued").lt("tries", MAX_TRIES)
    .order("created_at", { ascending: true }).limit(BATCH);
  if (onlyTenant) q = q.eq("tenant_id", onlyTenant);

  const { data: rows, error } = await q;
  if (error) return json({ error: error.message }, 500);
  if (!rows || rows.length === 0) return json({ sent: 0, failed: 0, detail: [] });

  // ---- 法人ごとの設定と鍵を、まとめて読みます ---------------------------
  const tenants = [...new Set(rows.map((r: any) => r.tenant_id))];
  const { data: settings } = await db.from("tenant_ai").select("*").in("tenant_id", tenants);
  const { data: secrets } = await db.from("tenant_secret").select("*").in("tenant_id", tenants);

  // お店の連絡先メール。返信がお店に届くように、返信先として付けます
  const storeIds = [...new Set(rows.map((r: any) => r.store_id).filter(Boolean))];
  const { data: stores } = storeIds.length
    ? await db.from("store").select("id, email").in("id", storeIds)
    : { data: [] as any[] };
  const replyOf = (id: string) =>
    (stores ?? []).find((x: any) => x.id === id)?.email || null;

  const setOf = (t: string) => (settings ?? []).find((s: any) => s.tenant_id === t) ?? {};
  const keyOf = (t: string, k: string) =>
    (secrets ?? []).find((s: any) => s.tenant_id === t && s.key_name === k)?.value ?? null;

  let sent = 0, failed = 0;
  const detail: any[] = [];

  for (const row of rows as any[]) {
    const s: any = setOf(row.tenant_id);
    try {
      if (row.channel === "line") {
        if (!s.line_enabled) throw new Error("LINEでの送信が、設定でオフになっています");
        const token = keyOf(row.tenant_id, "line_channel_token");
        if (!token) throw new Error("LINEのトークンが設定されていません");
        await sendLine(token, row.to_addr, `${row.subject ?? ""}\n\n${row.body}`.trim());

      } else if (row.channel === "email") {
        const provider = s.mail_provider ?? "off";
        if (provider === "off") throw new Error("メールでの送信が、設定でオフになっています");
        const from = s.mail_from;
        if (!from) throw new Error("差出人のメールアドレスが設定されていません");

        if (provider === "resend") {
          const key = keyOf(row.tenant_id, "resend_api_key");
          if (!key) throw new Error("Resend の鍵が設定されていません");
          await sendResend(key, from, s.mail_from_name ?? "",
                           row.to_addr, row.subject ?? "お知らせ", row.body,
                           replyOf(row.store_id));
        } else {
          const key = keyOf(row.tenant_id, "sendgrid_api_key");
          if (!key) throw new Error("SendGrid の鍵が設定されていません");
          await sendSendgrid(key, from, s.mail_from_name ?? "",
                             row.to_addr, row.subject ?? "お知らせ", row.body,
                             replyOf(row.store_id));
        }

      } else {
        throw new Error("その送り方は、まだ用意していません");
      }

      await db.from("outbox").update({
        status: "sent", sent_at: new Date().toISOString(),
        tries: (row.tries ?? 0) + 1, error: null,
      }).eq("id", row.id);

      // 明細にも「送りました」を書き戻します
      if (row.related_kind === "payslip" && row.related_id) {
        await db.from("payslip").update({
          status: "sent", sent_at: new Date().toISOString(), method: row.channel,
        }).eq("id", row.related_id);
      }

      sent++;
      detail.push({ id: row.id, channel: row.channel, ok: true });

    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      const tries = (row.tries ?? 0) + 1;
      await db.from("outbox").update({
        status: tries >= MAX_TRIES ? "failed" : "queued",
        tries, error: msg,
      }).eq("id", row.id);
      failed++;
      detail.push({ id: row.id, channel: row.channel, ok: false, error: msg });
    }
  }

  return json({ sent, failed, detail });
});
