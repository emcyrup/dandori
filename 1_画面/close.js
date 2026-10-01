/* ============================================================================
   だんどりシリーズ / ナイトだんどり 締め・日報
   close.js
   置き場所： サイトのルート（close.html と同じ階層）

   これまで「伝票・会計」の中にあった〈締め〉を、こちらに移しました。
   伝票・会計は、その場のお会計。こちらは、一日を閉じる作業です。

   お金の計算はすべてデータベース側（002_rpc.sql / 016_ai_send.sql）で行います。
   この画面は「表示」と「関数を呼ぶ」だけを担当します。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  var S = { me: null, stores: [], store: null };

  //  AIが書いた文章を、そのまま保存しようとしているか
  var AI_MADE = false;

  /* ---------------------------------------------------------------- 小道具 */

  var $ = function (id) { return document.getElementById(id); };
  var yen = function (n) { return "¥" + (n || 0).toLocaleString("ja-JP"); };
  function ymd(d) { return d.toISOString().slice(0, 10); }

  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }
  function fail(e) {
    var m = (e && (e.message || e.error_description || e.details)) || String(e);
    toast(m.replace(/^.*?:\s*/, ""), "err");
    if (window.console) console.error(e);
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  /*  Edge Function（AI）を呼びます */
  function callFn(name, body) {
    return sb.auth.getSession().then(function (r) {
      var tok = (r && r.data && r.data.session) ? r.data.session.access_token : null;
      if (!tok) { fail("ログインが必要です"); return null; }
      return fetch(CFG.supabaseUrl + "/functions/v1/" + name, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": CFG.supabaseAnonKey,
          "Authorization": "Bearer " + tok
        },
        body: JSON.stringify(body || {})
      }).then(function (res) {
        return res.json().then(function (j) {
          if (!res.ok || j.error) {
            fail(j.error || ("うまくいきませんでした（" + res.status + "）"));
            return null;
          }
          return j;
        });
      })["catch"](function (e) {
        fail("つながりませんでした。しくみの用意がまだかもしれません。");
        if (window.console) console.error(e);
        return null;
      });
    });
  }

  /* ------------------------------------------------------------ ログイン */

  $("loginForm").addEventListener("submit", function (e) {
    e.preventDefault();
    $("loginBtn").disabled = true;
    sb.auth.signInWithPassword({
      email: $("email").value.trim(), password: $("password").value
    }).then(function (r) {
      $("loginBtn").disabled = false;
      if (r.error) { fail(r.error); return; }
      boot();
    });
  });
  $("logoutBtn").addEventListener("click", function () {
    sb.auth.signOut().then(function () { location.reload(); });
  });

  function showLogin() {
    $("login").classList.remove("hidden");
    $("app").classList.add("hidden");
  }

  function boot() {
    sb.auth.getSession().then(function (r) {
      var u = (r && r.data && r.data.session) ? r.data.session.user : null;
      if (!u) { showLogin(); return; }
      return sb.from("staff").select("*").eq("auth_user_id", u.id).maybeSingle()
        .then(function (q) {
          if (q.error) { fail(q.error); return; }
          if (!q.data) { toast("このアカウントにスタッフ登録がありません。", "err"); return; }
          S.me = q.data;
          $("meName").textContent = S.me.name;
          $("login").classList.add("hidden");
          $("app").classList.remove("hidden");
          document.body.className = "theme-" + (CFG.theme || "dark");
          return loadStores();
        });
    })["catch"](fail);
  }

  /*  お店のえらびかた（業種ごとに覚えます。更新しても入れかわりません） */
  var MISEKEY = "dandori-store-" + (CFG.industry || "x");

  function loadStores() {
    return sb.rpc("store_list", { p_kind: CFG.industry || null })
      .then(function (q) {
        if (q.error || !q.data || !q.data.length) return storesFromTable();
        return putStores(q.data);
      })["catch"](storesFromTable);
  }

  function storesFromTable() {
    return sb.from("store").select("*").eq("is_active", true).order("name")
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var all = q.data || [];
        var mine = all.filter(function (s) { return s.industry === CFG.industry; });
        return putStores(mine.length ? mine : all);
      });
  }

  function putStores(rows) {
    S.stores = rows || [];
    if (!S.stores.length) { toast("店舗が登録されていません。", "err"); return; }
    $("storeSel").innerHTML = S.stores.map(function (s) {
      return '<option value="' + s.id + '">' + esc(s.name) + "</option>";
    }).join("");
    var keep = null;
    try { keep = localStorage.getItem(MISEKEY); } catch (e) {}
    var hit = S.stores.filter(function (s) { return s.id === keep; })[0];
    selectStore(hit ? hit.id : S.stores[0].id);
  }
  $("storeSel").addEventListener("change", function () { selectStore(this.value); });

  function selectStore(id) {
    S.store = S.stores.filter(function (s) { return s.id === id; })[0];
    $("storeSel").value = id;
    try { localStorage.setItem(MISEKEY, id); } catch (e) {}
    if (S.store.ui_theme) document.body.className = "theme-" + S.store.ui_theme;
    if (!$("dayDate").value) $("dayDate").value = todayBusinessDate();
    loadDay();
    loadReport();
  }

  function todayBusinessDate() {
    //  店舗の切替時刻より前なら前日あつかい（画面の推定。確定値はDBが持ちます）
    var cut = (S.store && S.store.day_cutoff) || "05:00";
    var now = new Date();
    var h = Number(cut.split(":")[0]), m = Number(cut.split(":")[1] || 0);
    var d = new Date(now);
    if (now.getHours() < h || (now.getHours() === h && now.getMinutes() < m)) {
      d.setDate(d.getDate() - 1);
    }
    return ymd(d);
  }

  /* -------------------------------------------------------------- 日締め */

  $("daySumBtn").addEventListener("click", loadDay);

  function loadDay() {
    var d = $("dayDate").value;
    if (!d || !S.store) return;
    Promise.all([
      sb.from("night_visit").select("status,total,paid_cash,paid_card,paid_credit")
        .eq("store_id", S.store.id).eq("business_date", d),
      sb.from("night_daily_close").select("*").eq("store_id", S.store.id)
        .eq("business_date", d).maybeSingle()
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      var rows = r[0].data || [];
      var closed = rows.filter(function (x) { return x.status === "closed"; });
      var open = rows.filter(function (x) { return x.status === "open"; }).length;
      var sum = function (k) {
        return closed.reduce(function (a, x) { return a + (x[k] || 0); }, 0);
      };
      var rec = r[1].data;

      $("daySummary").innerHTML =
        '<div class="totals" style="max-width:420px">' +
          "<div><span>組数</span><span class='mono'>" + closed.length + " 組</span></div>" +
          "<div><span>現金</span><span class='mono'>" + yen(sum("paid_cash")) + "</span></div>" +
          "<div><span>カード</span><span class='mono'>" + yen(sum("paid_card")) + "</span></div>" +
          "<div><span>売掛</span><span class='mono'>" + yen(sum("paid_credit")) + "</span></div>" +
          "<div class='grand'><span>売上</span><span class='mono'>" + yen(sum("total")) + "</span></div>" +
        "</div>" +
        (open ? '<div class="pay-check ng" style="max-width:420px">開いたままの卓が ' + open +
                " 件あります。先に締めてください。</div>" : "") +
        (rec ? '<div class="pay-check ' + (rec.cash_diff === 0 ? "ok" : "ng") +
               '" style="max-width:420px">' +
               "締め済み：実査 " + yen(rec.cash_counted) + "　差異 " +
               (rec.cash_diff === 0 ? "なし" : yen(rec.cash_diff)) + "</div>" : "") +
        '<div class="row" style="margin-top:14px;max-width:420px">' +
          '<label class="field" style="margin:0;flex:1">' +
          '<span style="font-size:12px;color:var(--muted)">数えた現金</span>' +
          '<input id="cashCounted" type="number" min="0" inputmode="numeric" value="' +
            (rec ? rec.cash_counted : sum("paid_cash")) + '"></label>' +
          '<button class="btn primary" id="closeDayBtn" style="margin-top:18px"' +
            (open ? " disabled" : "") + ">この日を締める</button>" +
        "</div>";

      var btn = $("closeDayBtn");
      if (btn) btn.addEventListener("click", function () {
        btn.disabled = true;
        sb.rpc("night_close_day", {
          p_store: S.store.id,
          p_date: d,
          p_cash_counted: Number($("cashCounted").value) || 0,
          p_note: null
        }).then(function (q) {
          btn.disabled = false;
          if (q.error) { fail(q.error); return; }
          var diff = q.data.cash_diff;
          toast(diff === 0 ? "締めました。現金は合っています。"
                           : "締めました。現金の差異 " + yen(diff),
                diff === 0 ? "ok" : "err");
          loadDay();
        });
      });
    });
  }

  /* ============================================================ 日報 */

  function reportDate() { return $("dayDate").value || ymd(new Date()); }

  function loadReport() {
    var d = reportDate();
    if (!d || !S.store) return;
    AI_MADE = false;
    sb.rpc("report_get", { p_store: S.store.id, p_date: d }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var r = q.data;
      $("nBody").value = (r && r.body) || "";
      $("nMemo").value = (r && r.memo) || "";
      $("nState").innerHTML = !r
        ? '<div class="box">この日の日報は、まだありません。</div>'
        : (r.status === "confirmed"
            ? '<div class="box"><b>確定ずみ</b>' +
              (r.confirmed_at
                ? new Date(r.confirmed_at).toLocaleString("ja-JP") + " に確定しました。" : "") +
              (r.source === "ai" ? "（AIの下書きから作りました）" : "") + "</div>"
            : '<div class="box warn"><b>下書きのままです</b>' +
              "内容を確かめて、確定してください。" +
              (r.source === "ai" ? "（AIの下書きです）" : "") + "</div>");
    });
  }

  /*  ひとことだけを保存します（本文はさわりません） */
  function saveMemo(quiet) {
    var d = reportDate();
    if (!d || !S.store) return Promise.resolve(null);
    return sb.rpc("report_memo_set", {
      p_store: S.store.id, p_date: d, p_memo: $("nMemo").value || ""
    }).then(function (q) {
      if (q.error) { fail(q.error); return null; }
      if (!quiet) toast("ひとことを保存しました", "ok");
      return q.data;
    });
  }
  $("nMemoSave").addEventListener("click", function () { saveMemo(false); });

  $("nAi").addEventListener("click", function () {
    var d = reportDate();
    if (!d || !S.store) return;
    var btn = this;
    btn.disabled = true; btn.textContent = "書いています…";
    //  ひとことを先に保存してから、AIに渡します
    saveMemo(true).then(function () {
      return callFn("ai", { kind: "night_report", store_id: S.store.id, date: d });
    }).then(function (r) {
      btn.disabled = false; btn.textContent = "AIで下書き";
      if (!r) return;
      AI_MADE = true;
      $("nBody").value = r.text;
      toast(r.provider + " が下書きしました。内容を確かめてください", "ok");
    });
  });

  $("dayDate").addEventListener("change", function () { loadDay(); loadReport(); });
  $("nSave").addEventListener("click", function () { saveReport("draft"); });
  $("nFix").addEventListener("click", function () { saveReport("confirmed"); });

  function saveReport(status) {
    var d = reportDate();
    if (!d || !S.store) return;
    sb.rpc("report_save", {
      p_store: S.store.id, p_date: d,
      p_body: $("nBody").value, p_status: status,
      p_source: AI_MADE ? "ai" : "manual",
      p_memo: $("nMemo").value || ""
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      toast(status === "confirmed" ? "確定しました" : "下書きを保存しました", "ok");
      loadReport();
    });
  }

  /* -------------------------------------------------------------- 起動 */

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  boot();
})();
