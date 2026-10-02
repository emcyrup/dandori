/* ============================================================================
   だんどりシリーズ / ナイトだんどり お客様
   customers.js
   置き場所： サイトのルート（customers.html と同じ階層）
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  var S = { me: null, stores: [], store: null, casts: [], customers: [], due: [], bottles: [] };

  var $ = function (id) { return document.getElementById(id); };
  var yen = function (n) { return "¥" + (n || 0).toLocaleString("ja-JP"); };
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }
  function fail(e) {
    var m = (e && (e.message || e.details)) || String(e);
    toast(m.replace(/^.*?:\s*/, ""), "err"); console.error(e);
  }
  function modal(html, onReady) {
    var root = $("modalRoot");
    root.innerHTML = '<div class="modal"><div class="box">' + html + "</div></div>";
    var w = root.querySelector(".modal");
    w.addEventListener("click", function (e) { if (e.target === w) closeModal(); });
    if (onReady) onReady(root);
  }
  function closeModal() { $("modalRoot").innerHTML = ""; }
  function ymd(d) { return d.toISOString().slice(0, 10); }
  var PREF = { line: "LINE", tel: "電話", none: "連絡しない" };
  var KIND = { line: "LINE", tel: "電話", mail: "メール", visit: "来店時", other: "その他" };
  var RES = { sent: "送った", replied: "返信あり", booked: "予約になった",
              declined: "断られた", no_answer: "反応なし" };

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
    if (S.store.ui_theme) { if (window.DANDORI_UI) window.DANDORI_UI.theme(S.store.ui_theme); else document.body.className = "theme-" + S.store.ui_theme; }
    sb.from("night_cast").select("id,name").eq("store_id", id).eq("is_active", true).order("name")
      .then(function (q) {
        S.casts = q.data || [];
        return sb.from("night_customer").select("id,name,visit_count,main_cast_id,company,last_visit_on,contact_pref,likes,is_blocked,line_ok,birthday,kana,tel,dislikes,note")
          .eq("store_id", id).order("name")
          .then(function (q2) { S.customers = q2.data || []; switchView("due"); });
      });
  }

  /* -------------------------------------------------------------- 画面切替 */

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });
  function switchView(v) {
    ["due", "list", "bday", "bottle"].forEach(function (n) {
      $("view-" + n).classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (v === "due") loadDue();
    if (v === "list") loadList();
    if (v === "bday") loadBday();
    if (v === "bottle") loadBottles();
  }

  /* -------------------------------------------------------------- そろそろの方 */

  $("dueGo").addEventListener("click", loadDue);
  $("dueRate").addEventListener("change", loadDue);

  function loadDue() {
    sb.rpc("night_customer_due", {
      p_store: S.store.id,
      p_over_rate: Number($("dueRate").value),
      p_first_days: 45, p_limit: 60
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      S.due = q.data || [];
      $("dueEmpty").classList.toggle("hidden", S.due.length > 0);
      $("dueTable").innerHTML = S.due.length ?
        "<tr><th>お客様</th><th>担当</th><th class='num'>来店</th><th class='num'>最終来店</th>" +
        "<th class='num'>いつもの間隔</th><th class='num'>過ぎた日数</th><th class='num'>1回あたり</th>" +
        "<th>前回の連絡</th><th></th></tr>" +
        S.due.map(function (r) {
          var cls = r.over_days >= 30 ? "cold" : "over";
          return '<tr class="due"><td>' + esc(r.name) +
            "<br><span class='note'>" + PREF[r.contact_pref] +
              (r.line_ok ? "" : "／LINE不可") + "</span></td>" +
            "<td>" + esc(r.main_cast || "—") + "</td>" +
            "<td class='num'>" + r.visits + " 回</td>" +
            "<td class='num'>" + r.last_visit + "<br><span class='note'>" + r.days_since + "日前</span></td>" +
            "<td class='num'>" + (r.avg_interval ? r.avg_interval + "日" : "—") + "</td>" +
            "<td class='num'><span class='" + cls + "'>+" + r.over_days + "日</span></td>" +
            "<td class='num'>" + yen(r.per_visit) + "</td>" +
            "<td>" + (r.last_contact_on || "<span class='note'>なし</span>") + "</td>" +
            '<td><button class="btn ghost" style="padding:6px 12px" data-ct="' + r.customer_id +
              '">連絡を記録</button></td></tr>';
        }).join("") : "";

      Array.prototype.forEach.call($("dueTable").querySelectorAll("button[data-ct]"), function (b) {
        b.addEventListener("click", function () { contactDialog(b.dataset.ct); });
      });
    });
  }

  $("dueCsv").addEventListener("click", function () {
    if (!S.due.length) { toast("出すものがありません", "err"); return; }
    var head = ["お名前", "担当", "来店回数", "最終来店", "いつもの間隔", "過ぎた日数",
                "1回あたり", "累計", "連絡手段", "前回の連絡"];
    var lines = [head.join(",")].concat(S.due.map(function (r) {
      return ['"' + r.name + '"', '"' + (r.main_cast || "") + '"', r.visits, r.last_visit,
              r.avg_interval, r.over_days, r.per_visit, r.total_sales,
              PREF[r.contact_pref], r.last_contact_on || ""].join(",");
    }));
    var blob = new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "そろそろの方_" + S.store.name + "_" + ymd(new Date()) + ".csv";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  });

  function contactDialog(id) {
    var c = (S.due.filter(function (x) { return x.customer_id === id; })[0]) ||
            (S.customers.filter(function (x) { return x.id === id; })[0]) || {};
    modal("<h2>連絡の記録　" + esc(c.name || "") + "</h2>" +
      '<div class="field"><label for="k_kind">方法</label><select id="k_kind">' +
        Object.keys(KIND).map(function (k) {
          return '<option value="' + k + '"' +
            (c.contact_pref === k ? " selected" : "") + ">" + KIND[k] + "</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="k_res">結果</label><select id="k_res">' +
        Object.keys(RES).map(function (k) {
          return '<option value="' + k + '">' + RES[k] + "</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="k_cast">担当キャスト</label><select id="k_cast">' +
        '<option value="">（なし）</option>' +
        S.casts.map(function (x) { return '<option value="' + x.id + '">' + esc(x.name) + "</option>"; }).join("") +
      "</select></div>" +
      '<div class="field"><label for="k_memo">メモ</label><input id="k_memo" placeholder="来週来られるとのこと"></div>' +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_contact_add", {
            p_customer: id,
            p_kind: root.querySelector("#k_kind").value,
            p_result: root.querySelector("#k_res").value,
            p_memo: root.querySelector("#k_memo").value.trim() || null,
            p_cast: root.querySelector("#k_cast").value || null,
            p_on: ymd(new Date())
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("記録しました", "ok"); loadDue();
          });
        });
      });
  }

  /* -------------------------------------------------------------- 台帳 */

  $("q").addEventListener("input", renderList);
  $("custAdd").addEventListener("click", function () { custDialog(null); });

  function loadList() {
    sb.from("night_customer").select("*").eq("store_id", S.store.id)
      .order("last_visit_on", { ascending: false, nullsFirst: false })
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        S.customers = q.data || [];
        renderList();
      });
  }

  function castName(id) {
    var c = S.casts.filter(function (x) { return x.id === id; })[0];
    return c ? c.name : "";
  }

  function renderList() {
    var kw = $("q").value.trim();
    var rows = !kw ? S.customers : S.customers.filter(function (c) {
      return (c.name || "").indexOf(kw) >= 0 || (c.company || "").indexOf(kw) >= 0 ||
             (c.kana || "").indexOf(kw) >= 0;
    });
    $("custTable").innerHTML =
      "<tr><th>お客様</th><th>担当</th><th class='num'>来店</th><th class='num'>最終来店</th>" +
      "<th>連絡</th><th>お好み</th><th></th></tr>" +
      (rows.length ? rows.map(function (c) {
        return "<tr" + (c.is_blocked ? " style='opacity:.5'" : "") + "><td>" + esc(c.name) +
          (c.is_blocked ? ' <span class="tag open">お断り</span>' : "") +
          (c.company ? "<br><span class='note'>" + esc(c.company) + "</span>" : "") + "</td>" +
          "<td>" + esc(castName(c.main_cast_id) || "—") + "</td>" +
          "<td class='num'>" + (c.visit_count || 0) + " 回</td>" +
          "<td class='num'>" + (c.last_visit_on || "—") + "</td>" +
          "<td>" + PREF[c.contact_pref || "line"] + "</td>" +
          "<td class='note'>" + esc(c.likes || "—") + "</td>" +
          '<td><button class="btn ghost" style="padding:6px 12px" data-det="' + c.id + '">詳細</button></td></tr>';
      }).join("") : "<tr><td colspan='7' class='note' style='padding:18px 0'>該当する方がいません。</td></tr>");

    Array.prototype.forEach.call($("custTable").querySelectorAll("button[data-det]"), function (b) {
      b.addEventListener("click", function () { detailDialog(b.dataset.det); });
    });
  }

  function detailDialog(id) {
    var c = S.customers.filter(function (x) { return x.id === id; })[0];
    if (!c) return;
    Promise.all([
      sb.rpc("night_customer_history", { p_customer: id, p_limit: 12 }),
      sb.from("night_contact_log").select("*").eq("customer_id", id)
        .order("contacted_on", { ascending: false }).limit(10)
    ]).then(function (r) {
      var hist = r[0].data || [], logs = r[1].data || [];
      var total = hist.reduce(function (a, x) { return a + (x.total || 0); }, 0);

      modal("<h2>" + esc(c.name) + "</h2>" +
        "<p class='note' style='margin:-8px 0 12px'>" +
          (c.company ? esc(c.company) + "　" : "") +
          "担当：" + esc(castName(c.main_cast_id) || "なし") +
          "　" + PREF[c.contact_pref || "line"] + "</p>" +
        (c.likes ? "<div class='pay-check ok' style='font-size:13px'>お好み：" + esc(c.likes) + "</div>" : "") +
        (c.dislikes ? "<div class='pay-check ng' style='font-size:13px'>避ける：" + esc(c.dislikes) + "</div>" : "") +
        '<div class="totals" style="margin-top:12px">' +
          "<div><span>来店</span><span class='mono'>" + (c.visit_count || 0) + " 回</span></div>" +
          "<div><span>最終来店</span><span class='mono'>" + (c.last_visit_on || "—") + "</span></div>" +
          (c.birthday ? "<div><span>お誕生日</span><span class='mono'>" + c.birthday + "</span></div>" : "") +
          "<div><span>直近" + hist.length + "回の合計</span><span class='mono'>" + yen(total) + "</span></div>" +
        "</div>" +
        "<h2 style='margin-top:18px'>来店の履歴</h2><div class='hist'><table class='list'>" +
        (hist.length ? hist.map(function (h) {
          return "<tr><td>" + h.business_date + "</td><td>" + esc(h.main_cast || "—") + "</td>" +
            "<td class='num'>" + h.head_count + "名</td>" +
            "<td class='num'>" + yen(h.total) + "</td></tr>";
        }).join("") : "<tr><td class='note'>まだありません。</td></tr>") + "</table></div>" +
        "<h2 style='margin-top:18px'>連絡の履歴</h2><div class='hist'><table class='list'>" +
        (logs.length ? logs.map(function (l) {
          return "<tr><td>" + l.contacted_on + "</td><td>" + (KIND[l.kind] || l.kind) + "</td>" +
            "<td>" + (RES[l.result] || l.result) + "</td>" +
            "<td class='note'>" + esc(l.memo || "") + "</td></tr>";
        }).join("") : "<tr><td class='note'>まだありません。</td></tr>") + "</table></div>" +
        '<div class="row" style="margin-top:16px">' +
          '<button class="btn ghost" id="m_contact">連絡を記録</button>' +
          '<button class="btn ghost" id="m_edit">編集</button>' +
          '<button class="btn primary" id="m_close" style="flex:1">閉じる</button></div>',
        function (root) {
          root.querySelector("#m_close").addEventListener("click", closeModal);
          root.querySelector("#m_contact").addEventListener("click", function () { contactDialog(id); });
          root.querySelector("#m_edit").addEventListener("click", function () { custDialog(id); });
        });
    });
  }

  function custDialog(id) {
    var c = id ? S.customers.filter(function (x) { return x.id === id; })[0] : null;
    var v = function (k) { return esc(c && c[k] != null ? c[k] : ""); };

    modal("<h2>" + (c ? "お客様の編集" : "お客様を追加") + "</h2>" +
      '<div class="field"><label for="u_name">お名前（呼称）</label>' +
        '<input id="u_name" value="' + esc(c ? c.name : "") + '" placeholder="佐藤様"></div>' +
      '<div class="field"><label for="u_kana">ふりがな</label><input id="u_kana" value="' + v("kana") + '"></div>' +
      '<div class="field"><label for="u_comp">会社名</label><input id="u_comp" value="' + v("company") + '"></div>' +
      '<div class="field"><label for="u_tel">電話番号</label><input id="u_tel" value="' + v("tel") + '"></div>' +
      '<div class="field"><label for="u_bd">お誕生日</label>' +
        '<input id="u_bd" type="date" value="' + v("birthday") + '"></div>' +
      '<div class="field"><label for="u_cast">担当キャスト</label><select id="u_cast">' +
        '<option value="">（なし）</option>' +
        S.casts.map(function (x) {
          return '<option value="' + x.id + '"' +
            (c && c.main_cast_id === x.id ? " selected" : "") + ">" + esc(x.name) + "</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="u_likes">お好み（お酒・話題）</label>' +
        '<input id="u_likes" value="' + v("likes") + '" placeholder="芋焼酎／野球の話"></div>' +
      '<div class="field"><label for="u_dis">避けたい話題</label>' +
        '<input id="u_dis" value="' + v("dislikes") + '"></div>' +
      '<div class="field"><label for="u_pref">ご連絡の手段</label><select id="u_pref">' +
        Object.keys(PREF).map(function (k) {
          return '<option value="' + k + '"' +
            (c && c.contact_pref === k ? " selected" : "") + ">" + PREF[k] + "</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="u_line">LINEでのご案内</label><select id="u_line">' +
        '<option value="1"' + (!c || c.line_ok ? " selected" : "") + ">同意いただいている</option>" +
        '<option value="0"' + (c && !c.line_ok ? " selected" : "") + ">送らない</option></select></div>" +
      '<div class="field"><label for="u_note">メモ</label><input id="u_note" value="' + v("note") + '"></div>' +
      (c ? '<div class="field"><label for="u_block">お断り</label><select id="u_block">' +
        '<option value="0"' + (!c.is_blocked ? " selected" : "") + ">通常</option>" +
        '<option value="1"' + (c.is_blocked ? " selected" : "") + ">お断りリストに入れる</option></select></div>" : "") +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var g = function (id2) {
            var val = root.querySelector("#" + id2).value.trim();
            return val === "" ? null : val;
          };
          var payload = {
            tenant_id: S.me.tenant_id, store_id: S.store.id,
            name: root.querySelector("#u_name").value.trim(),
            kana: g("u_kana"), company: g("u_comp"), tel: g("u_tel"),
            birthday: g("u_bd"), main_cast_id: g("u_cast"),
            likes: g("u_likes"), dislikes: g("u_dis"),
            contact_pref: root.querySelector("#u_pref").value,
            line_ok: root.querySelector("#u_line").value === "1",
            note: g("u_note")
          };
          if (!payload.name) { toast("お名前を入れてください", "err"); return; }
          var bl = root.querySelector("#u_block");
          if (bl) payload.is_blocked = bl.value === "1";

          var q = c ? sb.from("night_customer").update(payload).eq("id", c.id)
                    : sb.from("night_customer").insert(payload);
          q.then(function (res) {
            if (res.error) { fail(res.error); return; }
            closeModal(); toast("保存しました", "ok"); loadList();
          });
        });
      });
  }

  /* -------------------------------------------------------------- 誕生日 */

  function loadBday() {
    sb.rpc("night_customer_birthday", { p_store: S.store.id, p_days: 60 }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var rows = q.data || [];
      $("bdayEmpty").classList.toggle("hidden", rows.length > 0);
      $("bdayTable").innerHTML = rows.length ?
        "<tr><th>お客様</th><th>担当</th><th class='num'>お誕生日</th><th class='num'>あと</th>" +
        "<th class='num'>来店</th><th class='num'>最終来店</th><th></th></tr>" +
        rows.map(function (r) {
          var soon = r.days_until <= 14;
          return "<tr><td>" + esc(r.name) + "</td>" +
            "<td>" + esc(r.main_cast || "—") + "</td>" +
            "<td class='num'>" + r.birthday.slice(5).replace("-", "/") + "</td>" +
            "<td class='num'" + (soon ? " style='color:var(--gold);font-weight:700'" : "") + ">" +
              r.days_until + "日</td>" +
            "<td class='num'>" + (r.visits || 0) + " 回</td>" +
            "<td class='num'>" + (r.last_visit || "—") + "</td>" +
            '<td><button class="btn ghost" style="padding:6px 12px" data-ct2="' + r.customer_id +
              '">連絡を記録</button></td></tr>';
        }).join("") : "";

      Array.prototype.forEach.call($("bdayTable").querySelectorAll("button[data-ct2]"), function (b) {
        b.addEventListener("click", function () { contactDialog(b.dataset.ct2); });
      });
    });
  }


  /* -------------------------------------------------------------- ボトル */

  var BST = { keeping: "キープ中", consumed: "飲み切り", expired: "期限切れ", disposed: "廃棄" };

  $("btlFilter").addEventListener("change", loadBottles);
  $("btlAdd").addEventListener("click", function () { bottleDialog(null); });
  $("btlExpire").addEventListener("click", function () {
    sb.rpc("night_bottle_mark_expired", { p_store: S.store.id }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      toast(q.data > 0 ? q.data + "本を期限切れにしました" : "期限切れのボトルはありません",
            q.data > 0 ? "ok" : "err");
      loadBottles();
    });
  });

  function loadBottles() {
    Promise.all([
      sb.rpc("night_bottle_list", { p_store: S.store.id, p_status: $("btlFilter").value, p_customer: null }),
      sb.rpc("night_bottle_summary", { p_store: S.store.id, p_date: null, p_soon_days: 30 })
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      S.bottles = r[0].data || [];
      var sm = (r[1].data && r[1].data[0]) || {};

      $("btlTiles").innerHTML = [
        { lb: "キープ中", v: (sm.keeping || 0) + " 本" },
        { lb: "期限が近い（30日以内）", v: (sm.expiring || 0) + " 本", warn: sm.expiring > 0 },
        { lb: "期限切れ", v: (sm.expired || 0) + " 本", bad: sm.expired > 0 },
        { lb: "今日入れた", v: (sm.kept_today || 0) + " 本" },
        { lb: "今日出した", v: (sm.served_today || 0) + " 本" }
      ].map(function (t) {
        return '<div style="background:var(--panel);border:1px solid var(--line);' +
          'border-radius:10px;padding:13px 15px">' +
          '<div style="font-size:12px;color:var(--muted)">' + t.lb + "</div>" +
          '<div style="font-size:21px;font-weight:700;margin-top:2px;color:' +
            (t.bad ? "var(--bad)" : t.warn ? "var(--warn)" : "var(--ink)") + '">' + t.v + "</div></div>";
      }).join("");

      $("btlEmpty").classList.toggle("hidden", S.bottles.length > 0);
      $("btlTable").innerHTML = S.bottles.length ?
        "<tr><th>お客様</th><th>銘柄</th><th>棚番</th><th class='num'>残量</th>" +
        "<th class='num'>入れた日</th><th class='num'>期限</th><th>状態</th><th></th></tr>" +
        S.bottles.map(function (b) {
          var left = b.days_left;
          var expCls = left == null ? "" :
            (left < 0 ? " style='color:var(--bad);font-weight:700'"
                      : (left <= 30 ? " style='color:var(--warn);font-weight:700'" : ""));
          return "<tr" + (b.status === "keeping" ? "" : " style='opacity:.55'") + ">" +
            "<td>" + esc(b.who) + (b.cast_name ? "<br><span class='note'>担当 " +
              esc(b.cast_name) + "</span>" : "") + "</td>" +
            "<td>" + esc(b.name) + (b.kind ? "<br><span class='note'>" + esc(b.kind) + "</span>" : "") + "</td>" +
            "<td>" + esc(b.location || "—") + "</td>" +
            "<td class='num'>" + bar(b.remaining) + "</td>" +
            "<td class='num'>" + b.opened_on + "</td>" +
            "<td class='num'" + expCls + ">" + (b.expires_on || "なし") +
              (left != null ? "<br><span class='note'>" +
                (left < 0 ? Math.abs(left) + "日超過" : "あと" + left + "日") + "</span>" : "") + "</td>" +
            "<td>" + (BST[b.status] || b.status) + "</td>" +
            "<td>" + (b.status === "keeping"
              ? '<button class="btn ghost" style="padding:6px 10px" data-srv="' + b.id + '">出す</button> ' +
                '<button class="btn ghost" style="padding:6px 10px" data-btl="' + b.id + '">詳細</button>'
              : '<button class="btn ghost" style="padding:6px 10px" data-btl="' + b.id + '">詳細</button>') +
            "</td></tr>";
        }).join("") : "";

      Array.prototype.forEach.call($("btlTable").querySelectorAll("button[data-srv]"), function (x) {
        x.addEventListener("click", function () { serveDialog(x.dataset.srv); });
      });
      Array.prototype.forEach.call($("btlTable").querySelectorAll("button[data-btl]"), function (x) {
        x.addEventListener("click", function () { bottleDialog(x.dataset.btl); });
      });
    });
  }

  function bar(r) {
    var color = r <= 25 ? "var(--bad)" : (r <= 50 ? "var(--warn)" : "var(--gold)");
    return '<span style="display:inline-flex;align-items:center;gap:7px">' +
      '<span style="display:block;width:52px;height:10px;background:var(--panel2);' +
      'border-radius:3px;overflow:hidden"><span style="display:block;height:100%;width:' +
      r + '%;background:' + color + '"></span></span>' + r + "%</span>";
  }

  function serveDialog(id) {
    var b = S.bottles.filter(function (x) { return x.id === id; })[0] || {};
    var opts = [100, 75, 50, 25, 0].filter(function (v) { return v <= (b.remaining || 100); });
    modal("<h2>ボトルを出す</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin:-8px 0 14px'>" +
        esc(b.who) + "　" + esc(b.name) + "（棚番 " + esc(b.location || "—") + "）<br>" +
        "いまの残量は " + b.remaining + "% です。</p>" +
      '<div class="field"><label for="s_rem">出したあとの残量</label><select id="s_rem">' +
        opts.map(function (v) {
          return '<option value="' + v + '">' + v + "%" +
            (v === 0 ? "（飲み切り）" : "") + "</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="s_memo">メモ</label><input id="s_memo"></div>' +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_bottle_serve", {
            p_bottle: id,
            p_remaining: Number(root.querySelector("#s_rem").value),
            p_visit: null,
            p_memo: root.querySelector("#s_memo").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("記録しました", "ok"); loadBottles();
          });
        });
      });
  }

  function bottleDialog(id) {
    var b = id ? S.bottles.filter(function (x) { return x.id === id; })[0] : null;

    modal("<h2>" + (b ? "ボトルの詳細" : "ボトルを登録") + "</h2>" +
      (b ? "" :
        '<div class="field"><label for="b_cust">お客様</label><select id="b_cust">' +
          '<option value="">（台帳にない方）</option>' +
          S.customers.map(function (c) {
            return '<option value="' + c.id + '">' + esc(c.name) + "</option>";
          }).join("") + "</select></div>" +
        '<div class="field"><label for="b_guest">お名前（台帳にない方）</label><input id="b_guest"></div>') +
      '<div class="field"><label for="b_name">銘柄</label>' +
        '<input id="b_name" value="' + esc(b ? b.name : "") + '" placeholder="黒霧島（一升）"></div>' +
      '<div class="field"><label for="b_kind">種類</label>' +
        '<input id="b_kind" value="' + esc(b && b.kind ? b.kind : "") + '" placeholder="焼酎"></div>' +
      '<div class="field"><label for="b_loc">棚番</label>' +
        '<input id="b_loc" value="' + esc(b && b.location ? b.location : "") + '" placeholder="A-12"></div>' +
      (b ? '<div class="field"><label for="b_rem">残量（%）</label>' +
            '<input id="b_rem" type="number" min="0" max="100" value="' + b.remaining + '"></div>' +
           '<div class="field"><label for="b_exp">期限</label>' +
            '<input id="b_exp" type="date" value="' + (b.expires_on || "") + '"></div>'
         : '<div class="field"><label for="b_cast">担当キャスト</label><select id="b_cast">' +
             '<option value="">（なし）</option>' +
             S.casts.map(function (c) {
               return '<option value="' + c.id + '">' + esc(c.name) + "</option>";
             }).join("") + "</select></div>" +
           '<div class="field"><label for="b_months">キープ期間（か月）</label>' +
             '<input id="b_months" type="number" min="0" value="6">' +
             '<span style="font-size:12px;color:var(--muted)">0にすると期限なし</span></div>') +
      '<div class="field"><label for="b_note">メモ</label>' +
        '<input id="b_note" value="' + esc(b && b.note ? b.note : "") + '"></div>' +
      '<div class="row" style="margin-top:16px">' +
        (b && b.status === "keeping" ?
          '<button class="btn ghost" id="m_ext">期限を3か月延ばす</button>' +
          '<button class="btn danger" id="m_dis">廃棄</button>' : "") +
        '<button class="btn ghost" id="m_cancel">やめる</button>' +
        '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);

        var ext = root.querySelector("#m_ext");
        if (ext) ext.addEventListener("click", function () {
          sb.rpc("night_bottle_extend", { p_bottle: id, p_months: 3, p_memo: null })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal(); toast("期限を3か月延ばしました", "ok"); loadBottles();
            });
        });

        var dis = root.querySelector("#m_dis");
        if (dis) dis.addEventListener("click", function () {
          sb.rpc("night_bottle_status", { p_bottle: id, p_status: "disposed", p_memo: null })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal(); toast("廃棄にしました", "ok"); loadBottles();
            });
        });

        root.querySelector("#m_ok").addEventListener("click", function () {
          var g = function (k) {
            var el = root.querySelector("#" + k);
            if (!el) return null;
            var v = el.value.trim();
            return v === "" ? null : v;
          };
          if (b) {
            sb.rpc("night_bottle_edit", {
              p_bottle: id, p_name: g("b_name"), p_kind: g("b_kind"),
              p_location: g("b_loc"),
              p_remaining: Number(root.querySelector("#b_rem").value),
              p_expires: g("b_exp"), p_note: g("b_note")
            }).then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal(); toast("保存しました", "ok"); loadBottles();
            });
          } else {
            if (!g("b_name")) { toast("銘柄を入れてください", "err"); return; }
            sb.rpc("night_bottle_keep", {
              p_store: S.store.id, p_name: g("b_name"),
              p_customer: g("b_cust"), p_guest: g("b_guest"),
              p_kind: g("b_kind"), p_location: g("b_loc"),
              p_cast: g("b_cast"), p_visit: null,
              p_months: Number(root.querySelector("#b_months").value),
              p_note: g("b_note")
            }).then(function (q) {
              if (q.error) { fail(q.error); return; }
              closeModal(); toast("登録しました", "ok"); loadBottles();
            });
          }
        });
      });
  }

  /* -------------------------------------------------------------- 起動 */

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  boot();
})();
