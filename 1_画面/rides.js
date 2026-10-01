/* ============================================================================
   だんどりシリーズ / ナイトだんどり 送り
   rides.js
   置き場所： サイトのルート（rides.html と同じ階層）

   地図APIは使いません。回る順番は「上へ／下へ」で手で並べ替えます。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  var S = { me: null, stores: [], store: null, areas: [], drivers: [],
            casts: [], customers: [], rides: [], timer: null };

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
  function hhmm(ts) {
    return ts ? new Date(ts).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }) : "";
  }
  var SUBJ = { customer: "お客様", cast: "キャスト", other: "その他" };
  var ST = { waiting: "待ち", onboard: "走行中", done: "完了", canceled: "取消" };

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
          document.body.className = "theme-" + (CFG.theme || "dark");
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
    if (S.store.ui_theme) document.body.className = "theme-" + S.store.ui_theme;
    Promise.all([
      sb.from("night_area").select("*").eq("store_id", id).eq("is_active", true).order("sort_order"),
      sb.from("staff").select("id,name,role").in("role", ["driver", "staff", "manager", "owner"])
        .eq("is_active", true).order("name"),
      sb.from("night_cast").select("id,name").eq("store_id", id).eq("is_active", true).order("name"),
      sb.from("night_customer").select("id,name").eq("store_id", id).eq("is_blocked", false).order("name")
    ]).then(function (r) {
      S.areas = r[0].data || [];
      S.drivers = r[1].data || [];
      S.casts = r[2].data || [];
      S.customers = r[3].data || [];
      var t = new Date();
      if (!$("sFrom").value) {
        $("sFrom").value = ymd(new Date(t.getFullYear(), t.getMonth(), 1));
        $("sTo").value = ymd(t);
      }
      switchView("today");
    });
  }

  /* -------------------------------------------------------------- 画面切替 */

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });
  function switchView(v) {
    ["today", "sum", "area"].forEach(function (n) {
      $("view-" + n).classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (S.timer) { clearInterval(S.timer); S.timer = null; }
    if (v === "today") {
      loadRides();
      if (CFG.refreshSeconds > 0) S.timer = setInterval(loadRides, CFG.refreshSeconds * 1000);
    }
    if (v === "sum") loadSummary();
    if (v === "area") renderAreas();
  }

  /* -------------------------------------------------------------- 今夜の送り */

  $("rideReload").addEventListener("click", loadRides);
  $("rideAdd").addEventListener("click", function () { rideDialog(); });

  function loadRides() {
    sb.rpc("night_ride_day", { p_store: S.store.id, p_date: null }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      S.rides = q.data || [];
      var live = S.rides.filter(function (r) { return r.status !== "canceled"; });
      var wait = live.filter(function (r) { return r.status === "waiting"; }).length;
      var fee = live.filter(function (r) { return r.status === "done"; })
                    .reduce(function (a, r) { return a + (r.fee || 0); }, 0);
      $("rideSummary").textContent = live.length
        ? live.length + "件　待ち " + wait + "　送り代 " + yen(fee) : "";
      $("rideEmpty").classList.toggle("hidden", S.rides.length > 0);

      var html = "";
      ["onboard", "waiting", "done", "canceled"].forEach(function (st) {
        var rows = S.rides.filter(function (r) { return r.status === st; });
        if (!rows.length) return;
        html += '<div class="grp">' + ST[st] + "　" + rows.length + "件</div>" +
          rows.map(function (r) { return rideCard(r); }).join("");
      });
      $("rideList").innerHTML = html;

      bind("[data-go]", function (id) { setStatus(id, "onboard"); });
      bind("[data-done]", function (id) { setStatus(id, "done"); });
      bind("[data-back]", function (id) { setStatus(id, "waiting"); });
      bind("[data-cancel]", function (id) { setStatus(id, "canceled"); });
      bind("[data-up]", function (id) { move(id, -1); });
      bind("[data-down]", function (id) { move(id, 1); });
      bind("[data-drv]", function (id) { driverDialog(id); });
    });
  }

  function rideCard(r) {
    var meta = [];
    meta.push(SUBJ[r.subject] || r.subject);
    if (r.area_name) meta.push(r.area_name);
    if (r.head_count > 1) meta.push(r.head_count + "名");
    if (r.fee) meta.push("送り代 " + yen(r.fee));
    if (r.driver_fee) meta.push("ドライバー " + yen(r.driver_fee));
    if (r.departed_at) meta.push("出発 " + hhmm(r.departed_at));
    if (r.arrived_at) meta.push("到着 " + hhmm(r.arrived_at));

    var acts = "";
    if (r.status === "waiting") {
      acts = '<button class="btn ghost" data-up="' + r.id + '">↑</button>' +
             '<button class="btn ghost" data-down="' + r.id + '">↓</button>' +
             '<button class="btn ghost" data-drv="' + r.id + '">ドライバー</button>' +
             '<button class="btn primary" data-go="' + r.id + '">出発</button>';
    } else if (r.status === "onboard") {
      acts = '<button class="btn ghost" data-back="' + r.id + '">戻す</button>' +
             '<button class="btn primary" data-done="' + r.id + '">到着</button>';
    } else if (r.status === "done") {
      acts = '<button class="btn ghost" data-back="' + r.id + '">やり直す</button>';
    }
    if (r.status === "waiting") {
      acts += '<button class="btn danger" data-cancel="' + r.id + '">取消</button>';
    }

    return '<div class="ride ' + r.status + '">' +
      '<div class="no">' + r.seq + "</div>" +
      "<div><div class='who'>" + esc(r.who) +
        (r.destination ? " <span style='font-weight:400;color:var(--muted)'>→ " +
          esc(r.destination) + "</span>" : "") + "</div>" +
        '<div class="meta">' + meta.map(function (m) { return "<span>" + esc(m) + "</span>"; }).join("") +
        (r.driver_name ? "<span style='color:var(--gold)'>" + esc(r.driver_name) + "</span>"
                       : "<span style='color:var(--bad)'>ドライバー未定</span>") + "</div></div>" +
      '<div class="acts">' + acts + "</div></div>";
  }

  function bind(sel, fn) {
    Array.prototype.forEach.call($("rideList").querySelectorAll(sel), function (b) {
      var key = Object.keys(b.dataset)[0];
      b.addEventListener("click", function () { fn(b.dataset[key]); });
    });
  }

  function setStatus(id, st) {
    sb.rpc("night_ride_status", { p_ride: id, p_status: st }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      loadRides();
    });
  }
  function move(id, dir) {
    sb.rpc("night_ride_move", { p_ride: id, p_dir: dir }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      loadRides();
    });
  }

  function driverDialog(id) {
    modal("<h2>ドライバーを割り当てる</h2>" +
      '<div class="field"><label for="d_drv">担当</label><select id="d_drv">' +
        '<option value="">（未定）</option>' +
        S.drivers.map(function (d) {
          return '<option value="' + d.id + '">' + esc(d.name) +
            (d.role === "driver" ? "（ドライバー）" : "") + "</option>";
        }).join("") + "</select></div>" +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">割り当てる</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_ride_assign", {
            p_ride: id, p_driver: root.querySelector("#d_drv").value || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); loadRides();
          });
        });
      });
  }

  function rideDialog() {
    if (!S.areas.length) {
      toast("先にエリアを登録してください（エリア設定タブ）", "err");
      switchView("area"); return;
    }
    modal("<h2>送りを追加</h2>" +
      '<div class="field"><label for="r_subj">どなたの送りか</label><select id="r_subj">' +
        '<option value="customer">お客様</option><option value="cast">キャスト</option>' +
        '<option value="other">その他</option></select></div>' +
      '<div class="field" id="wrapCust"><label for="r_cust">お客様</label><select id="r_cust">' +
        '<option value="">（台帳にない方）</option>' +
        S.customers.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + "</option>"; }).join("") +
      "</select></div>" +
      '<div class="field hidden" id="wrapCast"><label for="r_cast">キャスト</label><select id="r_cast">' +
        S.casts.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + "</option>"; }).join("") +
      "</select></div>" +
      '<div class="field" id="wrapLabel"><label for="r_label">お名前（台帳にない方）</label>' +
        '<input id="r_label" placeholder="中村様"></div>' +
      '<div class="field"><label for="r_area">エリア</label><select id="r_area">' +
        S.areas.map(function (a) {
          return '<option value="' + a.id + '">' + esc(a.name) + "（" + yen(a.fee) + "）</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="r_dest">行き先</label>' +
        '<input id="r_dest" placeholder="ご自宅（六甲道）"></div>' +
      '<div class="field"><label for="r_head">人数</label>' +
        '<input id="r_head" type="number" min="1" value="1" inputmode="numeric"></div>' +
      '<div class="field"><label for="r_note">メモ</label><input id="r_note"></div>' +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">追加する</button></div>',
      function (root) {
        var subj = root.querySelector("#r_subj");
        function sync() {
          root.querySelector("#wrapCust").classList.toggle("hidden", subj.value !== "customer");
          root.querySelector("#wrapCast").classList.toggle("hidden", subj.value !== "cast");
          root.querySelector("#wrapLabel").classList.toggle("hidden", subj.value === "cast");
        }
        subj.addEventListener("change", sync); sync();

        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var sv = subj.value;
          sb.rpc("night_ride_add", {
            p_store: S.store.id,
            p_subject: sv,
            p_customer: sv === "customer" ? (root.querySelector("#r_cust").value || null) : null,
            p_cast: sv === "cast" ? (root.querySelector("#r_cast").value || null) : null,
            p_label: sv !== "cast" ? (root.querySelector("#r_label").value.trim() || null) : null,
            p_area: root.querySelector("#r_area").value || null,
            p_destination: root.querySelector("#r_dest").value.trim() || null,
            p_head_count: Number(root.querySelector("#r_head").value) || 1,
            p_visit: null,
            p_note: root.querySelector("#r_note").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("追加しました", "ok"); loadRides();
          });
        });
      });
  }

  /* -------------------------------------------------------------- 集計 */

  $("sGo").addEventListener("click", loadSummary);

  function loadSummary() {
    var f = $("sFrom").value, t = $("sTo").value;
    if (!f || !t) return;
    sb.rpc("night_ride_summary", { p_store: S.store.id, p_from: f, p_to: t })
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var rows = q.data || [];
        if (!rows.length) {
          $("sumArea").innerHTML = "<div class='empty'>この期間に完了した送りがありません。</div>";
          return;
        }
        var byKind = function (k) { return rows.filter(function (r) { return r.kind === k; }); };
        var tbl = function (title, list, col) {
          return "<h2 style='margin-top:18px'>" + title + "</h2>" +
            "<div class='scroll'><table class='list'><tr><th>" + col + "</th>" +
            "<th class='num'>件数</th><th class='num'>人数</th>" +
            "<th class='num'>送り代</th><th class='num'>ドライバー代</th><th class='num'>差引</th></tr>" +
            list.map(function (r) {
              return "<tr><td>" + esc(r.name) + "</td>" +
                "<td class='num'>" + r.rides + "</td>" +
                "<td class='num'>" + r.heads + "</td>" +
                "<td class='num'>" + yen(r.fee_total) + "</td>" +
                "<td class='num'>" + yen(r.driver_cost) + "</td>" +
                "<td class='num'" + (r.fee_total - r.driver_cost < 0 ? " style='color:var(--bad)'" : "") +
                  ">" + yen(r.fee_total - r.driver_cost) + "</td></tr>";
            }).join("") + "</table></div>";
        };
        $("sumArea").innerHTML = tbl("ドライバー別", byKind("driver"), "ドライバー") +
                                 tbl("エリア別", byKind("area"), "エリア");
      });
  }

  /* -------------------------------------------------------------- エリア設定 */

  $("areaAdd").addEventListener("click", function () { areaDialog(null); });
  $("areaSeed").addEventListener("click", function () {
    sb.rpc("night_seed_area", { p_store: S.store.id }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      toast(q.data > 0 ? q.data + "件を入れました" : "すでにエリアが登録されています",
            q.data > 0 ? "ok" : "err");
      reloadAreas();
    });
  });

  function reloadAreas() {
    return sb.from("night_area").select("*").eq("store_id", S.store.id).order("sort_order")
      .then(function (q) { S.areas = q.data || []; renderAreas(); });
  }

  function renderAreas() {
    if (!S.areas.length) {
      $("areaTable").innerHTML =
        "<tr><td style='color:var(--muted);padding:18px 0'>エリアがまだ登録されていません。" +
        "「ひな形を入れる」を押すと、4件が入ります。</td></tr>";
      return;
    }
    $("areaTable").innerHTML =
      "<tr><th>エリア</th><th class='num'>送り代</th><th class='num'>ドライバー代</th>" +
      "<th class='num'>差引</th><th>状態</th><th></th></tr>" +
      S.areas.map(function (a) {
        return "<tr" + (a.is_active ? "" : " style='opacity:.5'") + "><td>" + esc(a.name) + "</td>" +
          "<td class='num'>" + yen(a.fee) + "</td>" +
          "<td class='num'>" + yen(a.driver_fee) + "</td>" +
          "<td class='num'" + (a.fee - a.driver_fee < 0 ? " style='color:var(--bad)'" : "") + ">" +
            yen(a.fee - a.driver_fee) + "</td>" +
          "<td>" + (a.is_active ? "有効" : "停止") + "</td>" +
          '<td><button class="btn ghost" style="padding:6px 12px" data-ar="' + a.id + '">編集</button></td></tr>';
      }).join("");

    Array.prototype.forEach.call($("areaTable").querySelectorAll("button[data-ar]"), function (b) {
      b.addEventListener("click", function () { areaDialog(b.dataset.ar); });
    });
  }

  function areaDialog(id) {
    var a = id ? S.areas.filter(function (x) { return x.id === id; })[0] : null;
    modal("<h2>" + (a ? "エリアの編集" : "エリアを追加") + "</h2>" +
      '<div class="field"><label for="a_name">エリア名</label>' +
        '<input id="a_name" value="' + esc(a ? a.name : "") + '" placeholder="灘・六甲道"></div>' +
      '<div class="field"><label for="a_fee">お客様からいただく額</label>' +
        '<input id="a_fee" type="number" min="0" inputmode="numeric" value="' + (a ? a.fee : 0) + '"></div>' +
      '<div class="field"><label for="a_dfee">ドライバーへ支払う額</label>' +
        '<input id="a_dfee" type="number" min="0" inputmode="numeric" value="' + (a ? a.driver_fee : 0) + '"></div>' +
      '<div class="field"><label for="a_sort">並び順</label>' +
        '<input id="a_sort" type="number" value="' + (a ? a.sort_order : 99) + '"></div>' +
      (a ? '<div class="field"><label for="a_act">状態</label><select id="a_act">' +
        '<option value="1"' + (a.is_active ? " selected" : "") + ">有効</option>" +
        '<option value="0"' + (!a.is_active ? " selected" : "") + ">停止</option></select></div>" : "") +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var payload = {
            tenant_id: S.me.tenant_id, store_id: S.store.id,
            name: root.querySelector("#a_name").value.trim(),
            fee: Number(root.querySelector("#a_fee").value) || 0,
            driver_fee: Number(root.querySelector("#a_dfee").value) || 0,
            sort_order: Number(root.querySelector("#a_sort").value) || 99
          };
          if (!payload.name) { toast("エリア名を入れてください", "err"); return; }
          var ac = root.querySelector("#a_act");
          if (ac) payload.is_active = ac.value === "1";

          var q = a ? sb.from("night_area").update(payload).eq("id", a.id)
                    : sb.from("night_area").insert(payload);
          q.then(function (res) {
            if (res.error) { fail(res.error); return; }
            closeModal(); toast("保存しました", "ok"); reloadAreas();
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
