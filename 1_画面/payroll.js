/* ============================================================================
   だんどりシリーズ / ナイトだんどり キャスト・給与
   payroll.js
   置き場所： サイトのルート（payroll.html と同じ階層）

   給与の計算はすべてデータベース側（004_payroll.sql）で行います。
   この画面は「表示」と「関数を呼ぶ」だけです。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  var S = { me: null, stores: [], store: null, casts: [], att: [], rows: [] };

  var $ = function (id) { return document.getElementById(id); };
  var yen = function (n) { return "¥" + (n || 0).toLocaleString("ja-JP"); };
  var hm = function (min) {
    var h = Math.floor((min || 0) / 60), m = (min || 0) % 60;
    return h + "時間" + (m ? m + "分" : "");
  };

  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }
  function fail(e) {
    var m = (e && (e.message || e.details)) || String(e);
    toast(m.replace(/^.*?:\s*/, ""), "err");
    console.error(e);
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function modal(html, onReady) {
    var root = $("modalRoot");
    root.innerHTML = '<div class="modal"><div class="box">' + html + "</div></div>";
    var wrap = root.querySelector(".modal");
    wrap.addEventListener("click", function (e) { if (e.target === wrap) closeModal(); });
    if (onReady) onReady(root);
  }

  /* Edge Function（AI・送信）を呼びます */
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
      }).catch(function (e) {
        fail("つながりませんでした。しくみの用意がまだかもしれません。");
        if (window.console) console.error(e);
        return null;
      });
    });
  }

  function closeModal() { $("modalRoot").innerHTML = ""; }
  function ymd(d) { return d.toISOString().slice(0, 10); }

  /* ------------------------------------------------------------ ログイン */

  $("loginForm").addEventListener("submit", function (e) {
    e.preventDefault();
    $("loginBtn").disabled = true;
    sb.auth.signInWithPassword({ email: $("email").value.trim(), password: $("password").value })
      .then(function (r) {
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
      var _u = (r && r.data && r.data.session) ? r.data.session.user : null;
      if (!_u) { showLogin(); return; }
      return sb.from("staff").select("*").eq("auth_user_id", _u.id).maybeSingle()
        .then(function (q) {
          if (q.error) { fail(q.error); return; }
          if (!q.data) { toast("このアカウントにスタッフ登録がありません。", "err"); return; }
          S.me = q.data;
          $("meName").textContent = S.me.name;
          $("login").classList.add("hidden");
          $("app").classList.remove("hidden");
          if (window.DANDORI_UI) window.DANDORI_UI.theme((CFG.theme || "dark")); else document.body.className = "theme-" + (CFG.theme || "dark");
          return loadStores();
        });
    }).catch(fail);
  }

  /*  お店のえらびかた
      ・その業種のお店だけを出します（store.industry を見ています）
      ・えらんだお店は、業種ごとに覚えます。
        更新しても、ページを移っても、入れかわりません。 */
  var MISEKEY = "dandori-store-" + (CFG.industry || "x");

  function loadStores() {
    return sb.rpc("store_list", { p_kind: CFG.industry || null })
      .then(function (q) {
        if (q.error || !q.data || !q.data.length) return storesFromTable();
        return putStores(q.data);
      })
      .catch(storesFromTable);
  }

  /*  store_list（022_mise.sql）がまだ入っていないときの、ひかえの道です */
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
    loadCasts().then(function () {
      var t = new Date();
      if (!$("attDate").value) $("attDate").value = ymd(t);
      if (!$("pFrom").value) {
        $("pFrom").value = ymd(new Date(t.getFullYear(), t.getMonth(), 1));
        $("pTo").value = ymd(t);
      }
      switchView("attend");
    });
  }

  function loadCasts() {
    return sb.from("night_cast").select("*").eq("store_id", S.store.id).order("name")
      .then(function (q) { S.casts = q.data || []; })
      .then(function () {
        /*  指名のメニューが無いお店（Olivia など）では、画面から「指名」を隠します。 */
        return sb.from("night_menu").select("id").eq("store_id", S.store.id)
          .eq("category", "nomination").eq("is_active", true).limit(1)
          .then(function (q) { S.useNom = !!(q.data && q.data.length); }, function () { S.useNom = true; });
      });
  }

  /* -------------------------------------------------------------- 画面切替 */

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  function switchView(v) {
    ["attend", "calc", "slip", "month", "cast", "roster"].forEach(function (n) {
      $("view-" + n).classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (v === "attend") loadAttendance();
    if (v === "cast") renderCasts();
    if (v === "roster") loadRoster();
    if (v === "slip") { if (!$("slipYm").value) $("slipYm").value = ymd(new Date()).slice(0, 7); loadSlips(); }
    if (v === "month") loadMonthly(12);
  }

  /* -------------------------------------------------------------- 出勤 */

  $("attReload").addEventListener("click", loadAttendance);
  $("attDate").addEventListener("change", loadAttendance);

  function loadAttendance() {
    var d = $("attDate").value;
    if (!d || !S.store) return;
    Promise.all([
      sb.from("night_attendance").select("*").eq("store_id", S.store.id).eq("business_date", d),
      sb.from("night_payout").select("cast_id,amount").eq("store_id", S.store.id).eq("business_date", d)
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      var att = {}, pay = {};
      (r[0].data || []).forEach(function (a) { att[a.cast_id] = a; });
      (r[1].data || []).forEach(function (p) { pay[p.cast_id] = (pay[p.cast_id] || 0) + p.amount; });

      $("attCards").innerHTML = S.casts.filter(function (c) { return c.is_active; }).map(function (c) {
        var a = att[c.id];
        var state = !a || !a.clock_in ? "未出勤"
                  : (!a.clock_out ? "出勤中" : "退勤済み");
        var t = function (x) {
          return x ? new Date(x).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }) : "—";
        };
        var mins = (a && a.clock_in && a.clock_out)
          ? Math.max(Math.round((new Date(a.clock_out) - new Date(a.clock_in)) / 60000), 0) : 0;
        return '<div class="card" style="cursor:default">' +
          '<span class="tno" style="font-size:18px">' + esc(c.name) + "</span>" +
          '<span class="meta"><span>' + state + "</span>" +
            "<span>入 " + t(a && a.clock_in) + "</span><span>退 " + t(a && a.clock_out) + "</span>" +
            (mins ? '<span class="mono">' + hm(mins) + "</span>" : "") +
          "</span>" +
          (pay[c.id] ? '<span class="meta"><span>日払い ' + yen(pay[c.id]) + "</span></span>" : "") +
          '<span class="row" style="margin-top:4px">' +
            '<button class="btn" data-in="' + c.id + '">出勤</button>' +
            '<button class="btn" data-out="' + c.id + '">退勤</button>' +
            '<button class="btn ghost" data-pay="' + c.id + '">日払い</button>' +
            '<button class="btn ghost" data-adj="' + c.id + '">手当・控除</button>' +
            '<button class="btn ghost" data-fix="' + c.id + '">修正</button>' +
          "</span></div>";
      }).join("");

      bind("[data-in]", "in", function (id) { punch("night_clock_in", id); });
      bind("[data-out]", "out", function (id) { punch("night_clock_out", id); });
      bind("[data-pay]", "pay", payoutDialog);
      bind("[data-adj]", "adj", adjustDialog);
      bind("[data-fix]", "fix", function (id) { attendDialog(id, att[id]); });
    });
  }

  /* 出勤・退勤の時刻を手で直す（押し忘れ・押し間違いの訂正） */
  function attendDialog(castId, a) {
    var hm2 = function (ts) {
      if (!ts) return "";
      var d = new Date(ts);
      return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    };
    modal("<h2>出勤の修正　" + esc(castName(castId)) + "</h2>" +
      "<p style='color:var(--muted);font-size:12.5px;margin:-8px 0 14px'>" +
        $("attDate").value + " の営業ぶん。空欄にすると、その記録を消します。</p>" +
      '<div class="row">' +
        '<div class="field" style="flex:1"><label for="f_in">出勤</label>' +
          '<input id="f_in" type="time" value="' + hm2(a && a.clock_in) + '"></div>' +
        '<div class="field" style="flex:1"><label for="f_out">退勤</label>' +
          '<input id="f_out" type="time" value="' + hm2(a && a.clock_out) + '"></div>' +
      "</div>" +
      "<p style='color:var(--muted);font-size:12px;margin:-6px 0 12px'>" +
        "営業日の切り替え時刻（既定05:00）より前の時刻は、翌日ぶんとして扱います。" +
        "20:30 出勤 → 01:15 退勤 なら、そのまま入れてください。</p>" +
      '<div class="field"><label for="f_late">遅刻（分）</label>' +
        '<input id="f_late" type="number" min="0" inputmode="numeric" value="' +
          ((a && a.late_minutes) || 0) + '"></div>' +
      '<div class="field"><label for="f_note">メモ</label>' +
        '<input id="f_note" value="' + esc((a && a.note) || "") + '" placeholder="押し忘れを修正"></div>' +
      '<div class="row" style="margin-top:16px">' +
        (a ? '<button class="btn danger" id="m_del">記録を消す</button>' : "") +
        '<button class="btn ghost" id="m_cancel">やめる</button>' +
        '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        var del = root.querySelector("#m_del");
        if (del) del.addEventListener("click", function () {
          sb.rpc("night_attendance_delete", { p_cast: castId, p_date: $("attDate").value })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal(); toast("記録を消しました", "ok"); loadAttendance();
            });
        });
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_attendance_set", {
            p_cast: castId,
            p_date: $("attDate").value,
            p_in: root.querySelector("#f_in").value || null,
            p_out: root.querySelector("#f_out").value || null,
            p_late: Number(root.querySelector("#f_late").value) || 0,
            p_note: root.querySelector("#f_note").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("保存しました", "ok"); loadAttendance();
          });
        });
      });
  }

  function bind(sel, attr, fn) {
    Array.prototype.forEach.call($("attCards").querySelectorAll(sel), function (b) {
      b.addEventListener("click", function () { fn(b.dataset[attr]); });
    });
  }

  function punch(rpc, castId) {
    sb.rpc(rpc, { p_cast: castId }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      toast(rpc === "night_clock_in" ? "出勤を記録しました" : "退勤を記録しました", "ok");
      loadAttendance();
    });
  }

  function castName(id) {
    var c = S.casts.filter(function (x) { return x.id === id; })[0];
    return c ? c.name : "";
  }

  function payoutDialog(castId) {
    modal("<h2>日払い　" + esc(castName(castId)) + "</h2>" +
      '<div class="field"><label for="a_amt">金額</label>' +
      '<input id="a_amt" type="number" min="1" inputmode="numeric" placeholder="10000"></div>' +
      '<div class="field"><label for="a_memo">メモ</label><input id="a_memo" placeholder="当日日払い"></div>' +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_payout_add", {
            p_cast: castId, p_date: $("attDate").value,
            p_amount: Number(root.querySelector("#a_amt").value) || 0,
            p_memo: root.querySelector("#a_memo").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("日払いを記録しました", "ok"); loadAttendance();
          });
        });
        root.querySelector("#a_amt").focus();
      });
  }

  function adjustDialog(castId) {
    modal("<h2>手当・控除　" + esc(castName(castId)) + "</h2>" +
      '<div class="field"><label for="j_kind">種類</label><select id="j_kind">' +
      '<option value="allowance">手当（支給）</option>' +
      '<option value="deduction">控除（差引き）</option></select></div>' +
      '<div class="field"><label for="j_name">名目</label><input id="j_name" placeholder="皆勤手当"></div>' +
      '<div class="field"><label for="j_amt">金額</label>' +
      '<input id="j_amt" type="number" min="0" inputmode="numeric"></div>' +
      '<div class="pay-check ng" style="font-size:12.5px">控除の扱いは、労働基準法で制限があります。' +
      '罰金のような控除は、就業規則と本人の同意がないと認められないことがあります。' +
      '設定内容は社労士にご確認ください。</div>' +
      '<div class="row" style="margin-top:14px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_adjust_add", {
            p_cast: castId, p_date: $("attDate").value,
            p_kind: root.querySelector("#j_kind").value,
            p_name: root.querySelector("#j_name").value.trim() || "その他",
            p_amount: Number(root.querySelector("#j_amt").value) || 0,
            p_memo: null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("記録しました", "ok"); loadAttendance();
          });
        });
      });
  }

  /* -------------------------------------------------------------- 給与 */

  $("pCalc").addEventListener("click", preview);
  $("pQuickHalf").addEventListener("click", function () {
    var t = new Date();
    $("pFrom").value = ymd(new Date(t.getFullYear(), t.getMonth(), 1));
    $("pTo").value = ymd(new Date(t.getFullYear(), t.getMonth(), 15));
    preview();
  });
  $("pQuickMonth").addEventListener("click", function () {
    var t = new Date();
    $("pFrom").value = ymd(new Date(t.getFullYear(), t.getMonth(), 1));
    $("pTo").value = ymd(new Date(t.getFullYear(), t.getMonth() + 1, 0));
    preview();
  });

  function preview() {
    var f = $("pFrom").value, t = $("pTo").value;
    if (!f || !t) { toast("期間を選んでください", "err"); return; }
    sb.rpc("night_payroll_preview", { p_store: S.store.id, p_from: f, p_to: t })
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        S.rows = q.data || [];
        renderPreview(f, t);
      });
  }

  function renderPreview(f, t) {
    var rows = S.rows.filter(function (r) {
      return r.work_minutes > 0 || r.back_amount > 0 || r.allowance > 0 || r.deduction > 0 || r.advance > 0;
    });
    $("payEmpty").classList.toggle("hidden", rows.length > 0);
    if (!rows.length) {
      $("payTable").innerHTML = "";
      $("payEmpty").textContent = "この期間に、出勤も売上もありません。";
      $("payActions").innerHTML = "";
      return;
    }

    var sum = function (k) { return rows.reduce(function (a, r) { return a + (r[k] || 0); }, 0); };
    var warn = rows.filter(function (r) { return r.below_min_wage; });

    $("payTable").innerHTML =
      "<tr><th>キャスト</th><th class='num'>時間</th><th class='num'>時給</th>" +
      "<th class='num'>時給ぶん</th><th class='num'>バック</th><th class='num'>手当</th>" +
      "<th class='num'>控除</th><th class='num'>日払い</th><th class='num'>差引支給</th><th></th></tr>" +
      rows.map(function (r) {
        return "<tr>" +
          "<td>" + esc(r.cast_name) +
            (r.confirmed ? ' <span class="tag settled">確定済</span>' : "") +
            (r.below_min_wage ? ' <span class="tag open">最低賃金未満</span>' : "") +
            "<br><span style='color:var(--muted);font-size:11.5px'>" +
            (S.useNom ? "本指名 " + r.nominations + "／" : "") +
            "同伴 " + r.douhans + "／" + r.work_days + "日" +
            (r.achieved_pct != null && r.work_minutes > 0 ? "／達成率 " + r.achieved_pct + "%" : "") + "</span></td>" +
          "<td class='num'>" + hm(r.work_minutes) + "</td>" +
          "<td class='num'>" + yen(r.hourly_applied) +
            (r.hourly_applied !== r.hourly_base ?
              "<br><span style='color:var(--gold);font-size:11px'>スライド適用</span>" : "") + "</td>" +
          "<td class='num'>" + yen(r.wage_amount) + "</td>" +
          "<td class='num'>" + yen(r.back_amount) +
            (r.back_bonus > 0 ? "<br><span style='color:var(--gold);font-size:11px'>うち達成分 " + yen(r.back_bonus) + "</span>" : "") + "</td>" +
          "<td class='num'>" + yen(r.allowance) + "</td>" +
          "<td class='num'>" + (r.deduction ? "-" + yen(r.deduction) : "—") + "</td>" +
          "<td class='num'>" + (r.advance ? "-" + yen(r.advance) : "—") + "</td>" +
          "<td class='num' style='font-weight:700'>" + yen(r.net_amount) + "</td>" +
          '<td><button class="btn ghost" style="padding:6px 12px" data-slip="' + r.cast_id + '">明細</button></td>' +
        "</tr>";
      }).join("") +
      "<tr><td style='font-weight:700'>合計 " + rows.length + "名</td><td colspan='7'></td>" +
      "<td class='num' style='font-weight:700;color:var(--gold)'>" + yen(sum("net_amount")) + "</td><td></td></tr>";

    Array.prototype.forEach.call($("payTable").querySelectorAll("button[data-slip]"), function (b) {
      b.addEventListener("click", function () { showSlip(b.dataset.slip, f, t); });
    });

    $("payActions").innerHTML =
      (warn.length ? '<div class="pay-check ng" style="width:100%">' + warn.length +
        "名の時給が、設定した最低賃金（" + yen(S.store.min_wage) +
        "）を下回っています。時給の設定を確認してください。</div>" : "") +
      '<button class="btn primary" id="confirmBtn">この期間を確定する</button>' +
      '<span style="color:var(--muted);font-size:12.5px">確定すると記録として残ります。あとから再計算して上書きもできます。</span>';

    $("confirmBtn").addEventListener("click", function () {
      var btn = this; btn.disabled = true;
      sb.rpc("night_payroll_confirm", { p_store: S.store.id, p_from: f, p_to: t, p_cast: null })
        .then(function (q) {
          btn.disabled = false;
          if (q.error) { fail(q.error); return; }
          toast(q.data + "名ぶんを確定しました", "ok");
          preview();
        });
    });
  }

  function showSlip(castId, f, t) {
    var r = S.rows.filter(function (x) { return x.cast_id === castId; })[0];
    if (!r) return;
    var line = function (label, val, minus) {
      return "<div><span>" + label + "</span><span class='mono'>" +
        (minus && val ? "-" : "") + yen(val) + "</span></div>";
    };
    modal(
      "<h2>" + esc(r.cast_name) + "　給与明細</h2>" +
      "<p style='color:var(--muted);font-size:12.5px;margin:-8px 0 14px'>" +
        f + " 〜 " + t + "　／　" + S.store.name + "</p>" +
      '<div class="totals">' +
        "<div><span>出勤</span><span class='mono'>" + r.work_days + "日　" + hm(r.work_minutes) + "</span></div>" +
        "<div><span>適用時給</span><span class='mono'>" + yen(r.hourly_applied) +
          (r.hourly_applied !== r.hourly_base ? "（基本 " + yen(r.hourly_base) + "）" : "") + "</span></div>" +
        (S.useNom
          ? "<div><span>本指名／同伴／ドリンク</span><span class='mono'>" +
              r.nominations + " / " + r.douhans + " / " + r.drinks + "</span></div>"
          : "<div><span>同伴／ドリンク</span><span class='mono'>" +
              r.douhans + " / " + r.drinks + "</span></div>") +
        (r.achieved_pct != null && r.work_minutes > 0 ?
          "<div><span>個人売上／達成率</span><span class='mono'>" + yen(r.sales) + "／" + r.achieved_pct + "%</span></div>" : "") +
        "<div style='border-top:1px solid var(--line);margin-top:8px;padding-top:8px'></div>" +
        line("時給ぶん", r.wage_amount) +
        line("バック" + (r.back_bonus > 0 ? "（うち達成分 " + yen(r.back_bonus) + "）" : ""), r.back_amount) +
        line("手当", r.allowance) +
        line("控除", r.deduction, true) +
        line("日払い済み", r.advance, true) +
        "<div class='grand'><span>差引支給額</span><span class='mono'>" + yen(r.net_amount) + "</span></div>" +
      "</div>" +
      '<div class="row" style="margin-top:16px">' +
        '<button class="btn ghost" id="m_print">印刷</button>' +
        '<button class="btn primary" id="m_close" style="flex:1">閉じる</button></div>',
      function (root) {
        root.querySelector("#m_close").addEventListener("click", closeModal);
        root.querySelector("#m_print").addEventListener("click", function () { window.print(); });
      }
    );
  }

  /* -------------------------------------------------------------- キャスト設定 */

  function renderCasts() {
    $("castTable").innerHTML =
      "<tr><th>名前</th><th class='num'>基本時給</th><th>時給スライド</th>" +
      "<th>明細の受け取り方</th><th>状態</th><th></th></tr>" +
      S.casts.map(function (c) {
        var rules = (c.wage_rules || []).map(function (r) {
          var cond = r.type === "nomination" ? "本指名" + r.from + "本以上"
                   : r.type === "ratio" ? "達成率" + r.from + "%以上"
                   : "売上" + Number(r.from).toLocaleString() + "円以上";
          return cond + " → " + yen(r.wage) +
            (r.back_rate ? "・バック" + r.back_rate + "%〜" : "");
        });
        return "<tr><td>" + esc(c.name) + "</td>" +
          "<td class='num'>" + yen(c.hourly_wage) + "</td>" +
          "<td style='font-size:12.5px;color:var(--muted)'>" +
            (rules.length ? rules.join("<br>") : "なし") + "</td>" +
          "<td>" + slipWant(c) + "</td>" +
          "<td>" + (c.is_active ? "在籍" : "退店") + "</td>" +
          '<td class="row" style="gap:6px">' +
            '<button class="btn ghost" style="padding:6px 12px" data-edit="' + c.id + '">編集</button>' +
            '<button class="btn ghost" style="padding:6px 12px" data-cont="' + c.id + '">受け取り方</button>' +
          "</td></tr>";
      }).join("");

    Array.prototype.forEach.call($("castTable").querySelectorAll("button[data-edit]"), function (b) {
      b.addEventListener("click", function () { castDialog(b.dataset.edit); });
    });
    Array.prototype.forEach.call($("castTable").querySelectorAll("button[data-cont]"), function (b) {
      b.addEventListener("click", function () { contactDialog(b.dataset.cont); });
    });
  }

  /* 明細の受け取り方（ご本人に選んでいただきます） */
  function slipWant(c) {
    var m = c.payslip_method || "print";
    var label = { print: "印刷（手渡し）", line: "LINE", email: "メール", none: "渡さない" }[m] || m;
    var ready = m === "print" || m === "none" ||
                (m === "line" ? !!c.line_user_id : !!c.email);
    return "<span style='font-size:13px'>" + label + "</span>" +
           (ready ? "" : " <span class='pill warn'>送り先なし</span>");
  }

  function contactDialog(id) {
    var c = S.casts.filter(function (x) { return x.id === id; })[0];
    if (!c) return;
    var m = c.payslip_method || "print";
    modal(
      "<h2>" + esc(c.name) + " さんの受け取り方</h2>" +
      "<p style='color:var(--muted);font-size:13px'>" +
      "給与明細をどう受け取りたいか、ご本人にうかがって選んでください。</p>" +
      "<label class='field'><span>受け取り方</span><select id='k_m'>" +
        [["print", "印刷して手渡し"], ["line", "LINE"], ["email", "メール"], ["none", "渡さない"]]
        .map(function (o) {
          return "<option value='" + o[0] + "'" + (o[0] === m ? " selected" : "") + ">" +
                 o[1] + "</option>";
        }).join("") +
      "</select></label>" +
      "<label class='field'><span>メールアドレス</span>" +
        "<input id='k_mail' type='email' value='" + esc(c.email || "") + "'></label>" +
      "<label class='field'><span>LINEのID</span>" +
        "<input id='k_line' value='" + esc(c.line_user_id || "") + "'>" +
        "<span style='font-size:12px;color:var(--muted)'>" +
        "お店のLINE公式アカウントを友だち追加していただくと分かります。</span></label>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button>" +
      "<button class='btn primary' id='m_ok'>保存する</button></div>",
      function (root) {
        root.querySelector("#m_no").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_cast_contact_set", {
            p_cast: id,
            p_method: root.querySelector("#k_m").value,
            p_email: root.querySelector("#k_mail").value.trim() || null,
            p_line: root.querySelector("#k_line").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal();
            toast("保存しました", "ok");
            loadCasts().then(renderCasts);
          });
        });
      });
  }

  $("castAdd").addEventListener("click", function () { castDialog(null); });

  function castDialog(id) {
    var c = id ? S.casts.filter(function (x) { return x.id === id; })[0] : null;
    var r1 = (c && (c.wage_rules || []).filter(function (r) { return r.type === "nomination"; })[0]) || {};
    var r2 = (c && (c.wage_rules || []).filter(function (r) { return r.type === "sales"; })[0]) || {};
    var r3 = (c && (c.wage_rules || []).filter(function (r) { return r.type === "ratio"; })) || [];
    var ratioRows = "";
    for (var ri = 0; ri < 3; ri++) {
      var rr = r3[ri] || {};
      ratioRows += '<div class="row" style="margin-bottom:6px">' +
        '<input id="c_r_from' + ri + '" type="number" min="0" placeholder="' + [150, 200, 300][ri] + '" style="flex:1" value="' +
          (rr.from != null ? rr.from : "") + '">' +
        '<input id="c_r_wage' + ri + '" type="number" min="0" placeholder="' + [2500, 2500, 3000][ri] + '" style="flex:1" value="' +
          (rr.wage != null ? rr.wage : "") + '">' +
        '<input id="c_r_back' + ri + '" type="number" min="0" max="100" placeholder="' + (ri ? "20" : "") + '" style="flex:1" value="' +
          (rr.back_rate != null ? rr.back_rate : "") + '"></div>';
    }

    var val = function (k) { return esc(c && c[k] != null ? c[k] : ""); };

    modal("<h2>" + (c ? "キャストの編集" : "キャストを追加") + "</h2>" +
      '<div class="field"><label for="c_name">源氏名</label>' +
        '<input id="c_name" value="' + esc(c ? c.name : "") + '"></div>' +
      '<div class="field"><label for="c_real">氏名（名簿用）</label>' +
        '<input id="c_real" value="' + val("real_name") + '"></div>' +
      '<div class="field"><label for="c_birth">生年月日</label>' +
        '<input id="c_birth" type="date" value="' + val("birth_date") + '"></div>' +
      '<div class="field"><label for="c_addr">住所</label>' +
        '<input id="c_addr" value="' + val("address") + '"></div>' +
      '<div class="field"><label for="c_phone">電話番号</label>' +
        '<input id="c_phone" value="' + val("phone") + '"></div>' +
      '<div class="field"><label for="c_em">緊急連絡先（お名前／電話）</label>' +
        '<div class="row"><input id="c_em_name" style="flex:1" value="' + val("emergency_name") + '">' +
        '<input id="c_em_tel" style="flex:1" value="' + val("emergency_phone") + '"></div></div>' +
      '<div class="field"><label for="c_job">業務の種類</label>' +
        '<input id="c_job" value="' + (c && c.job_type ? esc(c.job_type) : "接客") + '"></div>' +
      '<div class="field"><label for="c_joined">雇入年月日</label>' +
        '<input id="c_joined" type="date" value="' + val("joined_on") + '"></div>' +
      '<div class="field"><label for="c_wage">基本時給（円）</label>' +
        '<input id="c_wage" type="number" min="0" inputmode="numeric" value="' + (c ? c.hourly_wage : 0) + '"></div>' +
      '<div class="field"' + (S.useNom ? "" : ' style="display:none"') + '><label for="c_n_from">本指名 ○本以上で時給（空欄ならスライドなし）</label>' +
        '<div class="row"><input id="c_n_from" type="number" min="0" placeholder="10" style="flex:1" value="' +
          (r1.from != null ? r1.from : "") + '">' +
        '<input id="c_n_wage" type="number" min="0" placeholder="3000" style="flex:1" value="' +
          (r1.wage != null ? r1.wage : "") + '"></div></div>' +
      '<div class="field"><label for="c_s_from">売上 ○円以上で時給</label>' +
        '<div class="row"><input id="c_s_from" type="number" min="0" placeholder="300000" style="flex:1" value="' +
          (r2.from != null ? r2.from : "") + '">' +
        '<input id="c_s_wage" type="number" min="0" placeholder="3500" style="flex:1" value="' +
          (r2.wage != null ? r2.wage : "") + '"></div></div>' +
      '<div class="field"><label>達成率スライド（達成率% ／ 時給 ／ バック下限%）</label>' +
        '<div style="color:var(--muted);font-size:11.5px;margin-bottom:6px">達成率 ＝ 個人売上 ÷（基本時給 × 勤務時間）。' +
        'バック下限は、達成したときにボトルなどのバック率を少なくともその%にします（空欄なら時給だけ）</div>' +
        ratioRows + '</div>' +
      (c ? '<div class="field"><label for="c_active">状態</label><select id="c_active">' +
        '<option value="1"' + (c.is_active ? " selected" : "") + ">在籍</option>" +
        '<option value="0"' + (!c.is_active ? " selected" : "") + ">退店</option></select></div>" : "") +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var rules = [];
          var nf = root.querySelector("#c_n_from").value, nw = root.querySelector("#c_n_wage").value;
          var sf = root.querySelector("#c_s_from").value, sw = root.querySelector("#c_s_wage").value;
          if (nf !== "" && nw !== "") rules.push({ type: "nomination", from: Number(nf), wage: Number(nw) });
          if (sf !== "" && sw !== "") rules.push({ type: "sales", from: Number(sf), wage: Number(sw) });
          for (var ri = 0; ri < 3; ri++) {
            var rf = root.querySelector("#c_r_from" + ri).value, rw = root.querySelector("#c_r_wage" + ri).value;
            var rb = root.querySelector("#c_r_back" + ri).value;
            if (rf !== "" && rw !== "") {
              var rule = { type: "ratio", from: Number(rf), wage: Number(rw) };
              if (rb !== "") rule.back_rate = Number(rb);
              rules.push(rule);
            }
          }

          var txt = function (id) {
            var v = root.querySelector("#" + id).value.trim();
            return v === "" ? null : v;
          };
          var payload = {
            tenant_id: S.me.tenant_id,
            store_id: S.store.id,
            name: root.querySelector("#c_name").value.trim(),
            real_name: txt("c_real"),
            birth_date: txt("c_birth"),
            address: txt("c_addr"),
            phone: txt("c_phone"),
            emergency_name: txt("c_em_name"),
            emergency_phone: txt("c_em_tel"),
            job_type: txt("c_job") || "接客",
            joined_on: txt("c_joined"),
            hourly_wage: Number(root.querySelector("#c_wage").value) || 0,
            wage_rules: rules
          };
          if (!payload.name) { toast("名前を入れてください", "err"); return; }

          var q;
          if (c) {
            var act = root.querySelector("#c_active");
            payload.is_active = act ? act.value === "1" : true;
            q = sb.from("night_cast").update(payload).eq("id", c.id);
          } else {
            q = sb.from("night_cast").insert(payload);
          }
          q.then(function (res) {
            if (res.error) { fail(res.error); return; }
            closeModal(); toast("保存しました", "ok");
            loadCasts().then(function () {
              if (!$("view-roster").classList.contains("hidden")) loadRoster();
              else renderCasts();
            });
          });
        });
      });
  }

  /* -------------------------------------------------------------- 名簿 */

  $("rosterPrint").addEventListener("click", function () { window.print(); });

  function loadRoster() {
    sb.from("v_employee_roster").select("*").eq("store_id", S.store.id).order("display_name")
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var rows = q.data || [];
        var bad = rows.filter(function (r) { return r.is_active && (r.roster_incomplete || r.id_check_missing); });

        $("rosterAlert").innerHTML = bad.length
          ? '<div class="pay-check ng">' + bad.length +
            "名、名簿の記載か本人確認が足りていません。求められたときに出せるよう、先に埋めてください。</div>"
          : '<div class="pay-check ok">在籍者全員、名簿の記載と本人確認の記録が揃っています。</div>';

        $("rosterTable").innerHTML =
          "<tr><th>源氏名</th><th>氏名</th><th class='num'>生年月日</th><th class='num'>年齢</th>" +
          "<th>業務</th><th class='num'>雇入</th><th>本人確認</th><th>状態</th><th></th></tr>" +
          rows.map(function (r) {
            var tags = [];
            if (r.roster_incomplete) tags.push('<span class="tag open">記載もれ</span>');
            if (r.id_check_missing) tags.push('<span class="tag open">未確認</span>');
            if (r.under_20) tags.push('<span class="tag partial">20歳未満</span>');
            if (!r.is_active) tags.push('<span class="tag settled">退店</span>');
            return "<tr" + (!r.is_active ? " style='opacity:.55'" : "") + ">" +
              "<td>" + esc(r.display_name) + "</td>" +
              "<td>" + (r.real_name ? esc(r.real_name) : "<span style='color:var(--bad)'>未記入</span>") + "</td>" +
              "<td class='num'>" + (r.birth_date || "<span style='color:var(--bad)'>未記入</span>") + "</td>" +
              "<td class='num'>" + (r.age != null ? r.age + "歳" : "—") + "</td>" +
              "<td>" + esc(r.job_type || "—") + "</td>" +
              "<td class='num'>" + (r.joined_on || "—") + "</td>" +
              "<td>" + (r.id_checked_on
                  ? esc(r.id_doc_type) + "<br><span style='color:var(--muted);font-size:11.5px'>" +
                    r.id_checked_on + " 確認</span>"
                  : "<span style='color:var(--bad)'>記録なし</span>") + "</td>" +
              "<td>" + (tags.join(" ") || "—") + "</td>" +
              '<td class="no-print"><button class="btn ghost" style="padding:6px 10px" data-idc="' + r.cast_id +
                '">確認を記録</button> ' +
                '<button class="btn ghost" style="padding:6px 10px" data-edit2="' + r.cast_id + '">編集</button></td>' +
            "</tr>";
          }).join("");

        Array.prototype.forEach.call($("rosterTable").querySelectorAll("button[data-idc]"), function (b) {
          b.addEventListener("click", function () { idCheckDialog(b.dataset.idc); });
        });
        Array.prototype.forEach.call($("rosterTable").querySelectorAll("button[data-edit2]"), function (b) {
          b.addEventListener("click", function () { castDialog(b.dataset.edit2); });
        });
      });
  }

  function idCheckDialog(castId) {
    var c = S.casts.filter(function (x) { return x.id === castId; })[0];
    modal("<h2>本人確認の記録　" + esc(c ? c.name : "") + "</h2>" +
      (c && !c.birth_date
        ? '<div class="pay-check ng">先に生年月日を登録してください（「編集」から）。</div>'
        : "") +
      '<div class="field"><label for="k_doc">確認した書類</label><select id="k_doc">' +
        ["運転免許証", "マイナンバーカード", "パスポート", "在留カード", "健康保険証＋補助書類", "住民票"]
          .map(function (d) { return "<option>" + d + "</option>"; }).join("") +
      "</select></div>" +
      '<div class="field"><label for="k_method">確認の方法</label><select id="k_method">' +
        '<option value="original">原本を提示してもらった</option>' +
        '<option value="copy">写しを受け取った</option>' +
        '<option value="video">オンラインで確認した</option></select></div>' +
      '<div class="field"><label for="k_on">確認日</label>' +
        '<input id="k_on" type="date" value="' + ymd(new Date()) + '"></div>' +
      '<div class="field"><label for="k_note">メモ</label><input id="k_note"></div>' +
      '<div class="pay-check ng" style="font-size:12.5px">身分証の画像は保存しません。' +
        '「いつ・誰が・何で確認したか」だけを記録に残します。</div>' +
      '<div class="row" style="margin-top:14px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_id_check_add", {
            p_cast: castId,
            p_doc_type: root.querySelector("#k_doc").value,
            p_method: root.querySelector("#k_method").value,
            p_on: root.querySelector("#k_on").value,
            p_note: root.querySelector("#k_note").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal();
            toast("確認日：" + q.data.checked_on + "　当時" + q.data.age_at_check + "歳 として記録しました", "ok");
            loadRoster();
          });
        });
      });
  }

  /* ============================================================ 給与明細 */

  var SLIP_METHOD = { print: "印刷", line: "LINE", email: "メール", none: "渡さない" };

  $("slipLoad").addEventListener("click", loadSlips);
  $("slipYm").addEventListener("change", loadSlips);

  function slipRange() {
    var ym = $("slipYm").value;
    if (!ym) return null;
    var y = +ym.slice(0, 4), m = +ym.slice(5, 7);
    var from = new Date(y, m - 1, 1), to = new Date(y, m, 0);
    return { ym: ym, from: ymd(from), to: ymd(to) };
  }

  function loadSlips() {
    var r = slipRange();
    if (!r || !S.store) return;
    Promise.all([
      sb.rpc("payslip_list", { p_store: S.store.id, p_ym: r.ym, p_kind: null }),
      sb.rpc("outbox_status", { p_store: S.store.id })
    ]).then(function (q) {
      if (q[0].error) { fail(q[0].error); return; }
      S.slips = q[0].data || [];
      renderSlips();
      renderOutbox(q[1].data || []);
    });
  }

  function renderOutbox(rows) {
    var q = 0, f = 0, err = "";
    rows.forEach(function (o) {
      q += o.queued || 0; f += o.failed || 0;
      if (o.last_error && !err) err = o.last_error;
    });
    var html = "";
    if (q) {
      html += '<div class="box warn">送信待ちが ' + q + ' 件あります。' +
              'LINE・メールは、送信のしくみが用意できてから順に送られます。</div>';
    }
    if (f) {
      html += '<div class="box bad">送れなかったものが ' + f + ' 件あります。' +
              (err ? esc(err) : "") + "</div>";
    }
    $("slipOutbox").innerHTML = html;
  }

  function renderSlips() {
    var rows = S.slips || [];
    $("slipEmpty").classList.toggle("hidden", rows.length > 0);
    if (!rows.length) { $("slipTable").innerHTML = ""; return; }

    var h = "<thead><tr><th>No</th><th>お名前</th><th class='num'>支給</th>" +
            "<th class='num'>控除</th><th class='num'>日払い</th><th class='num'>差引支給</th>" +
            "<th>受け取り方</th><th>状態</th><th></th></tr></thead><tbody>";

    rows.forEach(function (r) {
      var want = SLIP_METHOD[r.want_method] || "印刷";
      var ready = r.want_method === "print" || !!r.contact;
      var state = r.status === "sent"
        ? "送りました（" + (SLIP_METHOD[r.method] || r.method) + "）"
        : (r.status === "void" ? "取り消し" : "未送付");

      h += "<tr><td class='mono'>" + r.issue_no + "</td>" +
        "<td>" + esc(r.subject_name) + "</td>" +
        "<td class='num'>" + yen(r.gross) + "</td>" +
        "<td class='num'>" + yen(r.deduction) + "</td>" +
        "<td class='num'>" + yen(r.advance) + "</td>" +
        "<td class='num'><b>" + yen(r.net) + "</b></td>" +
        "<td>" + want + (ready ? "" : " <span class='pill warn'>送り先なし</span>") + "</td>" +
        "<td>" + state + "</td>" +
        "<td style='white-space:nowrap'>" +
          "<button class='btn' data-print='" + r.id + "'>印刷</button> " +
          "<button class='btn ghost' data-detail='" + r.id + "'>内訳</button>" +
          (r.status === "void" ? "" :
            " <button class='btn ghost' data-send='" + r.id + "'>送る</button>") +
        "</td></tr>";
    });
    $("slipTable").innerHTML = h + "</tbody>";

    Array.prototype.forEach.call($("slipTable").querySelectorAll("[data-print]"), function (b) {
      b.addEventListener("click", function () { printSlip(b.dataset.print); });
    });
    Array.prototype.forEach.call($("slipTable").querySelectorAll("[data-send]"), function (b) {
      b.addEventListener("click", function () { sendSlip(b.dataset.send); });
    });
    Array.prototype.forEach.call($("slipTable").querySelectorAll("[data-detail]"), function (b) {
      b.addEventListener("click", function () {
        var r = rows.filter(function (x) { return x.id === b.dataset.detail; })[0];
        showDetail(r.subject_id, r.subject_name, r.period_from, r.period_to);
      });
    });
  }

  $("slipIssue").addEventListener("click", function () {
    var r = slipRange();
    if (!r) return;
    modal(
      "<h3>" + r.ym + " の明細をつくります</h3>" +
      "<p>対象期間： " + r.from + " 〜 " + r.to + "</p>" +
      "<p style='color:var(--muted);font-size:13px'>" +
      "すでにこの期間の明細がある方は、いったん取り消して作り直します。<br>" +
      "確定した給与が1件もない場合は、つくれません。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button>" +
      "<button class='btn primary' id='m_ok'>つくる</button></div>",
      function (root) {
        root.querySelector("#m_no").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_payslip_issue", {
            p_store: S.store.id, p_from: r.from, p_to: r.to, p_cast: null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal();
            toast(q.data + "名ぶんの明細をつくりました", "ok");
            loadSlips();
          });
        });
      });
  });

  function sendSlip(id) {
    var row = (S.slips || []).filter(function (r) { return r.id === id; })[0] || {};
    var want = row.want_method || "print";
    modal(
      "<h3>" + esc(row.subject_name || "") + " さまへ送ります</h3>" +
      "<label class='field'><span>送り方</span><select id='k_m'>" +
        ["print", "line", "email"].map(function (m) {
          return "<option value='" + m + "'" + (m === want ? " selected" : "") + ">" +
                 SLIP_METHOD[m] + (m === want ? "（ご希望）" : "") + "</option>";
        }).join("") +
      "</select></label>" +
      "<p style='color:var(--muted);font-size:13px'>" +
      "「印刷」を選ぶと、印刷用の明細が開きます。渡した記録が残ります。<br>" +
      "LINE・メールは送信箱に入り、順に送られます。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button>" +
      "<button class='btn primary' id='m_ok'>送る</button></div>",
      function (root) {
        root.querySelector("#m_no").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var m = root.querySelector("#k_m").value;
          sb.rpc("payslip_send", { p_id: id, p_method: m, p_attach_path: null })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal();
              if (m === "print") { printSlip(id); loadSlips(); }
              else { toast("送信箱に入れました。送り出します…", "ok"); pushNow(); }
            });
        });
      });
  }

  /* 送信箱に入れたものを、その場で送り出します */
  function pushNow() {
    return callFn("send-outbox", {}).then(function (r) {
      if (!r) return;
      if (r.sent || r.failed) {
        toast((r.sent || 0) + "件を送り出しました" +
          (r.failed ? "／" + r.failed + "件は送れませんでした" : ""),
          r.failed ? "err" : "ok");
      }
      loadSlips();
    });
  }

  $("slipSendAll").addEventListener("click", function () {
    var r = slipRange();
    if (!r) return;
    sb.rpc("payslip_send_all", { p_store: S.store.id, p_ym: r.ym }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var d = (q.data && q.data[0]) || q.data || {};
      var msg = (d.sent || 0) + "件を送信箱に入れました";
      if (d.skipped) msg += "／" + d.skipped + "件は入れられませんでした";
      toast(msg, d.skipped ? "err" : "ok");
      pushNow();
      if (d.skipped && d.detail && d.detail.length) {
        modal("<h3>送れなかった方</h3><ul style='line-height:1.8'>" +
          d.detail.map(function (x) {
            return "<li>" + esc(x.name) + "：" + esc(x.reason) + "</li>";
          }).join("") + "</ul>" +
          "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
          "<button class='btn primary' id='m_ok'>閉じる</button></div>",
          function (root) { root.querySelector("#m_ok").addEventListener("click", closeModal); });
      }
      loadSlips();
    });
  });

  /* ----------------------------------------------- 明細の印刷（指定の書式） */

  function printSlip(id) {
    sb.rpc("payslip_get", { p_id: id }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var d = q.data;
      var earn = d.lines.filter(function (l) { return l.section === "earning"; });
      var ded  = d.lines.filter(function (l) { return l.section === "deduction"; });
      var info = d.lines.filter(function (l) { return l.section === "info"; });

      function tbl(title, arr, money) {
        if (!arr.length) return "";
        return "<div class='ps-col'><h4>" + title + "</h4><table>" +
          arr.map(function (l) {
            return "<tr><th>" + esc(l.label) + "</th><td class='num'>" +
              (l.qty != null ? "<span class='q'>" + (+l.qty) + esc(l.unit || "") + "</span>" : "") +
              (money ? yen(l.amount) : "") + "</td></tr>";
          }).join("") + "</table></div>";
      }

      var html =
        "<div class='ps-head'>" +
          "<div class='ps-t'>" + esc(d.title) + "</div>" +
          "<div class='ps-no'>No. " + d.issue_no + "　発行 " +
            new Date(d.issued_at).toLocaleDateString("ja-JP") + "</div>" +
        "</div>" +
        "<div class='ps-to'>" +
          "<div class='ps-name'>" + esc(d.subject_name) + " 様</div>" +
          "<div class='ps-period'>対象期間　" +
            d.period_from.replace(/-/g, "/") + " 〜 " + d.period_to.replace(/-/g, "/") + "</div>" +
        "</div>" +
        "<div class='ps-net'><span>差引支給額</span><b>" + yen(d.net) + "</b></div>" +
        "<div class='ps-cols'>" + tbl("支給", earn, true) + tbl("控除", ded, true) + tbl("参考", info, false) + "</div>" +
        (d.foot_note ? "<div class='ps-note'>" + esc(d.foot_note) + "</div>" : "") +
        "<div class='ps-issuer'>" + esc(d.issuer || "") +
          (d.store ? "　" + esc(d.store) : "") +
          (d.store_tel ? "　" + esc(d.store_tel) : "") +
          (d.store_address ? "<br>" + esc(d.store_address) : "") +
        "</div>";

      modal(
        "<div class='payslip' id='payslipBody'>" + html +
          "<div id='psDetail'></div></div>" +
        "<div class='row no-print' style='justify-content:space-between;margin-top:16px'>" +
        "<label class='row' style='gap:6px;font-size:13px'>" +
          "<input type='checkbox' id='m_det'> 内訳（日ごと・指名の明細）をつける</label>" +
        "<span class='row' style='gap:8px'>" +
        "<button class='btn ghost' id='m_no'>閉じる</button>" +
        "<button class='btn primary' id='m_ok'>印刷する</button></span></div>",
        function (root) {
          root.querySelector("#m_det").addEventListener("change", function () {
            if (!this.checked) { root.querySelector("#psDetail").innerHTML = ""; return; }
            sb.rpc("payslip_detail", { p_id: id }).then(function (r2) {
              if (r2.error) { fail(r2.error); return; }
              root.querySelector("#psDetail").innerHTML = detailHtml(r2.data);
            });
          });
          root.querySelector("#m_no").addEventListener("click", closeModal);
          root.querySelector("#m_ok").addEventListener("click", function () {
            document.body.classList.add("printing-slip");
            window.print();
            setTimeout(function () { document.body.classList.remove("printing-slip"); }, 500);
            if (d.status !== "sent") {
              sb.rpc("payslip_send", { p_id: id, p_method: "print", p_attach_path: null })
                .then(function () { loadSlips(); });
            }
          });
        });
    });
  }

  /* ============================================================ 内訳 */

  /* 印刷用（明細の2枚目として付ける） */
  function detailHtml(d) {
    var daily = d.daily || [], sum = d.summary || [], items = d.items || [];
    var h = "<div class='ps-break'></div>" +
      "<div class='ps-head'><div class='ps-t' style='font-size:17px'>内訳</div>" +
      "<div class='ps-no'>" + esc(d.subject_name) + " 様　" +
      String(d.period_from).replace(/-/g, "/") + " 〜 " +
      String(d.period_to).replace(/-/g, "/") + "</div></div>";

    h += "<h4 class='ps-sub'>日ごと</h4><table class='ps-detail'>" +
      "<thead><tr><th>日</th><th>出勤</th><th>退勤</th><th class='num'>時間</th>" +
      "<th class='num'>時給ぶん</th>" + (S.useNom ? "<th class='num'>指名</th>" : "") + "<th class='num'>同伴</th>" +
      "<th class='num'>ドリンク</th><th class='num'>バック</th><th class='num'>日払い</th>" +
      "</tr></thead><tbody>";
    daily.forEach(function (r) {
      h += "<tr><td>" + String(r.business_date).slice(5).replace("-", "/") +
        "（" + esc(r.weekday) + "）</td>" +
        "<td>" + (r.clock_in_hm || "—") + "</td>" +
        "<td>" + (r.clock_out_hm || "—") + "</td>" +
        "<td class='num'>" + (+r.work_hours) + "h</td>" +
        "<td class='num'>" + yen(r.wage_amount) + "</td>" +
        (S.useNom ? "<td class='num'>" + (r.nominations || "") + "</td>" : "") +
        "<td class='num'>" + (r.douhans || "") + "</td>" +
        "<td class='num'>" + (r.drinks || "") + "</td>" +
        "<td class='num'>" + yen(r.back_amount) + "</td>" +
        "<td class='num'>" + (r.payout ? yen(r.payout) : "") + "</td></tr>";
    });
    var tot = daily.reduce(function (a, r) {
      a.h += +r.work_hours; a.w += r.wage_amount; a.n += r.nominations;
      a.d += r.douhans; a.k += r.drinks; a.b += r.back_amount; a.p += r.payout;
      return a;
    }, { h: 0, w: 0, n: 0, d: 0, k: 0, b: 0, p: 0 });
    h += "<tr class='ps-total'><td colspan='3'>合計　" + daily.length + "日</td>" +
      "<td class='num'>" + Math.round(tot.h * 100) / 100 + "h</td>" +
      "<td class='num'>" + yen(tot.w) + "</td>" +
      (S.useNom ? "<td class='num'>" + tot.n + "</td>" : "") + "<td class='num'>" + tot.d + "</td>" +
      "<td class='num'>" + tot.k + "</td><td class='num'>" + yen(tot.b) + "</td>" +
      "<td class='num'>" + yen(tot.p) + "</td></tr></tbody></table>";

    if (sum.length) {
      h += "<h4 class='ps-sub'>種類ごと</h4><table class='ps-detail'>" +
        "<thead><tr><th>種類</th><th class='num'>件数</th><th class='num'>本数</th>" +
        "<th class='num'>お客様のお支払い</th><th class='num'>バック</th></tr></thead><tbody>";
      sum.forEach(function (r) {
        h += "<tr><td>" + esc(r.category_name) + "</td>" +
          "<td class='num'>" + r.cnt + "</td><td class='num'>" + r.qty + "</td>" +
          "<td class='num'>" + yen(r.amount) + "</td>" +
          "<td class='num'>" + yen(r.back_amount) + "</td></tr>";
      });
      var st = sum.reduce(function (a, r) {
        a.c += r.cnt; a.q += r.qty; a.a += r.amount; a.b += r.back_amount; return a;
      }, { c: 0, q: 0, a: 0, b: 0 });
      h += "<tr class='ps-total'><td>合計</td><td class='num'>" + st.c + "</td>" +
        "<td class='num'>" + st.q + "</td><td class='num'>" + yen(st.a) + "</td>" +
        "<td class='num'>" + yen(st.b) + "</td></tr>";
      h += "</tbody></table>";
    }

    var noms = items.filter(function (i) { return i.category === "nomination"; });
    if (noms.length) {
      h += "<h4 class='ps-sub'>指名の明細</h4><table class='ps-detail'>" +
        "<thead><tr><th>日</th><th>時刻</th><th>卓</th><th>お客様</th><th>内容</th>" +
        "<th class='num'>指名料</th><th class='num'>バック</th></tr></thead><tbody>";
      noms.forEach(function (i) {
        h += "<tr><td>" + String(i.business_date).slice(5).replace("-", "/") + "</td>" +
          "<td>" + esc(i.punched_hm) + "</td><td>" + esc(i.table_no || "") + "</td>" +
          "<td>" + esc(i.customer_name || "") + "</td><td>" + esc(i.name) + "</td>" +
          "<td class='num'>" + yen(i.amount) + "</td>" +
          "<td class='num'>" + yen(i.back_amount) + "</td></tr>";
      });
      var nt = noms.reduce(function (a, i) {
        a.a += i.amount; a.b += i.back_amount; return a;
      }, { a: 0, b: 0 });
      h += "<tr class='ps-total'><td colspan='5'>合計　" + noms.length + "本</td>" +
        "<td class='num'>" + yen(nt.a) + "</td>" +
        "<td class='num'>" + yen(nt.b) + "</td></tr></tbody></table>";
    }
    return h;
  }

  /* 画面で見る内訳 */
  function showDetail(castId, castName, from, to) {
    Promise.all([
      sb.rpc("night_payroll_daily", { p_cast: castId, p_from: from, p_to: to }),
      sb.rpc("night_payroll_item_summary", { p_cast: castId, p_from: from, p_to: to }),
      sb.rpc("night_payroll_items", { p_cast: castId, p_from: from, p_to: to, p_category: null })
    ]).then(function (q) {
      if (q[0].error) { fail(q[0].error); return; }
      var d = {
        subject_name: castName, period_from: from, period_to: to,
        daily: q[0].data || [], summary: q[1].data || [], items: q[2].data || []
      };
      S.detail = d;

      modal(
        "<h2 style='margin-top:0'>" + esc(castName) + " さんの内訳</h2>" +
        "<p style='color:var(--muted);font-size:13px;margin-top:-6px'>" +
        String(from).replace(/-/g, "/") + " 〜 " + String(to).replace(/-/g, "/") + "</p>" +
        "<nav class='tabs' style='margin:0 0 12px'>" +
          "<button data-d='day' aria-selected='true'>日ごと</button>" +
          "<button data-d='sum' aria-selected='false'>種類ごと</button>" +
          "<button data-d='item' aria-selected='false'>1件ずつ</button>" +
        "</nav>" +
        "<div class='row no-print' style='margin-bottom:10px'>" +
          "<label class='field' style='margin:0;min-width:140px'>" +
          "<span style='font-size:12px;color:var(--muted)'>種類でしぼる</span>" +
          "<select id='d_cat'><option value=''>すべて</option></select></label>" +
          "<button class='btn ghost' id='d_csv' style='margin-top:18px'>CSVで保存</button>" +
        "</div>" +
        "<div class='scroll'><table class='list' id='d_table'></table></div>" +
        "<div class='row no-print' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn ghost' id='m_no'>閉じる</button>" +
        "<button class='btn primary' id='m_pr'>この内訳を印刷</button></div>",
        function (root) {
          var view = "day";
          var cats = [];
          d.summary.forEach(function (x) { cats.push(x); });
          root.querySelector("#d_cat").innerHTML =
            "<option value=''>すべて</option>" + cats.map(function (c) {
              return "<option value='" + c.category + "'>" + esc(c.category_name) + "</option>";
            }).join("");

          function draw() {
            root.querySelector("#d_cat").parentNode.style.display =
              view === "item" ? "" : "none";
            root.querySelector("#d_table").innerHTML = detailTable(view,
              root.querySelector("#d_cat").value);
          }
          Array.prototype.forEach.call(root.querySelectorAll("[data-d]"), function (b) {
            b.addEventListener("click", function () {
              view = b.dataset.d;
              Array.prototype.forEach.call(root.querySelectorAll("[data-d]"), function (x) {
                x.setAttribute("aria-selected", String(x.dataset.d === view));
              });
              draw();
            });
          });
          root.querySelector("#d_cat").addEventListener("change", draw);
          root.querySelector("#d_csv").addEventListener("click", function () {
            detailCsv(view, root.querySelector("#d_cat").value, castName);
          });
          root.querySelector("#m_no").addEventListener("click", closeModal);
          root.querySelector("#m_pr").addEventListener("click", function () {
            modal("<div class='payslip'>" + detailHtml(d) + "</div>" +
              "<div class='row no-print' style='justify-content:flex-end;margin-top:16px'>" +
              "<button class='btn ghost' id='m_no'>閉じる</button>" +
              "<button class='btn primary' id='m_ok'>印刷する</button></div>",
              function (r2) {
                r2.querySelector("#m_no").addEventListener("click", closeModal);
                r2.querySelector("#m_ok").addEventListener("click", function () { window.print(); });
              });
          });
          draw();
        });
    });
  }

  function detailRows(view, cat) {
    var d = S.detail || { daily: [], summary: [], items: [] };
    if (view === "day") {
      var day = {
        head: ["日", "曜", "出勤", "退勤", "時間", "遅刻", "時給", "時給ぶん",
               "指名", "同伴", "ドリンク", "売上", "バック", "日払い", "手当", "控除"],
        body: d.daily.map(function (r) {
          return [String(r.business_date), r.weekday, r.clock_in_hm || "", r.clock_out_hm || "",
                  +r.work_hours, r.late_minutes, r.hourly, r.wage_amount,
                  r.nominations, r.douhans, r.drinks, r.sales, r.back_amount,
                  r.payout, r.allowance, r.deduction];
        }),
        money: [7, 11, 12, 13, 14, 15], num: [4, 5, 6, 8, 9, 10],
        noTotal: [6], date: [0]
      };
      if (!S.useNom) {   /* 指名を使わないお店では「指名」の列（8列目）を落とします */
        var drop = function (row) { return row.filter(function (_, i) { return i !== 8; }); };
        day.head = drop(day.head);
        day.body = day.body.map(drop);
        var shift = function (ix) { return ix.filter(function (i) { return i !== 8; }).map(function (i) { return i > 8 ? i - 1 : i; }); };
        day.money = shift(day.money); day.num = shift(day.num);
      }
      return day;
    }
    if (view === "sum") {
      return {
        head: ["種類", "件数", "本数", "お客様のお支払い", "バック"],
        body: d.summary.map(function (r) {
          return [r.category_name, r.cnt, r.qty, r.amount, r.back_amount];
        }),
        money: [3, 4], num: [1, 2], noTotal: [], date: []
      };
    }
    return {
      head: ["日", "時刻", "卓", "お客様", "種類", "内容", "数", "単価", "金額", "バック"],
      body: d.items.filter(function (i) { return !cat || i.category === cat; })
        .map(function (i) {
          return [String(i.business_date), i.punched_hm, i.table_no || "",
                  i.customer_name || "", i.category_name, i.name,
                  i.quantity, i.unit_price, i.amount, i.back_amount];
        }),
      money: [7, 8, 9], num: [6], noTotal: [7], date: [0]
    };
  }

  function detailTable(view, cat) {
    var r = detailRows(view, cat);
    if (!r.body.length) return "";
    var money = {}, num = {}, skip = {}, dt = {};
    r.money.forEach(function (i) { money[i] = 1; });
    r.num.forEach(function (i) { num[i] = 1; });
    (r.noTotal || []).forEach(function (i) { skip[i] = 1; });
    (r.date || []).forEach(function (i) { dt[i] = 1; });
    var md = function (v) { return String(v).slice(5).replace("-", "/"); };

    var h = "<thead><tr>" + r.head.map(function (x, i) {
      return "<th" + (money[i] || num[i] ? " class='num'" : "") + ">" + esc(x) + "</th>";
    }).join("") + "</tr></thead><tbody>";

    r.body.forEach(function (row) {
      h += "<tr>" + row.map(function (v, i) {
        if (money[i]) return "<td class='num'>" + (v ? yen(v) : "") + "</td>";
        if (num[i]) return "<td class='num'>" + (v || "") + "</td>";
        if (dt[i]) return "<td style='white-space:nowrap'>" + esc(md(v)) + "</td>";
        return "<td>" + esc(v) + "</td>";
      }).join("") + "</tr>";
    });

    // 合計行（金額と本数のある列だけ）
    var tot = r.head.map(function (_, i) {
      if ((!money[i] && !num[i]) || skip[i]) return null;
      return r.body.reduce(function (a, row) { return a + (Number(row[i]) || 0); }, 0);
    });
    h += "<tr class='pay-check'><td style='white-space:nowrap'>合計 " +
      r.body.length + "件</td>" +
      tot.slice(1).map(function (v, i) {
        var idx = i + 1;
        if (v == null) return "<td></td>";
        return "<td class='num'><b>" + (money[idx] ? yen(v) : v) + "</b></td>";
      }).join("") + "</tr>";

    return h + "</tbody>";
  }

  function detailCsv(view, cat, castName) {
    var r = detailRows(view, cat);
    var csv = "﻿" + r.head.join(",") + "\n" +
      r.body.map(function (row) {
        return row.map(function (v) {
          var t = String(v == null ? "" : v);
          return /[",\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t;
        }).join(",");
      }).join("\n");
    var a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    a.download = "uchiwake_" + castName + "_" + view + ".csv";
    a.click();
  }

  /* ============================================================ 月別の履歴 */

  $("mo6").addEventListener("click", function () { loadMonthly(6); });
  $("mo12").addEventListener("click", function () { loadMonthly(12); });

  function loadMonthly(n) {
    if (!S.store) return;
    sb.rpc("night_payroll_monthly", { p_store: S.store.id, p_months: n }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      S.months = q.data || [];
      renderMonthly();
      fillMoCast();
    });
  }

  function renderMonthly() {
    var rows = S.months || [];
    var max = Math.max.apply(null, rows.map(function (r) { return r.net_amount || 0; }).concat([1]));

    var bw = 46, gap = 14, h = 150, pad = 26;
    var w = Math.max(rows.length * (bw + gap) + pad, 320);
    var svg = "<svg viewBox='0 0 " + w + " " + (h + 44) + "' width='100%' " +
              "style='max-height:210px' role='img' aria-label='月別の差引支給額'>";
    rows.forEach(function (r, i) {
      var bh = Math.round((r.net_amount || 0) / max * h);
      var x = pad / 2 + i * (bw + gap), y = h - bh + 8;
      svg += "<rect x='" + x + "' y='" + y + "' width='" + bw + "' height='" + Math.max(bh, 2) +
             "' rx='4' fill='var(--gold)' opacity='" + (r.net_amount ? 0.92 : 0.25) + "'>" +
             "<title>" + r.period_ym + "　" + yen(r.net_amount) + "（" + r.people + "名）</title></rect>";
      svg += "<text x='" + (x + bw / 2) + "' y='" + (h + 26) +
             "' text-anchor='middle' font-size='11' fill='var(--muted)'>" +
             r.period_ym.slice(5) + "月</text>";
    });
    svg += "</svg>";
    $("moChart").innerHTML = svg;

    var t = "<thead><tr><th>月</th><th class='num'>人数</th><th class='num'>出勤時間</th>" +
      "<th class='num'>時給ぶん</th><th class='num'>バック</th><th class='num'>手当</th>" +
      "<th class='num'>控除</th><th class='num'>日払い</th><th class='num'>差引支給</th>" +
      "<th class='num'>明細</th></tr></thead><tbody>";
    rows.slice().reverse().forEach(function (r) {
      t += "<tr><td class='mono'>" + r.period_ym + "</td>" +
        "<td class='num'>" + r.people + "</td>" +
        "<td class='num'>" + (+r.work_hours) + "h</td>" +
        "<td class='num'>" + yen(r.wage_amount) + "</td>" +
        "<td class='num'>" + yen(r.back_amount) + "</td>" +
        "<td class='num'>" + yen(r.allowance) + "</td>" +
        "<td class='num'>" + yen(r.deduction) + "</td>" +
        "<td class='num'>" + yen(r.advance) + "</td>" +
        "<td class='num'><b>" + yen(r.net_amount) + "</b></td>" +
        "<td class='num'>" + r.payslips + "</td></tr>";
    });
    $("moTable").innerHTML = t + "</tbody>";
  }

  $("moCsv").addEventListener("click", function () {
    var rows = S.months || [];
    var head = ["月", "人数", "出勤時間", "時給ぶん", "バック", "手当", "控除", "日払い", "差引支給", "明細"];
    var body = rows.map(function (r) {
      return [r.period_ym, r.people, r.work_hours, r.wage_amount, r.back_amount,
              r.allowance, r.deduction, r.advance, r.net_amount, r.payslips].join(",");
    });
    var csv = "﻿" + head.join(",") + "\n" + body.join("\n");
    var a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    a.download = "jinkenhi_" + (S.store ? S.store.name : "store") + ".csv";
    a.click();
  });

  function fillMoCast() {
    var sel = $("moCast");
    if (sel.options.length && sel.value) { loadCastHistory(sel.value); return; }
    sel.innerHTML = S.casts.map(function (c) {
      return "<option value='" + c.id + "'>" + esc(c.name) + "</option>";
    }).join("");
    if (sel.value) loadCastHistory(sel.value);
  }
  $("moCast").addEventListener("change", function () { loadCastHistory(this.value); });

  function loadCastHistory(castId) {
    if (!castId) return;
    sb.rpc("night_payroll_cast_history", { p_cast: castId, p_months: 24 }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var rows = q.data || [];
      if (!rows.length) {
        $("moCastTable").innerHTML = "";
        return;
      }
      var t = "<thead><tr><th>月</th><th>対象期間</th><th class='num'>出勤</th>" +
        (S.useNom ? "<th class='num'>本指名</th>" : "") + "<th class='num'>差引支給</th><th>明細</th></tr></thead><tbody>";
      rows.forEach(function (r) {
        t += "<tr><td class='mono'>" + r.period_ym + "</td>" +
          "<td class='mono' style='font-size:12px'>" +
            r.period_from.slice(5).replace("-", "/") + "〜" +
            r.period_to.slice(5).replace("-", "/") + "</td>" +
          "<td class='num'>" + (+r.work_hours) + "h</td>" +
          (S.useNom ? "<td class='num'>" + r.nominations + "</td>" : "") +
          "<td class='num'><b>" + yen(r.net_amount) + "</b></td>" +
          "<td style='white-space:nowrap'>" + (r.payslip_id
            ? "No." + r.payslip_no +
              (r.sent_method ? "（" + (SLIP_METHOD[r.sent_method] || r.sent_method) + "）" : "") +
              " <button class='btn' data-ph='" + r.payslip_id + "'>印刷</button>"
            : "<span style='color:var(--muted)'>未発行</span>") +
          " <button class='btn ghost' data-du='" + r.period_from + "|" + r.period_to + "'>内訳</button>" +
          "</td></tr>";
      });
      $("moCastTable").innerHTML = t + "</tbody>";
      Array.prototype.forEach.call($("moCastTable").querySelectorAll("[data-ph]"), function (b) {
        b.addEventListener("click", function () { printSlip(b.dataset.ph); });
      });
      Array.prototype.forEach.call($("moCastTable").querySelectorAll("[data-du]"), function (b) {
        b.addEventListener("click", function () {
          var p = b.dataset.du.split("|");
          var sel = $("moCast");
          showDetail(sel.value, sel.options[sel.selectedIndex].text, p[0], p[1]);
        });
      });
    });
  }

  /* -------------------------------------------------------------- 起動 */

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  boot();
})();
