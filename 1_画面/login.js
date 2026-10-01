/* ============================================================================
   だんどりシリーズ / ログインの管理
   login.js
   置き場所： サイトのルート（login.html と同じ階層）

   店長以上の方が、ご自分のお店のスタッフに
     ・名簿に足す
     ・ログインを作る（その場で仮パスワード／招待メール）
     ・パスワードを作り直す
     ・ログインを止める
     ・権限を変える
   を、この画面だけで行えます。

   ほんとうの作成・停止は、Supabase の Edge Function「staff-login」が行います。
   管理者の鍵は、ブラウザには出ません。
   ============================================================================ */

(function () {
  "use strict";

  var $ = K.$, esc = K.esc;
  var ROWS = [];

  var ROLES = [
    { v: "owner",   t: "オーナー",   h: "ぜんぶ見えて、ぜんぶ変えられます" },
    { v: "manager", t: "店長",       h: "オーナーとほぼ同じです" },
    { v: "staff",   t: "スタッフ",   h: "ふだんの仕事はできます。お金の全体像は見えません" },
    { v: "driver",  t: "ドライバー", h: "送迎まわりだけです" }
  ];

  function roleLabel(v) {
    for (var i = 0; i < ROLES.length; i++) if (ROLES[i].v === v) return ROLES[i].t;
    return v;
  }

  function wide(root, px) {
    var b = root.querySelector(".box");
    if (b) b.style.maxWidth = px + "px";
  }

  (function () {
    var st = document.createElement("style");
    st.textContent = "#modalRoot b{display:inline; margin:0}" +
      ".pwshow{font-size:22px; font-weight:700; letter-spacing:.04em;" +
      "background:var(--panel2); border:1px solid var(--line); border-radius:10px;" +
      "padding:14px 16px; margin:10px 0; text-align:center;" +
      "font-family:ui-monospace,Menlo,Consolas,monospace; word-break:break-all}";
    (document.head || document.documentElement).appendChild(st);
  })();

  /* ------------------------------------------------------------ 呼び出し */

  function callFn(body) {
    var CFG = window.DANDORI_CONFIG || {};
    return K.sb.auth.getSession().then(function (r) {
      var tok = (r && r.data && r.data.session && r.data.session.access_token) || "";
      return fetch(CFG.supabaseUrl + "/functions/v1/staff-login", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": CFG.supabaseAnonKey,
          "Authorization": "Bearer " + tok
        },
        body: JSON.stringify(body)
      });
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (j) {
        if (!r.ok || j.error) {
          throw new Error(j.error || "うまくいきませんでした（" + r.status + "）");
        }
        return j;
      });
    });
  }

  function backUrl() {
    return location.href.replace(/[^/]*$/, "") + "reset.html";
  }

  /* -------------------------------------------------------------- 一覧 */

  function load() {
    return K.rpc("staff_login_list", { p_store: K.S.store.id }).then(function (rows) {
      ROWS = rows || [];
      draw();
    });
  }

  function draw() {
    var live = ROWS.filter(function (r) { return r.is_active; });
    var off = ROWS.filter(function (r) { return !r.is_active; });
    var noLogin = live.filter(function (r) { return !r.has_login; }).length;

    $("lSum").innerHTML =
      "<div class='stats'>" +
      K.stat("はたらいている方", live.length + " 名") +
      K.stat("ログインあり", (live.length - noLogin) + " 名") +
      K.stat("ログインなし", noLogin + " 名", noLogin ? "warn" : "") +
      "</div>";

    if (!ROWS.length) {
      $("lTable").innerHTML = "";
      $("lEmpty").classList.remove("hidden");
      return;
    }
    $("lEmpty").classList.add("hidden");

    var body = ROWS.map(function (r) {
      return "<tr class='" + (r.is_active ? "" : "off") + "'>" +
        "<td><b>" + esc(r.name) + "</b>" +
          (r.is_me ? " " + K.pill("ご自分", "ok") : "") +
          (r.is_active ? "" : "<br><small>止めています</small>") + "</td>" +
        "<td class='nw'>" + esc(r.role_label) + "</td>" +
        "<td>" + (r.email ? esc(r.email) : "<small>—</small>") + "</td>" +
        "<td class='nw'>" + (r.has_login
          ? K.pill("あり", "ok")
          : K.pill("なし", "warn")) + "</td>" +
        "<td class='right nw'>" +
          (r.is_active
            ? "<button class='btn " + (r.has_login ? "ghost" : "primary") +
              "' data-login='" + r.id + "'>" +
              (r.has_login ? "ログイン" : "ログインを作る") + "</button> " +
              (r.is_me ? "" :
                "<button class='btn ghost' data-role='" + r.id + "'>権限</button> " +
                "<button class='btn ghost' data-stop='" + r.id + "'>止める</button>")
            : "<button class='btn ghost' data-back='" + r.id + "'>もどす</button>") +
        "</td></tr>";
    });

    $("lTable").innerHTML = K.table(
      ["お名前", "権限", "メールアドレス", "ログイン", ""], body);

    K.bind($("lTable"), "[data-login]", "login", openLogin);
    K.bind($("lTable"), "[data-role]", "role", openRole);
    K.bind($("lTable"), "[data-stop]", "stop", openStop);
    K.bind($("lTable"), "[data-back]", "back", function (id) {
      K.rpc("staff_restart", { p_staff: id }).then(function (r) {
        if (!r) return;
        K.toast("もどしました"); load();
      });
    });
  }

  function row(id) {
    var a = ROWS.filter(function (r) { return r.id === id; });
    return a.length ? a[0] : null;
  }

  /* ------------------------------------------------ 名簿に足す */

  function openAdd() {
    K.modal(
      "<h2 style='margin-top:0'>スタッフを足す</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
      "まず名簿に足します。ログインは、そのあとで作れます。</p>" +
      "<div class='row' style='flex-wrap:wrap;gap:10px'>" +
      "<label class='field' style='flex:2 1 200px'><span>お名前</span>" +
        "<input id='a_name' placeholder='例： 山田 みさき'></label>" +
      "<label class='field' style='flex:1 1 150px'><span>権限</span>" +
        "<select id='a_role'>" + ROLES.map(function (r) {
          return "<option value='" + r.v + "'" +
            (r.v === "staff" ? " selected" : "") + ">" + esc(r.t) + "</option>";
        }).join("") + "</select></label>" +
      "<label class='field' style='flex:2 1 220px'><span>メールアドレス（任意）</span>" +
        "<input id='a_mail' type='email' placeholder='あとからでも入れられます'></label>" +
      "</div>" +
      "<div class='box' id='a_hint' style='margin-top:10px'></div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='a_no'>やめる</button> " +
      "<button class='btn primary' id='a_ok'>足す</button></div>",
      function (root) {
        wide(root, 680);
        function hint() {
          var v = $("a_role").value;
          for (var i = 0; i < ROLES.length; i++) {
            if (ROLES[i].v === v) { $("a_hint").innerHTML = "<b>" + esc(ROLES[i].t) +
              "</b>　" + esc(ROLES[i].h); return; }
          }
        }
        root.querySelector("#a_role").addEventListener("change", hint);
        hint();
        root.querySelector("#a_no").addEventListener("click", K.closeModal);
        root.querySelector("#a_ok").addEventListener("click", function () {
          var n = ($("a_name").value || "").trim();
          if (!n) { K.toast("お名前を入れてください", "err"); return; }
          K.rpc("staff_add", {
            p_store: K.S.store.id, p_name: n, p_role: $("a_role").value,
            p_email: ($("a_mail").value || "").trim() || null
          }).then(function (r) {
            if (!r) return;
            K.closeModal(); K.toast("足しました"); load();
          });
        });
      });
  }

  /* ------------------------------------------------ ログインを作る */

  function openLogin(id) {
    var r = row(id);
    if (!r) return;
    var already = r.has_login;

    K.modal(
      "<h2 style='margin-top:0'>" + esc(r.name) + " さんのログイン</h2>" +
      (already
        ? "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
          "すでにログインがあります。パスワードを作り直せます。</p>"
        : "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
          "この方が、ご自分のスマホやお店の端末から入れるようになります。</p>") +

      "<label class='field'><span>メールアドレス</span>" +
        "<input id='g_mail' type='email' value='" + esc(r.email || "") + "' " +
        "placeholder='ログインに使うアドレス'></label>" +

      "<label class='field'><span>渡しかた</span>" +
        "<select id='g_mode'>" +
        "<option value='temp'>その場で仮パスワードを出す（メール不要）</option>" +
        "<option value='invite'>ご案内のメールを送る（ご本人が決める）</option>" +
        "</select></label>" +
      "<div class='box' id='g_hint'></div>" +

      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='g_no'>やめる</button> " +
      "<button class='btn primary' id='g_ok'>" +
        (already ? "作り直す" : "作る") + "</button></div>",
      function (root) {
        wide(root, 640);
        function hint() {
          $("g_hint").innerHTML = ($("g_mode").value === "temp")
            ? "<b>その場で出します。</b>この画面を閉じると二度と見られません。" +
              "お渡ししたあと、ご本人に変えていただいてください。"
            : "<b>メールが届きます。</b>ご本人がリンクをひらいて、" +
              "ご自分でパスワードを決めます。店長さんはパスワードを知りません。";
        }
        root.querySelector("#g_mode").addEventListener("change", hint);
        hint();
        root.querySelector("#g_no").addEventListener("click", K.closeModal);
        root.querySelector("#g_ok").addEventListener("click", function () {
          var m = ($("g_mail").value || "").trim();
          if (!m || m.indexOf("@") < 0) {
            K.toast("メールアドレスを入れてください", "err"); return;
          }
          var btn = $("g_ok");
          btn.disabled = true; btn.textContent = "作っています…";
          callFn({
            action: already ? "reset" : "create",
            staff_id: id, email: m, mode: $("g_mode").value, back: backUrl()
          }).then(function (j) {
            K.closeModal();
            if (j.mode === "temp") showPassword(r.name, j.email, j.password);
            else { K.toast(j.message || "送りました"); }
            load();
          }).catch(function (e) {
            btn.disabled = false; btn.textContent = already ? "作り直す" : "作る";
            K.toast(e.message || "うまくいきませんでした", "err");
          });
        });
      });
  }

  function showPassword(name, mail, pw) {
    K.modal(
      "<h2 style='margin-top:0'>" + esc(name) + " さんにお渡しください</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
      "この画面を閉じると、パスワードは<b>二度と出ません</b>。" +
      "お渡ししてから閉じてください。</p>" +
      "<div class='field'><span>メールアドレス</span></div>" +
      "<div class='pwshow'>" + esc(mail) + "</div>" +
      "<div class='field'><span>パスワード</span></div>" +
      "<div class='pwshow' id='p_pw'>" + esc(pw) + "</div>" +
      "<div class='box'>ご本人には、入ったあとに右上の<b>パスワード</b>から" +
      "お好きなものに変えていただいてください。</div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='p_copy'>まとめてコピー</button> " +
      "<button class='btn primary' id='p_ok'>お渡ししました</button></div>",
      function (root) {
        wide(root, 560);
        root.querySelector("#p_ok").addEventListener("click", K.closeModal);
        root.querySelector("#p_copy").addEventListener("click", function () {
          var t = "だんどりシリーズ ログイン\n" +
                  "アドレス： " + mail + "\n" +
                  "パスワード： " + pw + "\n" +
                  "入ったら、右上の「パスワード」から変えてください。";
          try {
            if (navigator.clipboard && navigator.clipboard.writeText) {
              navigator.clipboard.writeText(t);
            }
            K.toast("コピーしました");
          } catch (e) { K.toast("コピーできませんでした", "err"); }
        });
      });
  }

  /* ------------------------------------------------ 権限を変える */

  function openRole(id) {
    var r = row(id);
    if (!r) return;
    K.modal(
      "<h2 style='margin-top:0'>" + esc(r.name) + " さんの権限</h2>" +
      "<label class='field'><span>権限</span><select id='r_role'>" +
        ROLES.map(function (x) {
          return "<option value='" + x.v + "'" +
            (x.v === r.role ? " selected" : "") + ">" + esc(x.t) + "</option>";
        }).join("") + "</select></label>" +
      "<div class='box' id='r_hint'></div>" +
      "<div class='row' style='justify-content:flex-end;margin-top:14px'>" +
      "<button class='btn ghost' id='r_no'>やめる</button> " +
      "<button class='btn primary' id='r_ok'>変える</button></div>",
      function (root) {
        wide(root, 560);
        function hint() {
          var v = $("r_role").value;
          for (var i = 0; i < ROLES.length; i++) {
            if (ROLES[i].v === v) { $("r_hint").innerHTML = "<b>" + esc(ROLES[i].t) +
              "</b>　" + esc(ROLES[i].h); return; }
          }
        }
        root.querySelector("#r_role").addEventListener("change", hint);
        hint();
        root.querySelector("#r_no").addEventListener("click", K.closeModal);
        root.querySelector("#r_ok").addEventListener("click", function () {
          K.rpc("staff_role_set", { p_staff: id, p_role: $("r_role").value })
            .then(function (x) {
              if (!x) return;
              K.closeModal(); K.toast("変えました"); load();
            });
        });
      });
  }

  /* ------------------------------------------------ 止める */

  function openStop(id) {
    var r = row(id);
    if (!r) return;
    K.confirm(esc(r.name) + " さんを止めます",
      "<p>名簿からは外れますが、<b>これまでの記録は残ります</b>。" +
      (r.has_login ? "ログインも使えなくなります。" : "") +
      "<br>あとから「もどす」で戻せます。</p>",
      "止める",
      function () {
        var go = r.has_login
          ? callFn({ action: "stop", staff_id: id })
          : Promise.resolve({});
        go.then(function () {
          return K.rpc("staff_stop", { p_staff: id });
        }).then(function (x) {
          K.closeModal();
          if (x) K.toast("止めました");
          load();
        }).catch(function (e) {
          K.closeModal();
          K.toast(e.message || "うまくいきませんでした", "err");
        });
      });
  }

  /* ---------------------------------------------------------------- 画面 */

  $("lAdd").addEventListener("click", openAdd);
  $("lReload").addEventListener("click", load);

  K.wireLogin();
  K.boot(function () { load(); });
})();
