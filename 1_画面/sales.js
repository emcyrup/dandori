/* ============================================================================
   だんどりシリーズ / ナイトだんどり 売上
   sales.js
   置き場所： サイトのルート（sales.html と同じ階層）

   集計はすべてデータベース側（008_sales.sql）で行います。
   この画面は数字を受け取って並べるだけです。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  var S = { me: null, stores: [], store: null, daily: [], from: null, to: null };

  var $ = function (id) { return document.getElementById(id); };
  var yen = function (n) { return "¥" + (n || 0).toLocaleString("ja-JP"); };
  var man = function (n) {
    if (!n) return "0";
    return n >= 10000 ? (n / 10000).toFixed(n >= 100000 ? 0 : 1) + "万" : String(n);
  };
  function ymd(d) { return d.toISOString().slice(0, 10); }
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
    toast(m.replace(/^.*?:\s*/, ""), "err");
    console.error(e);
  }
  var WD = ["日", "月", "火", "水", "木", "金", "土"];
  function mdw(iso) {
    var d = new Date(iso + "T00:00:00");
    return (d.getMonth() + 1) + "/" + d.getDate() + "（" + WD[d.getDay()] + "）";
  }

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
    loadToday();
    setRange(7);
  }

  /* -------------------------------------------------------------- 今日 */

  function loadToday() {
    sb.rpc("night_sales_today", { p_store: S.store.id }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var t = (q.data && q.data[0]) || {};
      $("todayDate").textContent = t.business_date ? mdw(t.business_date) + " 営業ぶん" : "";

      var tiles = [
        { lb: "売上（締め済み）", v: yen(t.closed_sales), sub: t.closed_visits + "組　" + t.closed_guests + "名",
          lead: true },
        { lb: "開いている卓", v: t.open_visits ? yen(t.open_estimate) : "—",
          sub: t.open_visits ? t.open_visits + "組が進行中" : "なし" },
        { lb: "今夜の見込み", v: yen(t.total_estimate), sub: "締め済み＋進行中" },
        { lb: "客単価", v: yen(t.per_guest), sub: "締め済みぶん" },
        { lb: "現金", v: yen(t.cash), sub: "" },
        { lb: "カード", v: yen(t.card), sub: "" },
        { lb: "売掛", v: yen(t.credit), sub: t.credit ? "回収待ち" : "" }
      ];
      $("todayTiles").innerHTML = tiles.map(function (x) {
        return '<div class="tile' + (x.lead ? " lead" : "") + '">' +
          '<div class="lb">' + x.lb + "</div><div class='v'>" + x.v + "</div>" +
          (x.sub ? '<div class="sub">' + x.sub + "</div>" : "") + "</div>";
      }).join("");
    });
  }

  /* -------------------------------------------------------------- 期間 */

  Array.prototype.forEach.call(document.querySelectorAll("button[data-range]"), function (b) {
    b.addEventListener("click", function () { setRange(b.dataset.range); });
  });
  $("rGo").addEventListener("click", function () {
    if (!$("rFrom").value || !$("rTo").value) { toast("期間を選んでください", "err"); return; }
    load($("rFrom").value, $("rTo").value);
  });

  function setRange(kind) {
    var t = new Date(), f, to = t;
    if (kind === "month") {
      f = new Date(t.getFullYear(), t.getMonth(), 1);
    } else if (kind === "lastmonth") {
      f = new Date(t.getFullYear(), t.getMonth() - 1, 1);
      to = new Date(t.getFullYear(), t.getMonth(), 0);
    } else {
      f = new Date(t); f.setDate(f.getDate() - (Number(kind) - 1));
    }
    $("rFrom").value = ymd(f);
    $("rTo").value = ymd(to);
    load(ymd(f), ymd(to));
  }

  function load(from, to) {
    S.from = from; S.to = to;
    Promise.all([
      sb.rpc("night_sales_daily", { p_store: S.store.id, p_from: from, p_to: to }),
      sb.rpc("night_sales_category", { p_store: S.store.id, p_from: from, p_to: to }),
      sb.rpc("night_sales_cast", { p_store: S.store.id, p_from: from, p_to: to }),
      sb.rpc("night_sales_customer", { p_store: S.store.id, p_from: from, p_to: to, p_limit: 10 })
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      S.daily = r[0].data || [];
      renderRangeTiles();
      drawDaily();
      drawBars("catBars", (r[1].data || []).map(function (x) {
        return { name: x.label, value: x.amount, note: x.qty + "点　" + x.share + "%" };
      }));
      drawBars("castBars", (r[2].data || []).map(function (x) {
        return { name: x.cast_name, value: x.sales,
                 note: "指名" + x.nominations + "　出勤" + x.work_days + "日" };
      }));
      renderCustomers(r[3].data || []);
      renderDailyTable();
    });
  }

  function sum(k) { return S.daily.reduce(function (a, x) { return a + (x[k] || 0); }, 0); }

  function renderRangeTiles() {
    var days = S.daily.filter(function (d) { return d.visits > 0; }).length;
    var sales = sum("sales"), guests = sum("guests"), visits = sum("visits");
    var best = S.daily.slice().sort(function (a, b) { return b.sales - a.sales; })[0];

    $("rangeTiles").innerHTML = [
      { lb: "売上合計", v: yen(sales), sub: days + "営業日", lead: true },
      { lb: "1日あたり", v: yen(days ? Math.round(sales / days) : 0), sub: "営業した日の平均" },
      { lb: "組数", v: visits.toLocaleString("ja-JP") + " 組", sub: guests + "名" },
      { lb: "客単価", v: yen(guests ? Math.round(sales / guests) : 0), sub: "" },
      { lb: "現金 / カード / 売掛", v: yen(sum("cash")),
        sub: "カード " + yen(sum("card")) + "　売掛 " + yen(sum("credit")) },
      { lb: "いちばん売れた日", v: best && best.sales ? yen(best.sales) : "—",
        sub: best && best.sales ? mdw(best.business_date) : "" }
    ].map(function (x) {
      return '<div class="tile' + (x.lead ? " lead" : "") + '">' +
        '<div class="lb">' + x.lb + "</div><div class='v'>" + x.v + "</div>" +
        (x.sub ? '<div class="sub">' + x.sub + "</div>" : "") + "</div>";
    }).join("");
  }

  /* -------------------------------------------------------------- 日別グラフ */

  function drawDaily() {
    var box = $("dailyChart");
    var data = S.daily;
    if (!data.length) { box.innerHTML = '<div class="empty">この期間に売上がありません。</div>'; return; }

    var W = 900, H = 240, padL = 52, padR = 12, padT = 14, padB = 30;
    var iw = W - padL - padR, ih = H - padT - padB;
    var max = Math.max.apply(null, data.map(function (d) { return d.sales; })) || 1;
    // 目盛りは上限を切りのいい数に
    var step = Math.pow(10, String(Math.round(max)).length - 1);
    var top = Math.ceil(max / step) * step;
    var bw = Math.max(Math.min(iw / data.length - 6, 46), 4);

    var grid = [0, 0.5, 1].map(function (p) {
      var y = padT + ih - ih * p;
      return '<line class="gl" x1="' + padL + '" y1="' + y + '" x2="' + (W - padR) + '" y2="' + y + '"></line>' +
             '<text class="gtxt" x="' + (padL - 8) + '" y="' + (y + 4) + '" text-anchor="end">' +
             (p ? man(Math.round(top * p)) : "0") + "</text>";
    }).join("");

    var bars = data.map(function (d, i) {
      var x = padL + (iw / data.length) * i + (iw / data.length - bw) / 2;
      var h = d.sales ? Math.max(ih * (d.sales / top), 3) : 0;
      var y = padT + ih - h;
      return '<rect class="bar' + (d.sales ? "" : " dim") + '" x="' + x.toFixed(1) + '" y="' + y.toFixed(1) +
        '" width="' + bw.toFixed(1) + '" height="' + (h || 2).toFixed(1) + '" rx="3"' +
        ' data-i="' + i + '"></rect>';
    }).join("");

    // 日付ラベルは詰まらないよう間引く
    var everyN = Math.ceil(data.length / 12);
    var labels = data.map(function (d, i) {
      if (i % everyN !== 0 && i !== data.length - 1) return "";
      var x = padL + (iw / data.length) * i + (iw / data.length) / 2;
      var t = d.business_date.slice(5).replace("-", "/");
      return '<text class="gtxt" x="' + x.toFixed(1) + '" y="' + (H - 10) +
        '" text-anchor="middle">' + t + "</text>";
    }).join("");

    box.innerHTML =
      '<svg viewBox="0 0 ' + W + " " + H + '" role="img" aria-label="日別の売上">' +
      grid + bars + labels + "</svg>" +
      '<div class="tip" id="tip"></div>';

    var tip = $("tip");
    box.querySelectorAll("rect.bar").forEach(function (rect) {
      rect.addEventListener("mouseenter", function () {
        var d = data[Number(rect.dataset.i)];
        tip.innerHTML = mdw(d.business_date) + "<b>" + yen(d.sales) + "</b>" +
          (d.visits ? d.visits + "組　" + d.guests + "名　客単価 " + yen(d.per_guest)
                    : "営業なし");
        var r = rect.getBoundingClientRect(), b = box.getBoundingClientRect();
        tip.style.left = (r.left - b.left + r.width / 2) + "px";
        tip.style.top = (r.top - b.top) + "px";
        tip.style.opacity = 1;
      });
      rect.addEventListener("mouseleave", function () { tip.style.opacity = 0; });
    });
  }

  /* -------------------------------------------------------------- 横バー */

  function drawBars(id, rows) {
    var box = $(id);
    if (!rows.length || !rows[0].value) {
      box.innerHTML = '<div class="empty" style="padding:16px 0">データがありません。</div>';
      return;
    }
    var max = Math.max.apply(null, rows.map(function (r) { return r.value; })) || 1;
    box.innerHTML = rows.map(function (r) {
      return '<div class="hb"><span class="nm">' + esc(r.name) + "</span>" +
        '<span class="tr"><span class="fl" style="width:' +
          Math.max((r.value / max) * 100, 1).toFixed(1) + '%"></span></span>' +
        '<span class="vl">' + yen(r.value) +
          (r.note ? '<br><span style="font-size:11px">' + esc(r.note) + "</span>" : "") +
        "</span></div>";
    }).join("");
  }

  /* -------------------------------------------------------------- 表 */

  function renderCustomers(rows) {
    if (!rows.length) {
      $("custTable").innerHTML = "<tr><td style='color:var(--muted)'>この期間の来店がありません。</td></tr>";
      return;
    }
    $("custTable").innerHTML =
      "<tr><th>お客様</th><th class='num'>来店</th><th class='num'>売上</th>" +
      "<th class='num'>1回あたり</th><th class='num'>最終来店</th></tr>" +
      rows.map(function (r) {
        return "<tr><td>" + esc(r.name) + "</td>" +
          "<td class='num'>" + r.visits + " 回</td>" +
          "<td class='num'>" + yen(r.sales) + "</td>" +
          "<td class='num'>" + yen(r.per_visit) + "</td>" +
          "<td class='num'>" + mdw(r.last_visit) + "</td></tr>";
      }).join("");
  }

  function renderDailyTable() {
    var rows = S.daily.filter(function (d) { return d.visits > 0; });
    if (!rows.length) {
      $("dailyTable").innerHTML = "<tr><td style='color:var(--muted)'>この期間に売上がありません。</td></tr>";
      return;
    }
    $("dailyTable").innerHTML =
      "<tr><th>営業日</th><th class='num'>組</th><th class='num'>人数</th><th class='num'>売上</th>" +
      "<th class='num'>客単価</th><th class='num'>現金</th><th class='num'>カード</th>" +
      "<th class='num'>売掛</th><th>締め</th></tr>" +
      rows.map(function (d) {
        return "<tr><td>" + mdw(d.business_date) + "</td>" +
          "<td class='num'>" + d.visits + "</td>" +
          "<td class='num'>" + d.guests + "</td>" +
          "<td class='num' style='font-weight:600'>" + yen(d.sales) + "</td>" +
          "<td class='num'>" + yen(d.per_guest) + "</td>" +
          "<td class='num'>" + yen(d.cash) + "</td>" +
          "<td class='num'>" + yen(d.card) + "</td>" +
          "<td class='num'>" + (d.credit ? yen(d.credit) : "—") + "</td>" +
          "<td>" + (d.closed ? '<span class="tag settled">済</span>'
                             : '<span class="tag open">未</span>') + "</td></tr>";
      }).join("");
  }

  /* -------------------------------------------------------------- CSV */

  $("csvBtn").addEventListener("click", function () {
    var head = ["営業日", "組数", "人数", "売上", "客単価", "現金", "カード", "売掛",
                "サービス料", "消費税", "値引き", "日締め"];
    var lines = [head.join(",")].concat(S.daily.map(function (d) {
      return [d.business_date, d.visits, d.guests, d.sales, d.per_guest, d.cash, d.card,
              d.credit, d.service, d.tax, d.discount, d.closed ? "済" : "未"].join(",");
    }));
    // Excel が文字化けしないよう BOM を付けます
    var blob = new Blob(["﻿" + lines.join("\r\n")], { type: "text/csv;charset=utf-8" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "売上_" + S.store.name + "_" + S.from + "_" + S.to + ".csv";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 1000);
  });

  /* -------------------------------------------------------------- 起動 */

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  boot();
})();
