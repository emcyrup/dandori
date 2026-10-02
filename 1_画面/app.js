/* ============================================================================
   だんどりシリーズ / ナイトだんどり 伝票・会計
   app.js
   置き場所： サイトのルート（index.html と同じ階層）

   お金の計算はすべてデータベース側の関数（002_rpc.sql）で行います。
   この画面は「表示」と「関数を呼ぶ」だけを担当します。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);

  var S = {            // 画面の状態
    me: null,
    stores: [],
    store: null,
    casts: [],
    menus: [],
    customers: [],
    visit: null,
    items: [],
    bottles: [],
    view: "hall",
    timer: null
  };

  /* ---------------------------------------------------------------- 小道具 */

  var $ = function (id) { return document.getElementById(id); };
  var yen = function (n) { return "¥" + (n || 0).toLocaleString("ja-JP"); };

  function toast(msg, kind) {
    var el = document.createElement("div");
    el.className = "toast" + (kind ? " " + kind : "");
    el.textContent = msg;
    $("toast").appendChild(el);
    setTimeout(function () { el.remove(); }, kind === "err" ? 6000 : 3000);
  }

  function fail(e) {
    var m = (e && (e.message || e.error_description || e.details)) || String(e);
    m = m.replace(/^.*?:\s*/, "");        // Postgres の接頭辞を落とす
    toast(m, "err");
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

  var CAT_LABEL = {
    set: "セット", extension: "延長", nomination: "指名", douhan: "同伴",
    drink: "ドリンク", bottle: "ボトル", food: "フード", other: "その他"
  };
  var CAT_ORDER = ["set", "extension", "nomination", "douhan", "drink", "bottle", "food", "other"];

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

  function boot() {
    sb.auth.getSession().then(function (r) {
      var _u = (r && r.data && r.data.session) ? r.data.session.user : null;
      if (!_u) { showLogin(); return; }
      return sb.from("staff").select("*").eq("auth_user_id", _u.id).maybeSingle()
        .then(function (q) {
          if (q.error) { fail(q.error); return; }
          if (!q.data) {
            toast("このアカウントにスタッフ登録がありません。管理者に staff テーブルへの登録を依頼してください。", "err");
            return;
          }
          S.me = q.data;
          $("meName").textContent = S.me.name + "（" + roleLabel(S.me.role) + "）";
          $("login").classList.add("hidden");
          $("app").classList.remove("hidden");
          document.body.className = "theme-" + (CFG.theme || "dark");
          return loadStores();
        });
    }).catch(fail);
  }

  function roleLabel(r) {
    return { owner: "オーナー", manager: "店長", staff: "スタッフ", driver: "ドライバー" }[r] || r;
  }

  function showLogin() {
    $("login").classList.remove("hidden");
    $("app").classList.add("hidden");
  }

  /* -------------------------------------------------------------- 店舗 */

  /*  お店のえらびかた
      ・その業種のお店だけを出します（store.industry を見ています）
      ・えらんだお店は、業種ごとに別々に覚えます。
        ほかの業種の画面をひらいても、入れかわりません。
      ・画面を更新しても、前にえらんだお店のままです。 */
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
    if (CFG.theme === "dark" && S.store.ui_theme && S.store.ui_theme !== "dark") {
      document.body.className = "theme-" + S.store.ui_theme;
    }
    Promise.all([loadMasters()]).then(function () { switchView("hall"); });
  }

  function loadMasters() {
    return Promise.all([
      sb.from("night_cast").select("id,name").eq("store_id", S.store.id).eq("is_active", true).order("name"),
      sb.from("night_menu").select("*").eq("store_id", S.store.id).eq("is_active", true)
        .order("sort_order"),
      sb.from("night_customer").select("id,name,visit_count").eq("store_id", S.store.id)
        .eq("is_blocked", false).order("name")
    ]).then(function (r) {
      S.casts = (r[0].data) || [];
      S.menus = (r[1].data) || [];
      S.customers = (r[2].data) || [];
    });
  }

  /* -------------------------------------------------------------- 画面切替 */

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  function switchView(v) {
    S.view = v;
    if (v !== "ticket") $("bottleBox").classList.add("hidden");
    ["hall", "ticket", "recv"].forEach(function (n) {
      $("view-" + n).classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (S.timer) { clearInterval(S.timer); S.timer = null; }

    if (v === "hall") {
      loadHall();
      if (CFG.refreshSeconds > 0) S.timer = setInterval(loadHall, CFG.refreshSeconds * 1000);
    }
    if (v === "recv") loadReceivables();
  }

  /* -------------------------------------------------------------- ホール */

  $("reloadBtn").addEventListener("click", loadHall);
  $("openBtn").addEventListener("click", openVisitDialog);

  function loadHall() {
    if (!S.store) return;
    sb.from("v_open_visit").select("*").eq("store_id", S.store.id).order("entered_at")
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var rows = q.data || [];
        $("hallEmpty").classList.toggle("hidden", rows.length > 0);
        var sum = rows.reduce(function (a, r) { return a + (r.total || 0); }, 0);
        $("hallSummary").textContent = rows.length
          ? rows.length + "卓　合計 " + yen(sum) : "";
        $("hallCards").innerHTML = rows.map(function (r) {
          var longStay = r.minutes >= 90;
          return '<button class="card' + (longStay ? " long" : "") + '" data-id="' + r.id + '">' +
            '<span class="tno">' + esc(r.table_no || "—") + "</span>" +
            '<span class="gname">' + esc(r.guest || "（お名前なし）") + "</span>" +
            '<span class="meta">' +
              "<span>" + esc(r.main_cast || "フリー") + "</span>" +
              "<span>" + r.head_count + "名</span>" +
              '<span class="min mono">' + r.minutes + "分</span>" +
            "</span>" +
            '<span class="amt mono">' + yen(r.total) + "</span>" +
          "</button>";
        }).join("");
        Array.prototype.forEach.call($("hallCards").querySelectorAll(".card"), function (c) {
          c.addEventListener("click", function () { openTicket(c.dataset.id); });
        });
      });
  }

  function openVisitDialog() {
    modal(
      "<h2>卓を開く</h2>" +
      '<div class="field"><label for="m_table">卓番</label>' +
        '<input id="m_table" placeholder="A-1"></div>' +
      '<div class="field"><label for="m_cust">お客様</label><select id="m_cust">' +
        '<option value="">（新規・名前だけ入れる）</option>' +
        S.customers.map(function (c) {
          return '<option value="' + c.id + '">' + esc(c.name) + "（" + c.visit_count + "回）</option>";
        }).join("") + "</select></div>" +
      '<div class="field"><label for="m_guest">お名前（新規のとき）</label>' +
        '<input id="m_guest" placeholder="山本様"></div>' +
      '<div class="field"><label for="m_head">人数</label>' +
        '<input id="m_head" type="number" min="1" value="1" inputmode="numeric"></div>' +
      '<div class="field"><label for="m_cast">担当キャスト</label><select id="m_cast">' +
        '<option value="">（なし）</option>' +
        S.casts.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + "</option>"; }).join("") +
        "</select></div>" +
      '<div class="row" style="margin-top:16px">' +
        '<button class="btn ghost" id="m_cancel">やめる</button>' +
        '<button class="btn primary" id="m_ok" style="flex:1">開く</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          sb.rpc("night_open_visit", {
            p_store: S.store.id,
            p_table_no: root.querySelector("#m_table").value.trim() || null,
            p_customer: root.querySelector("#m_cust").value || null,
            p_guest_name: root.querySelector("#m_guest").value.trim() || null,
            p_head_count: Number(root.querySelector("#m_head").value) || 1,
            p_cast: root.querySelector("#m_cast").value || null
          }).then(function (q) {
            btn.disabled = false;
            if (q.error) { fail(q.error); return; }
            closeModal();
            openTicket(q.data.id);
          });
        });
        root.querySelector("#m_table").focus();
      }
    );
  }

  /* -------------------------------------------------------------- 伝票 */

  $("backBtn").addEventListener("click", function () { switchView("hall"); });

  function openTicket(id) {
    switchView("ticket");
    loadTicket(id);
  }

  function loadTicket(id) {
    return Promise.all([
      sb.from("night_visit").select("*").eq("id", id).single(),
      sb.from("night_visit_item").select("*").eq("visit_id", id).order("punched_at")
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      S.visit = r[0].data;
      S.items = r[1].data || [];
      renderTicket();
      loadBottles();
    });
  }

  function castName(id) {
    var c = S.casts.filter(function (x) { return x.id === id; })[0];
    return c ? c.name : "";
  }

  function renderTicket() {
    var v = S.visit;
    var cust = S.customers.filter(function (c) { return c.id === v.customer_id; })[0];
    $("ticketTitle").textContent = (v.table_no || "卓") + "　" +
      (cust ? cust.name : (v.guest_name || "お名前なし"));
    $("ticketMeta").textContent = v.head_count + "名　" +
      (castName(v.main_cast_id) ? "担当 " + castName(v.main_cast_id) : "フリー（担当なし）") + "　" +
      new Date(v.entered_at).toLocaleTimeString("ja-JP", { hour: "2-digit", minute: "2-digit" }) + " 入店";

    // キャスト選択
    $("castBtn").textContent = v.main_cast_id ? "担当を変える" : "担当を決める";
    $("castSel").innerHTML = '<option value="">（担当：' + (castName(v.main_cast_id) || "なし") + "）</option>" +
      S.casts.map(function (c) { return '<option value="' + c.id + '">' + esc(c.name) + "</option>"; }).join("");

    // メニュー
    var byCat = {};
    S.menus.forEach(function (m) { (byCat[m.category] = byCat[m.category] || []).push(m); });
    $("menuArea").innerHTML = CAT_ORDER.filter(function (c) { return byCat[c]; }).map(function (c) {
      return '<div class="cat"><h3>' + (CAT_LABEL[c] || c) + "</h3>" +
        '<div class="menu-grid">' + byCat[c].map(function (m) {
          var back = m.back_amount > 0 ? "／バック" + yen(m.back_amount)
                   : (Number(m.back_rate) > 0 ? "／バック" + m.back_rate + "%" : "");
          return '<button class="menu-btn" data-menu="' + m.id + '"><b>' + esc(m.name) + "</b>" +
                 "<span>" + yen(m.unit_price) + back + "</span></button>";
        }).join("") + "</div></div>";
    }).join("");

    Array.prototype.forEach.call($("menuArea").querySelectorAll(".menu-btn"), function (b) {
      b.addEventListener("click", function () { addItem(b.dataset.menu); });
    });

    // 明細
    $("itemList").innerHTML = S.items.length ? S.items.map(function (i) {
      var sub = [];
      if (i.quantity > 1) sub.push(yen(i.unit_price) + " × " + i.quantity);
      if (i.cast_id) sub.push(castName(i.cast_id) + (i.back_amount ? "（バック" + yen(i.back_amount) + "）" : ""));
      return '<div class="item"><span class="nm">' + esc(i.name) +
        (sub.length ? '<span class="sub">' + esc(sub.join("　")) + "</span>" : "") + "</span>" +
        '<span class="am mono">' + yen(i.amount) + "</span>" +
        '<button data-item="' + i.id + '" title="消す">×</button></div>';
    }).join("") : '<div class="empty" style="padding:18px 0">まだ何も打たれていません。</div>';

    Array.prototype.forEach.call($("itemList").querySelectorAll("button[data-item]"), function (b) {
      b.addEventListener("click", function () { removeItem(b.dataset.item); });
    });

    // 合計
    $("totals").innerHTML =
      "<div><span>小計</span><span class='mono'>" + yen(v.subtotal) + "</span></div>" +
      "<div><span>サービス料 " + Number(S.store.service_rate) + "%</span><span class='mono'>" + yen(v.service_charge) + "</span></div>" +
      "<div><span>消費税</span><span class='mono'>" + yen(v.tax) + "</span></div>" +
      (v.discount ? "<div><span>値引き</span><span class='mono'>-" + yen(v.discount) + "</span></div>" : "") +
      "<div class='grand'><span>合計</span><span class='mono'>" + yen(v.total) + "</span></div>";

    $("payBtn").disabled = !S.items.length;
  }

  /* -------------------------------------------------------------- 卓の担当（フリーの割り振り） */

  $("castBtn").addEventListener("click", function () {
    var v = S.visit;
    modal(
      "<h2>" + esc(v.table_no || "卓") + "　担当キャスト</h2>" +
      "<p style='color:var(--muted);font-size:12.5px;margin:-8px 0 14px'>" +
        "フリーのお客様についたキャストを選びます。この卓で付くドリンクなどのバックと個人売上が、そのキャストに付きます" +
        "（指名料は付きません）。</p>" +
      '<div class="field"><label for="sc_cast">担当</label><select id="sc_cast">' +
        '<option value="">（フリー・担当なし）</option>' +
        S.casts.map(function (c) {
          return '<option value="' + c.id + '"' + (c.id === v.main_cast_id ? " selected" : "") + ">" + esc(c.name) + "</option>";
        }).join("") + "</select></div>" +
      '<div class="row" style="margin-top:16px">' +
        '<button class="btn ghost" id="m_cancel">やめる</button>' +
        '<button class="btn primary" id="m_ok" style="flex:1">決める</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var btn = this; btn.disabled = true;
          sb.rpc("night_set_cast", { p_visit: v.id, p_cast: root.querySelector("#sc_cast").value || null })
            .then(function (q) {
              btn.disabled = false;
              if (q.error) { fail(q.error); return; }
              closeModal();
              toast(q.data && q.data.main_cast_id ? castName(q.data.main_cast_id) + " を担当にしました" : "フリーに戻しました", "ok");
              loadTicket(v.id);
            });
        });
      }
    );
  });

  function addItem(menuId) {
    sb.rpc("night_add_item", {
      p_visit: S.visit.id,
      p_menu: menuId,
      p_quantity: Number($("qtyInput").value) || 1,
      p_cast: $("castSel").value || null
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      $("qtyInput").value = 1;
      loadTicket(S.visit.id);
    });
  }

  function removeItem(itemId) {
    sb.rpc("night_remove_item", { p_item: itemId }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      loadTicket(S.visit.id);
    });
  }

  $("discountBtn").addEventListener("click", function () {
    modal("<h2>値引き</h2>" +
      '<div class="field"><label for="m_disc">値引き額（円）</label>' +
      '<input id="m_disc" type="number" min="0" inputmode="numeric" value="' + (S.visit.discount || 0) + '"></div>' +
      '<div class="row" style="margin-top:16px">' +
      '<button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">反映する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_set_discount", {
            p_visit: S.visit.id,
            p_discount: Number(root.querySelector("#m_disc").value) || 0
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); loadTicket(S.visit.id);
          });
        });
      });
  });

  /* ------------------------------------------------------- ボトルキープ */

  function loadBottles() {
    var box = $("bottleBox");
    if (!S.visit || !S.visit.customer_id) {
      // 台帳のお客様が紐づいていない卓でも、登録だけはできるようにします
      box.classList.remove("hidden");
      $("bottleList").innerHTML =
        "<div class='empty' style='padding:10px 0'>お客様が紐づいていないため、キープの呼び出しはできません。" +
        "登録は下のボタンからできます。</div>";
      return;
    }
    sb.rpc("night_bottle_list", {
      p_store: S.store.id, p_status: "keeping", p_customer: S.visit.customer_id
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      S.bottles = q.data || [];
      box.classList.remove("hidden");
      $("bottleList").innerHTML = S.bottles.length ? S.bottles.map(function (b) {
        var left = b.days_left;
        var warn = left != null && left <= 30;
        return '<div class="item" style="grid-template-columns:1fr auto auto">' +
          '<span class="nm">' + esc(b.name) +
            '<span class="sub">棚番 ' + esc(b.location || "—") + "　残り " + b.remaining + "%" +
            (left != null ? "　" + (left < 0 ? "期限切れ（" + Math.abs(left) + "日超過）"
                                             : "期限まで" + left + "日") : "") + "</span></span>" +
          '<span class="am"' + (warn ? ' style="color:var(--warn)"' : "") + '>' +
            (left != null && left < 0 ? "期限切れ" : "") + "</span>" +
          '<button class="btn ghost" style="padding:6px 12px" data-serve="' + b.id + '">出す</button>' +
        "</div>";
      }).join("") :
        "<div class='empty' style='padding:10px 0'>キープ中のボトルはありません。</div>";

      Array.prototype.forEach.call($("bottleList").querySelectorAll("button[data-serve]"), function (x) {
        x.addEventListener("click", function () { serveBottle(x.dataset.serve); });
      });
    });
  }

  function serveBottle(id) {
    var b = S.bottles.filter(function (x) { return x.id === id; })[0] || {};
    var opts = [100, 75, 50, 25, 0].filter(function (v) { return v <= (b.remaining || 100); });
    modal("<h2>ボトルを出す</h2>" +
      "<p style='color:var(--muted);font-size:13px;margin:-8px 0 14px'>" +
        esc(b.name) + "（棚番 " + esc(b.location || "—") + "）　いまの残量 " + b.remaining + "%</p>" +
      '<div class="field"><label for="bs_rem">出したあとの残量</label><select id="bs_rem">' +
        opts.map(function (v) {
          return '<option value="' + v + '">' + v + "%" + (v === 0 ? "（飲み切り）" : "") + "</option>";
        }).join("") + "</select></div>" +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_bottle_serve", {
            p_bottle: id,
            p_remaining: Number(root.querySelector("#bs_rem").value),
            p_visit: S.visit ? S.visit.id : null,
            p_memo: null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("記録しました", "ok"); loadBottles();
          });
        });
      });
  }

  $("bottleAdd").addEventListener("click", function () {
    if (!S.visit) return;
    modal("<h2>キープを登録</h2>" +
      '<div class="field"><label for="bk_name">銘柄</label>' +
        '<input id="bk_name" placeholder="黒霧島（一升）"></div>' +
      '<div class="field"><label for="bk_kind">種類</label>' +
        '<input id="bk_kind" placeholder="焼酎"></div>' +
      '<div class="field"><label for="bk_loc">棚番</label>' +
        '<input id="bk_loc" placeholder="A-12"></div>' +
      (S.visit.customer_id ? "" :
        '<div class="field"><label for="bk_guest">お名前</label>' +
        '<input id="bk_guest" value="' + esc(S.visit.guest_name || "") + '"></div>') +
      '<div class="field"><label for="bk_months">キープ期間（か月）</label>' +
        '<input id="bk_months" type="number" min="0" value="6"></div>' +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">登録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var g = function (k) {
            var el = root.querySelector("#" + k);
            if (!el) return null;
            var v = el.value.trim();
            return v === "" ? null : v;
          };
          if (!g("bk_name")) { toast("銘柄を入れてください", "err"); return; }
          sb.rpc("night_bottle_keep", {
            p_store: S.store.id,
            p_name: g("bk_name"),
            p_customer: S.visit.customer_id || null,
            p_guest: S.visit.customer_id ? null : g("bk_guest"),
            p_kind: g("bk_kind"),
            p_location: g("bk_loc"),
            p_cast: S.visit.main_cast_id || null,
            p_visit: S.visit.id,
            p_months: Number(root.querySelector("#bk_months").value),
            p_note: null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("キープに登録しました", "ok"); loadBottles();
          });
        });
      });
  });

  /* -------------------------------------------------------------- 会計 */

  $("payBtn").addEventListener("click", function () {
    var total = S.visit.total;
    modal(
      "<h2>会計　" + yen(total) + "</h2>" +
      '<div class="field"><label for="p_cash">現金</label>' +
        '<input id="p_cash" type="number" min="0" inputmode="numeric" value="' + total + '"></div>' +
      '<div class="field"><label for="p_card">カード</label>' +
        '<input id="p_card" type="number" min="0" inputmode="numeric" value="0"></div>' +
      '<div class="field"><label for="p_credit">売掛（ツケ）</label>' +
        '<input id="p_credit" type="number" min="0" inputmode="numeric" value="0"></div>' +
      '<div class="field" id="dueWrap" style="display:none"><label for="p_due">支払い期日</label>' +
        '<input id="p_due" type="date"></div>' +
      '<div class="pay-check ok" id="payCheck"></div>' +
      '<div class="row" style="margin-top:14px">' +
        '<button class="btn ghost" id="m_cancel">やめる</button>' +
        '<button class="btn primary" id="m_ok" style="flex:1">締める</button></div>',
      function (root) {
        var ins = ["p_cash", "p_card", "p_credit"].map(function (id) { return root.querySelector("#" + id); });
        var chk = root.querySelector("#payCheck");
        var ok = root.querySelector("#m_ok");

        function recheck() {
          var sum = ins.reduce(function (a, el) { return a + (Number(el.value) || 0); }, 0);
          var diff = sum - total;
          root.querySelector("#dueWrap").style.display =
            (Number(ins[2].value) || 0) > 0 ? "" : "none";
          if (diff === 0) {
            chk.className = "pay-check ok";
            chk.textContent = "ぴったりです。";
            ok.disabled = false;
          } else {
            chk.className = "pay-check ng";
            chk.textContent = diff > 0 ? "合計より " + yen(diff) + " 多いです。"
                                       : "あと " + yen(-diff) + " 足りません。";
            ok.disabled = true;
          }
        }
        ins.forEach(function (el) { el.addEventListener("input", recheck); });
        recheck();

        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        ok.addEventListener("click", function () {
          ok.disabled = true;
          sb.rpc("night_close_visit", {
            p_visit: S.visit.id,
            p_cash: Number(ins[0].value) || 0,
            p_card: Number(ins[1].value) || 0,
            p_credit: Number(ins[2].value) || 0,
            p_due_on: root.querySelector("#p_due").value || null,
            p_note: null
          }).then(function (q) {
            ok.disabled = false;
            if (q.error) { fail(q.error); return; }
            closeModal();
            toast("締めました　" + yen(q.data.total), "ok");
            switchView("hall");
          });
        });
      }
    );
  });

  /* -------------------------------------------------------------- 売掛 */

  function loadReceivables() {
    sb.from("night_receivable")
      .select("*, night_customer(name)")
      .eq("store_id", S.store.id).neq("status", "settled")
      .order("occurred_on")
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        var rows = q.data || [];
        $("recvEmpty").classList.toggle("hidden", rows.length > 0);
        var label = { open: "未入金", partial: "一部入金", written_off: "貸倒" };
        $("recvTable").innerHTML = rows.length ?
          "<tr><th>お客様</th><th>発生日</th><th>期日</th><th class='num'>残高</th><th></th></tr>" +
          rows.map(function (r) {
            var over = r.due_on && r.due_on < new Date().toISOString().slice(0, 10);
            return "<tr><td>" + esc(r.night_customer ? r.night_customer.name : "—") +
              ' <span class="tag ' + r.status + '">' + (label[r.status] || r.status) + "</span></td>" +
              "<td>" + r.occurred_on + "</td>" +
              "<td" + (over ? ' style="color:var(--bad)"' : "") + ">" + (r.due_on || "—") + "</td>" +
              "<td class='num'>" + yen(r.balance) + "</td>" +
              '<td><button class="btn ghost" style="padding:6px 12px" data-recv="' + r.id +
              '" data-bal="' + r.balance + '">入金</button></td></tr>';
          }).join("") : "";

        Array.prototype.forEach.call($("recvTable").querySelectorAll("button[data-recv]"), function (b) {
          b.addEventListener("click", function () { receiveDialog(b.dataset.recv, Number(b.dataset.bal)); });
        });
      });
  }

  function receiveDialog(id, balance) {
    modal("<h2>入金　残高 " + yen(balance) + "</h2>" +
      '<div class="field"><label for="r_amt">入金額</label>' +
      '<input id="r_amt" type="number" min="1" max="' + balance + '" value="' + balance + '" inputmode="numeric"></div>' +
      '<div class="field"><label for="r_memo">メモ</label><input id="r_memo" placeholder="本人来店時に受領"></div>' +
      '<div class="row" style="margin-top:16px">' +
      '<button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">記録する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("night_receive_payment", {
            p_receivable: id,
            p_amount: Number(root.querySelector("#r_amt").value) || 0,
            p_memo: root.querySelector("#r_memo").value.trim() || null
          }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            closeModal(); toast("入金を記録しました", "ok"); loadReceivables();
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
