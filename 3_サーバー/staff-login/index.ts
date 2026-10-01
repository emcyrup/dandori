// ============================================================================
//  だんどりシリーズ 共通 / スタッフのログインを作る・止める
//  supabase/functions/staff-login/index.ts
//
//  置き場所： Supabase の Edge Function「staff-login」
//
//  この関数がすること
//   1. 呼んだ方が「店長以上」かどうかを確かめます（staff_login_check）
//   2. そのうえで、ログイン（Authentication → Users）を作る・直す・止める
//   3. できたことだけをお返しします
//
//  ★ service_role の鍵は、この関数の中だけで使います。
//    ブラウザには一切出ません。
//
//  ★ 使う鍵（Secrets）は、Supabase が自動で入れてくれるものだけです。
//      SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY
//    追加で入れるものはありません。
//
//  できること（action）
//   create  … ログインを作る。mode = "temp"（仮パスワードを返す）
//                                / "invite"（招待メールを送る）
//   reset   … パスワードを作り直す。mode は create と同じ
//   stop    … ログインを止める（名簿は残ります）
// ============================================================================

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

/*  読みまちがえにくい文字だけで、仮パスワードを作ります。
    0 と O、1 と l のような、まぎらわしい文字は使いません。 */
function tempPassword(): string {
  const a = "abcdefghjkmnpqrstuvwxyz";
  const n = "23456789";
  const pick = (s: string, k: number) => {
    const b = new Uint32Array(k);
    crypto.getRandomValues(b);
    return Array.from(b, (x) => s[x % s.length]).join("");
  };
  return pick(a, 4) + "-" + pick(a, 4) + "-" + pick(n, 4);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POSTでお願いします" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const auth = req.headers.get("Authorization") ?? "";

  if (!svc) {
    return json({ error: "この機能の準備がまだできていません。担当までご連絡ください。" }, 503);
  }

  const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.45.4");

  //  呼んだ方の鍵で動くほう（権限の確認に使います）
  const asUser = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
  });
  //  管理者の鍵で動くほう（ログインの作成・停止に使います）
  const admin = createClient(url, svc, { auth: { persistSession: false } });

  let body: any = {};
  try { body = await req.json(); } catch { /* 空でも進みます */ }

  const action = String(body.action ?? "");
  const staffId = String(body.staff_id ?? "");
  const mode = String(body.mode ?? "temp");
  const email = String(body.email ?? "").trim().toLowerCase();
  const back = String(body.back ?? "").trim();     // 招待メールの戻り先

  if (!staffId) return json({ error: "どなたのぶんか分かりません" }, 400);

  //  ---------------------------------------------- 1. 権限をたしかめます
  const chk = await asUser.rpc("staff_login_check", { p_staff: staffId });
  if (chk.error) {
    return json({ error: chk.error.message || "権限を確かめられませんでした" }, 403);
  }
  const s = chk.data as any;

  try {
    //  -------------------------------------------- 2. ログインを止める
    if (action === "stop") {
      if (s.auth_user_id) {
        await admin.auth.admin.updateUserById(s.auth_user_id, {
          ban_duration: "876000h",          // 100年。実質「止める」
        });
      }
      await admin.rpc("sr_staff_login_unlink", { p_staff: staffId });
      return json({ ok: true, message: s.name + " さんのログインを止めました。" });
    }

    //  -------------------------------------------- 3. 作る・作り直す
    if (action !== "create" && action !== "reset") {
      return json({ error: "できない操作です" }, 400);
    }

    let userId: string | null = s.auth_user_id ?? null;
    let useEmail = email || s.email || "";

    if (!useEmail) {
      return json({ error: "メールアドレスを入れてください" }, 400);
    }

    //  すでに同じアドレスのログインがあれば、それを使います
    if (!userId) {
      const f = await admin.rpc("sr_auth_user_by_email", { p_email: useEmail });
      if (!f.error && f.data) userId = f.data as string;
    }

    const pw = tempPassword();

    if (!userId) {
      //  はじめて作ります
      if (mode === "invite") {
        const inv = await admin.auth.admin.inviteUserByEmail(useEmail, {
          redirectTo: back || undefined,
        });
        if (inv.error) throw inv.error;
        userId = inv.data.user?.id ?? null;
      } else {
        const cre = await admin.auth.admin.createUser({
          email: useEmail,
          password: pw,
          email_confirm: true,
        });
        if (cre.error) throw cre.error;
        userId = cre.data.user?.id ?? null;
      }
    } else {
      //  もうあるので、パスワードを入れ直す／案内を送り直します
      if (mode === "invite") {
        const r = await asUser.auth.resetPasswordForEmail(useEmail, {
          redirectTo: back || undefined,
        });
        if (r.error) throw r.error;
      } else {
        const up = await admin.auth.admin.updateUserById(userId, {
          password: pw,
          email_confirm: true,
          ban_duration: "none",
        });
        if (up.error) throw up.error;
      }
    }

    if (!userId) return json({ error: "ログインを作れませんでした" }, 500);

    //  名簿とむすびます
    const link = await admin.rpc("sr_staff_login_link", {
      p_staff: staffId, p_user: userId, p_email: useEmail,
    });
    if (link.error) throw link.error;

    if (mode === "invite") {
      return json({
        ok: true,
        mode: "invite",
        email: useEmail,
        message: useEmail + " あてに、ご案内のメールをお送りしました。" +
                 "ご本人がリンクをひらいて、パスワードを決めます。",
      });
    }
    return json({
      ok: true,
      mode: "temp",
      email: useEmail,
      password: pw,
      message: "この画面を閉じると、パスワードは二度と出ません。" +
               "ご本人にお渡しください。",
    });

  } catch (e) {
    const m = (e && (e as any).message) ? (e as any).message : String(e);
    //  よくある断り文句を、日本語にします
    if (/already been registered|already exists/i.test(m)) {
      return json({ error: "そのメールアドレスは、すでにほかの方が使っています。" }, 400);
    }
    if (/rate limit/i.test(m)) {
      return json({ error: "メールの送りすぎです。少し時間をあけてからお試しください。" }, 429);
    }
    if (/invalid.*email/i.test(m)) {
      return json({ error: "メールアドレスの形が正しくないようです。" }, 400);
    }
    return json({ error: m }, 500);
  }
});
