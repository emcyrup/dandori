/* ============================================================================
   だんどりシリーズ / ナイトだんどり 設定
   admin.js
   置き場所： サイトのルート（admin.html と同じ階層）

   店舗の設定・料金マスタ・スタッフの確認を行う画面です。
   法人そのものの作成は、Supabase の SQL Editor から行います（006_provision.sql）。
   ============================================================================ */

(function () {
  "use strict";

  var CFG = window.DANDORI_CONFIG || {};
  var sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey);
  var S = { me: null, stores: [], store: null, menus: [], staff: [] };

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

  var CAT = {
    set: "セット", extension: "延長", nomination: "指名", douhan: "同伴",
    drink: "ドリンク", bottle: "ボトル", food: "フード", other: "その他"
  };

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
          if (S.me.role !== "owner" && S.me.role !== "manager") {
            document.body.innerHTML =
              '<div style="padding:40px;text-align:center;color:#8FA1B3">' +
              "設定画面は、店長以上の権限でご利用ください。</div>";
            return;
          }
          $("meName").textContent = S.me.name;
          $("login").classList.add("hidden");
          $("app").classList.remove("hidden");
          document.body.className = "theme-" + (CFG.theme || "dark");
          return loadStores();
        });
    }).catch(fail);
  }

  /*  お店のえらびかた（設定の画面は、停止中のお店も出します） */
  var MISEKEY = "dandori-store-" + (CFG.industry || "x");

  function loadStores() {
    return sb.from("store").select("*").order("created_at").then(function (q) {
      if (q.error) { fail(q.error); return; }
      var all = q.data || [];
      var mine = all.filter(function (s) { return s.industry === CFG.industry; });
      S.stores = mine.length ? mine : all;
      if (!S.stores.length) { toast("店舗が登録されていません。", "err"); return; }
      $("storeSel").innerHTML = S.stores.map(function (s) {
        return '<option value="' + s.id + '">' + esc(s.name) + (s.is_active ? "" : "（停止中）") + "</option>";
      }).join("");
      var keep = null;
      try { keep = localStorage.getItem(MISEKEY); } catch (e) {}
      var hit = S.stores.filter(function (s) { return s.id === keep; })[0];
      selectStore(hit ? hit.id : S.stores[0].id);
    });
  }
  $("storeSel").addEventListener("change", function () { selectStore(this.value); });

  function selectStore(id) {
    S.store = S.stores.filter(function (s) { return s.id === id; })[0];
    $("storeSel").value = id;
    try { localStorage.setItem(MISEKEY, id); } catch (e) {}
    fillStoreForm();
    switchView("store");
  }

  /* -------------------------------------------------------------- 画面切替 */

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  function switchView(v) {
    ["store", "menu", "staff", "imp", "ai"].forEach(function (n) {
      $("view-" + n).classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (v === "menu") loadMenus();
    if (v === "staff") loadStaff();
    if (v === "imp") loadImports();
    if (v === "ai") loadAi();
  }

  /* -------------------------------------------------------------- 店舗の設定 */

  function fillStoreForm() {
    var s = S.store;
    $("s_name").value = s.name || "";
    $("s_tel").value = s.tel || "";
    $("s_cutoff").value = (s.day_cutoff || "05:00:00").slice(0, 5);
    $("s_service").value = Number(s.service_rate);
    $("s_tax").value = Number(s.tax_rate);
    $("s_incl").value = s.tax_included ? "1" : "0";
    $("s_minwage").value = s.min_wage || 0;
    $("s_theme").value = s.ui_theme || "standard";
    updateHint();
  }

  ["s_service", "s_tax", "s_incl"].forEach(function (id) {
    $(id).addEventListener("input", updateHint);
  });

  function updateHint() {
    var base = 10000;
    var svc = Math.floor(base * (Number($("s_service").value) || 0) / 100);
    var tax = $("s_incl").value === "1" ? 0
            : Math.floor((base + svc) * (Number($("s_tax").value) || 0) / 100);
    $("storeCalcHint").textContent =
      "例：" + yen(base) + " のご注文 → サービス料 " + yen(svc) + "、税 " + yen(tax) +
      "、お会計 " + yen(base + svc + tax);
  }

  $("storeSave").addEventListener("click", function () {
    var btn = this; btn.disabled = true;
    sb.from("store").update({
      name: $("s_name").value.trim(),
      tel: $("s_tel").value.trim() || null,
      day_cutoff: $("s_cutoff").value || "05:00",
      service_rate: Number($("s_service").value) || 0,
      tax_rate: Number($("s_tax").value) || 0,
      tax_included: $("s_incl").value === "1",
      min_wage: Number($("s_minwage").value) || 0,
      ui_theme: $("s_theme").value
    }).eq("id", S.store.id).then(function (q) {
      btn.disabled = false;
      if (q.error) { fail(q.error); return; }
      toast("保存しました", "ok");
      loadStores();
    });
  });

  $("addStore").addEventListener("click", function () {
    var name = $("newStoreName").value.trim();
    if (!name) { toast("店舗名を入れてください", "err"); return; }
    var btn = this; btn.disabled = true;
    var s = S.store;
    sb.from("store").insert({
      tenant_id: S.me.tenant_id, name: name,
      day_cutoff: s.day_cutoff, service_rate: s.service_rate, tax_rate: s.tax_rate,
      tax_included: s.tax_included, min_wage: s.min_wage, ui_theme: s.ui_theme
    }).select().single().then(function (q) {
      if (q.error) { btn.disabled = false; fail(q.error); return; }
      return sb.rpc("night_seed_menu", { p_store: q.data.id }).then(function (r) {
        btn.disabled = false;
        if (r.error) { fail(r.error); return; }
        $("newStoreName").value = "";
        toast(name + " を追加しました（料金のひな形 " + r.data + "件）", "ok");
        loadStores();
      });
    });
  });

  /* -------------------------------------------------------------- 料金マスタ */

  function loadMenus() {
    sb.from("night_menu").select("*").eq("store_id", S.store.id)
      .order("sort_order").then(function (q) {
        if (q.error) { fail(q.error); return; }
        S.menus = q.data || [];
        renderMenus();
      });
  }

  function renderMenus() {
    if (!S.menus.length) {
      $("menuTable").innerHTML =
        "<tr><td style='color:var(--muted);padding:20px 0'>料金がまだ登録されていません。" +
        "「ひな形を入れる」を押すと、よくある13件が入ります。</td></tr>";
      return;
    }
    $("menuTable").innerHTML =
      "<tr><th>区分</th><th>名前</th><th class='num'>単価</th><th class='num'>バック</th>" +
      "<th>サービス料</th><th>税</th><th>状態</th><th></th></tr>" +
      S.menus.map(function (m) {
        var back = m.back_amount > 0 ? yen(m.back_amount)
                 : (Number(m.back_rate) > 0 ? m.back_rate + "%" : "—");
        return "<tr" + (m.is_active ? "" : " style='opacity:.5'") + ">" +
          "<td>" + (CAT[m.category] || m.category) + "</td>" +
          "<td>" + esc(m.name) + "</td>" +
          "<td class='num'>" + yen(m.unit_price) + "</td>" +
          "<td class='num'>" + back + "</td>" +
          "<td>" + (m.service_apply ? "かける" : "かけない") + "</td>" +
          "<td>" + (m.tax_apply ? "かける" : "かけない") + "</td>" +
          "<td>" + (m.is_active ? "有効" : "停止") + "</td>" +
          '<td><button class="btn ghost" style="padding:6px 12px" data-menu="' + m.id + '">編集</button></td>' +
        "</tr>";
      }).join("");

    Array.prototype.forEach.call($("menuTable").querySelectorAll("button[data-menu]"), function (b) {
      b.addEventListener("click", function () { menuDialog(b.dataset.menu); });
    });
  }

  $("menuAdd").addEventListener("click", function () { menuDialog(null); });

  $("menuSeed").addEventListener("click", function () {
    var btn = this; btn.disabled = true;
    sb.rpc("night_seed_menu", { p_store: S.store.id }).then(function (q) {
      btn.disabled = false;
      if (q.error) { fail(q.error); return; }
      toast(q.data > 0 ? q.data + "件を入れました" : "すでに料金が登録されています", q.data > 0 ? "ok" : "err");
      loadMenus();
    });
  });

  function menuDialog(id) {
    var m = id ? S.menus.filter(function (x) { return x.id === id; })[0] : null;
    var opt = Object.keys(CAT).map(function (k) {
      return '<option value="' + k + '"' + (m && m.category === k ? " selected" : "") + ">" + CAT[k] + "</option>";
    }).join("");

    modal("<h2>" + (m ? "料金の編集" : "料金を追加") + "</h2>" +
      '<div class="field"><label for="x_cat">区分</label><select id="x_cat">' + opt + "</select></div>" +
      '<div class="field"><label for="x_name">名前</label>' +
        '<input id="x_name" value="' + esc(m ? m.name : "") + '" placeholder="セット（60分）"></div>' +
      '<div class="field"><label for="x_price">単価（円）</label>' +
        '<input id="x_price" type="number" min="0" inputmode="numeric" value="' + (m ? m.unit_price : 0) + '"></div>' +
      '<div class="row">' +
        '<div class="field" style="flex:1"><label for="x_back">バック額（円）</label>' +
          '<input id="x_back" type="number" min="0" inputmode="numeric" value="' + (m ? m.back_amount : 0) + '"></div>' +
        '<div class="field" style="flex:1"><label for="x_rate">バック率（%）</label>' +
          '<input id="x_rate" type="number" min="0" max="100" step="0.5" value="' + (m ? Number(m.back_rate) : 0) + '"></div>' +
      "</div>" +
      '<div class="field"><label for="x_svc">サービス料</label><select id="x_svc">' +
        '<option value="1"' + (!m || m.service_apply ? " selected" : "") + ">かける</option>" +
        '<option value="0"' + (m && !m.service_apply ? " selected" : "") + ">かけない</option></select></div>" +
      '<div class="field"><label for="x_tax">消費税</label><select id="x_tax">' +
        '<option value="1"' + (!m || m.tax_apply ? " selected" : "") + ">かける</option>" +
        '<option value="0"' + (m && !m.tax_apply ? " selected" : "") + ">かけない</option></select></div>" +
      '<div class="field"><label for="x_sort">並び順</label>' +
        '<input id="x_sort" type="number" value="' + (m ? m.sort_order : 99) + '"></div>' +
      (m ? '<div class="field"><label for="x_active">状態</label><select id="x_active">' +
        '<option value="1"' + (m.is_active ? " selected" : "") + ">有効</option>" +
        '<option value="0"' + (!m.is_active ? " selected" : "") + ">停止（打てなくする）</option></select></div>" : "") +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var v = function (id) { return root.querySelector("#" + id).value; };
          var payload = {
            tenant_id: S.me.tenant_id,
            store_id: S.store.id,
            category: v("x_cat"),
            name: v("x_name").trim(),
            unit_price: Number(v("x_price")) || 0,
            back_amount: Number(v("x_back")) || 0,
            back_rate: Number(v("x_rate")) || 0,
            service_apply: v("x_svc") === "1",
            tax_apply: v("x_tax") === "1",
            sort_order: Number(v("x_sort")) || 99
          };
          if (!payload.name) { toast("名前を入れてください", "err"); return; }

          var q;
          if (m) {
            var a = root.querySelector("#x_active");
            payload.is_active = a ? a.value === "1" : true;
            q = sb.from("night_menu").update(payload).eq("id", m.id);
          } else {
            q = sb.from("night_menu").insert(payload);
          }
          q.then(function (res) {
            if (res.error) { fail(res.error); return; }
            closeModal(); toast("保存しました", "ok"); loadMenus();
          });
        });
      });
  }

  /* -------------------------------------------------------------- スタッフ */

  function loadStaff() {
    Promise.all([
      sb.from("staff").select("*").order("created_at"),
      sb.from("staff_store").select("*")
    ]).then(function (r) {
      if (r[0].error) { fail(r[0].error); return; }
      S.staff = r[0].data || [];
      var links = r[1].data || [];
      var storeName = function (id) {
        var s = S.stores.filter(function (x) { return x.id === id; })[0];
        return s ? s.name : "";
      };
      var role = { owner: "オーナー", manager: "店長", staff: "スタッフ", driver: "ドライバー" };

      $("staffTable").innerHTML =
        "<tr><th>名前</th><th>メール</th><th>権限</th><th>見られる店舗</th><th>状態</th><th></th></tr>" +
        S.staff.map(function (s) {
          var mine = links.filter(function (l) { return l.staff_id === s.id; })
            .map(function (l) { return storeName(l.store_id); });
          return "<tr" + (s.is_active ? "" : " style='opacity:.5'") + ">" +
            "<td>" + esc(s.name) + (s.id === S.me.id ? "（自分）" : "") + "</td>" +
            "<td style='font-size:12.5px;color:var(--muted)'>" + esc(s.email || "—") + "</td>" +
            "<td>" + (role[s.role] || s.role) + "</td>" +
            "<td style='font-size:12.5px'>" +
              (s.role === "owner" || s.role === "manager" ? "全店舗"
                : (mine.length ? esc(mine.join("、")) : "<span style='color:var(--bad)'>なし</span>")) + "</td>" +
            "<td>" + (s.is_active ? "有効" : "停止") + "</td>" +
            "<td>" + (s.id === S.me.id ? "" :
              '<button class="btn ghost" style="padding:6px 12px" data-staff="' + s.id + '">変更</button>') + "</td>" +
          "</tr>";
        }).join("");

      Array.prototype.forEach.call($("staffTable").querySelectorAll("button[data-staff]"), function (b) {
        b.addEventListener("click", function () { staffDialog(b.dataset.staff); });
      });
    });
  }

  function staffDialog(id) {
    var s = S.staff.filter(function (x) { return x.id === id; })[0];
    if (!s) return;
    var isOwner = S.me.role === "owner";

    modal("<h2>" + esc(s.name) + "</h2>" +
      '<div class="field"><label for="t_role">権限</label><select id="t_role"' +
        (isOwner ? "" : " disabled") + ">" +
        ["owner", "manager", "staff", "driver"].map(function (r) {
          var n = { owner: "オーナー（すべて）", manager: "店長（確定・設定まで）",
                    staff: "スタッフ（伝票のみ）", driver: "ドライバー" }[r];
          return '<option value="' + r + '"' + (s.role === r ? " selected" : "") + ">" + n + "</option>";
        }).join("") + "</select>" +
        (isOwner ? "" : '<span style="font-size:12px;color:var(--muted)">権限の変更はオーナーのみです</span>') +
      "</div>" +
      '<div class="field"><label for="t_active">状態</label><select id="t_active">' +
        '<option value="1"' + (s.is_active ? " selected" : "") + ">有効</option>" +
        '<option value="0"' + (!s.is_active ? " selected" : "") + ">停止（ログインしても何も見えなくなる）</option>" +
      "</select></div>" +
      '<div class="field"><label>見られる店舗（スタッフ・ドライバーのみ）</label>' +
        S.stores.map(function (st) {
          return '<label style="display:flex;gap:8px;align-items:center;font-size:13.5px;padding:3px 0">' +
            '<input type="checkbox" data-st="' + st.id + '"> ' + esc(st.name) + "</label>";
        }).join("") + "</div>" +
      '<div class="row" style="margin-top:16px"><button class="btn ghost" id="m_cancel">やめる</button>' +
      '<button class="btn primary" id="m_ok" style="flex:1">保存する</button></div>',
      function (root) {
        sb.from("staff_store").select("store_id").eq("staff_id", id).then(function (q) {
          (q.data || []).forEach(function (l) {
            var cb = root.querySelector('input[data-st="' + l.store_id + '"]');
            if (cb) cb.checked = true;
          });
        });

        root.querySelector("#m_cancel").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var up = { is_active: root.querySelector("#t_active").value === "1" };
          if (isOwner) up.role = root.querySelector("#t_role").value;

          sb.from("staff").update(up).eq("id", id).then(function (q) {
            if (q.error) { fail(q.error); return; }
            var want = Array.prototype.filter.call(
              root.querySelectorAll("input[data-st]"), function (cb) { return cb.checked; }
            ).map(function (cb) { return { staff_id: id, store_id: cb.dataset.st }; });

            return sb.from("staff_store").delete().eq("staff_id", id).then(function () {
              return want.length ? sb.from("staff_store").insert(want) : { error: null };
            });
          }).then(function (r) {
            if (r && r.error) { fail(r.error); return; }
            closeModal(); toast("保存しました", "ok"); loadStaff();
          });
        });
      });
  }

  /* ============================================================ 過去データ取込 */

  var IMP_KIND = {
    cast: "在籍名簿", customer: "顧客台帳",
    attendance: "出勤記録", payroll: "給与"
  };
  var IMP_STATUS = {
    uploaded: "預かりました", reviewing: "確認中", applied: "反映済み",
    canceled: "取り消し", reverted: "反映を取消"
  };

  /* --- CSVを読む（引用符・改行・BOMに対応した、小さな読み取り器） --- */
  function parseCsv(text) {
    text = text.replace(/^﻿/, "");
    var rows = [], row = [], cur = "", q = false, i;
    for (i = 0; i < text.length; i++) {
      var ch = text[i];
      if (q) {
        if (ch === '"') {
          if (text[i + 1] === '"') { cur += '"'; i++; } else { q = false; }
        } else { cur += ch; }
      } else if (ch === '"') { q = true; }
      else if (ch === ",") { row.push(cur); cur = ""; }
      else if (ch === "\n") { row.push(cur); rows.push(row); row = []; cur = ""; }
      else if (ch !== "\r") { cur += ch; }
    }
    if (cur !== "" || row.length) { row.push(cur); rows.push(row); }
    return rows.filter(function (r) { return r.some(function (c) { return c.trim() !== ""; }); });
  }

  function loadFields(kind) {
    return sb.rpc("import_fields", { p_kind: kind }).then(function (q) {
      if (q.error) { fail(q.error); return []; }
      return q.data || [];
    });
  }

  $("impTemplate").addEventListener("click", function () {
    var kind = $("impKind").value;
    loadFields(kind).then(function (fs) {
      if (!fs.length) return;
      var head = fs.map(function (f) { return f.label; }).join(",");
      var samp = fs.map(function (f) { return f.sample || ""; }).join(",");
      var csv = "﻿" + head + "\n" + samp + "\n";
      var a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
      a.download = "hinagata_" + kind + ".csv";
      a.click();
      toast("雛形をダウンロードしました。見出しはそのままで、下に行を足してください", "ok");
    });
  });

  $("impCsv").addEventListener("change", function () {
    var f = this.files && this.files[0];
    if (!f) return;
    var kind = $("impKind").value;
    var input = this;
    var fr = new FileReader();
    fr.onload = function () {
      var rows = parseCsv(String(fr.result));
      input.value = "";
      if (rows.length < 2) { toast("中身が読み取れませんでした", "err"); return; }
      loadFields(kind).then(function (fs) {
        // 見出し（日本語の項目名 or 英語の列名）を、内部の項目名に合わせます
        var byLabel = {}, byField = {};
        fs.forEach(function (x) { byLabel[x.label] = x.field; byField[x.field] = x.field; });
        var head = rows[0].map(function (h) {
          h = h.trim();
          return byLabel[h] || byField[h] || null;
        });
        var unknown = rows[0].filter(function (h, i) { return !head[i]; });
        var objs = rows.slice(1).map(function (r) {
          var o = {};
          head.forEach(function (k, i) { if (k) o[k] = (r[i] || "").trim(); });
          return o;
        });
        startImport(kind, "csv", f.name, objs, unknown);
      });
    };
    fr.readAsText(f, "UTF-8");
  });

  function startImport(kind, source, fileName, rows, unknown) {
    sb.rpc("import_create", {
      p_store: S.store.id, p_kind: kind, p_source: source,
      p_file_name: fileName, p_note: null
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var batch = q.data.id;
      if (!rows || !rows.length) { loadImports(); openImport(batch); return; }
      return sb.rpc("import_rows_add", { p_batch: batch, p_rows: rows }).then(function (r) {
        if (r.error) { fail(r.error); return; }
        if (unknown && unknown.length) {
          toast("見出しが分からない列は飛ばしました：" + unknown.join("・"), "err");
        }
        return sb.rpc("import_check", { p_batch: batch }).then(function () {
          loadImports();
          openImport(batch);
        });
      });
    });
  }

  /* --- PDF・写真を預かる --- */
  $("impFile").addEventListener("change", function () {
    var files = Array.prototype.slice.call(this.files || []);
    var input = this;
    if (!files.length) return;
    var kind = $("impKind").value;
    var isPdf = /\.pdf$/i.test(files[0].name);

    sb.rpc("import_create", {
      p_store: S.store.id, p_kind: kind, p_source: isPdf ? "pdf" : "image",
      p_file_name: files.map(function (f) { return f.name; }).join("、"), p_note: null
    }).then(function (q) {
      input.value = "";
      if (q.error) { fail(q.error); return; }
      var batch = q.data.id;
      var jobs = files.map(function (f, i) {
        var path = S.store.id + "/" + batch + "/" + (i + 1) + "_" + f.name.replace(/[^\w.\-]/g, "_");
        return sb.storage.from("imports").upload(path, f, { upsert: true }).then(function (u) {
          if (u.error) throw u.error;
          return sb.rpc("import_file_add", {
            p_batch: batch, p_path: path, p_file_name: f.name,
            p_mime: f.type || null, p_page: i + 1, p_bytes: f.size
          });
        });
      });
      Promise.all(jobs).then(function () {
        toast(files.length + "件をお預かりしました。中身を起こしてご連絡します", "ok");
        loadImports();
      }).catch(function (e) { fail(e); });
    });
  });

  /* --- 履歴 --- */
  function loadImports() {
    if (!S.store) return;
    sb.rpc("import_list", { p_store: S.store.id, p_limit: 30 }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var rows = q.data || [];
      S.impKindOf = S.impKindOf || {};
      rows.forEach(function (r) { S.impKindOf[r.id] = r.kind; });
      $("impEmpty").classList.toggle("hidden", rows.length > 0);
      if (!rows.length) { $("impTable").innerHTML = ""; return; }

      var t = "<thead><tr><th>日時</th><th>種類</th><th>もと</th><th>ファイル</th>" +
        "<th class='num'>行</th><th class='num'>OK</th><th class='num'>要直し</th>" +
        "<th>状態</th><th></th></tr></thead><tbody>";
      rows.forEach(function (r) {
        t += "<tr><td class='mono' style='font-size:12px'>" +
            new Date(r.created_at).toLocaleString("ja-JP", {
              month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }) + "</td>" +
          "<td>" + (IMP_KIND[r.kind] || r.kind) + "</td>" +
          "<td>" + (r.source === "csv" ? "CSV" : r.source === "pdf" ? "PDF" :
                    r.source === "image" ? "写真" : "手入力") +
            (r.files ? "（" + r.files + "）" : "") + "</td>" +
          "<td style='max-width:200px;overflow:hidden;text-overflow:ellipsis'>" +
            esc(r.file_name || "") + "</td>" +
          "<td class='num'>" + r.row_count + "</td>" +
          "<td class='num'>" + r.ok_count + "</td>" +
          "<td class='num'>" + (r.ng_count ? "<b>" + r.ng_count + "</b>" : "0") + "</td>" +
          "<td>" + (IMP_STATUS[r.status] || r.status) + "</td>" +
          "<td><button class='btn' data-open='" + r.id + "'>中身</button></td></tr>";
      });
      $("impTable").innerHTML = t + "</tbody>";
      Array.prototype.forEach.call($("impTable").querySelectorAll("[data-open]"), function (b) {
        b.addEventListener("click", function () { openImport(b.dataset.open); });
      });
    });
  }

  /* --- 中身の確認 --- */
  function openImport(batch) {
    S.impBatch = batch;
    $("impDetail").classList.remove("hidden");
    var kind = (S.impKindOf || {})[batch] || $("impKind").value;
    loadFields(kind).then(function (fs) {
      S.impLabels = {};
      fs.forEach(function (f) { S.impLabels[f.field] = f.label; });
      return sb.rpc("import_rows", { p_batch: batch, p_status: null });
    }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      var rows = q.data || [];
      var ok = rows.filter(function (r) { return r.status === "ok"; }).length;
      var ng = rows.filter(function (r) { return r.status === "ng"; }).length;
      var ap = rows.filter(function (r) { return r.status === "applied"; }).length;

      $("impSummary").innerHTML =
        '<div class="box' + (ng ? " warn" : "") + '">' +
        "全 " + rows.length + " 行　／　反映済み " + ap + "　／　反映できる " + ok +
        "　／　直しが要る " + ng +
        (ng ? "<br>直しが要る行は、赤い文字で理由を出しています。飛ばすこともできます。" : "") +
        "</div>";

      // 列は、実際に入っている項目から組み立てます
      var keys = [];
      rows.forEach(function (r) {
        Object.keys(r.mapped || {}).forEach(function (k) {
          if (keys.indexOf(k) < 0) keys.push(k);
        });
      });

      var lab = S.impLabels || {};
      var t = "<thead><tr><th>行</th>" +
        keys.map(function (k) { return "<th>" + esc(lab[k] || k) + "</th>"; }).join("") +
        "<th>状態</th><th></th></tr></thead><tbody>";
      rows.forEach(function (r) {
        t += "<tr><td class='mono'>" + r.line_no + "</td>" +
          keys.map(function (k) {
            return "<td style='max-width:170px;overflow:hidden;text-overflow:ellipsis'>" +
                   esc((r.mapped || {})[k] == null ? "" : (r.mapped || {})[k]) + "</td>";
          }).join("") +
          "<td>" + (r.status === "applied" ? "反映済み"
                  : r.status === "ok" ? "OK"
                  : r.status === "skip" ? "飛ばす"
                  : "<span style='color:var(--bad)'>" + esc(r.error || "要確認") + "</span>") + "</td>" +
          "<td style='white-space:nowrap'>" + (r.status === "applied" ? "" :
            "<button class='btn' data-fix='" + r.id + "'>直す</button> " +
            "<button class='btn ghost' data-skip='" + r.id + "'>飛ばす</button>") +
          "</td></tr>";
      });
      $("impRows").innerHTML = t + "</tbody>";

      Array.prototype.forEach.call($("impRows").querySelectorAll("[data-fix]"), function (b) {
        b.addEventListener("click", function () {
          var r = rows.filter(function (x) { return x.id === b.dataset.fix; })[0];
          fixRow(r, keys);
        });
      });
      Array.prototype.forEach.call($("impRows").querySelectorAll("[data-skip]"), function (b) {
        b.addEventListener("click", function () {
          sb.rpc("import_row_set", { p_row: b.dataset.skip, p_mapped: null, p_status: "skip" })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              openImport(batch);
            });
        });
      });
    });
  }

  function fixRow(r, keys) {
    if (!r) return;
    modal(
      "<h3>" + r.line_no + " 行目を直す</h3>" +
      (r.error ? "<div class='box bad'>" + esc(r.error) + "</div>" : "") +
      keys.map(function (k) {
        return "<label class='field'><span>" + esc((S.impLabels || {})[k] || k) + "</span>" +
          "<input data-k='" + esc(k) + "' value='" +
          esc((r.mapped || {})[k] == null ? "" : (r.mapped || {})[k]) + "'></label>";
      }).join("") +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button>" +
      "<button class='btn primary' id='m_ok'>直して、たしかめる</button></div>",
      function (root) {
        root.querySelector("#m_no").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          var m = {};
          Array.prototype.forEach.call(root.querySelectorAll("[data-k]"), function (i) {
            m[i.dataset.k] = i.value.trim();
          });
          sb.rpc("import_row_set", { p_row: r.id, p_mapped: m, p_status: "new" })
            .then(function (q) {
              if (q.error) { fail(q.error); return; }
              return sb.rpc("import_check", { p_batch: S.impBatch });
            })
            .then(function () { closeModal(); openImport(S.impBatch); });
        });
      });
  }

  $("impCheck").addEventListener("click", function () {
    if (!S.impBatch) return;
    sb.rpc("import_check", { p_batch: S.impBatch }).then(function (q) {
      if (q.error) { fail(q.error); return; }
      openImport(S.impBatch); loadImports();
    });
  });

  $("impApply").addEventListener("click", function () {
    if (!S.impBatch) return;
    modal(
      "<h3>反映します</h3>" +
      "<p>「OK」になっている行だけを、本番のデータに書き込みます。<br>" +
      "同じお名前・同じ期間のものは上書きされ、二重には増えません。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='m_no'>やめる</button>" +
      "<button class='btn primary' id='m_ok'>反映する</button></div>",
      function (root) {
        root.querySelector("#m_no").addEventListener("click", closeModal);
        root.querySelector("#m_ok").addEventListener("click", function () {
          sb.rpc("import_apply", { p_batch: S.impBatch }).then(function (q) {
            if (q.error) { fail(q.error); return; }
            var d = (q.data && q.data[0]) || {};
            closeModal();
            toast((d.applied || 0) + "行を反映しました" +
                  (d.failed ? "／" + d.failed + "行は直しが要ります" : ""),
                  d.failed ? "err" : "ok");
            openImport(S.impBatch); loadImports();
          });
        });
      });
  });

  $("impCancelBtn").addEventListener("click", function () {
    if (!S.impBatch) return;
    sb.rpc("import_cancel", { p_batch: S.impBatch, p_reason: "画面から取り消し" })
      .then(function (q) {
        if (q.error) { fail(q.error); return; }
        toast("取り消しました", "ok");
        $("impDetail").classList.add("hidden");
        S.impBatch = null;
        loadImports();
      });
  });


  /* データベースの関数を呼びます（失敗したらお知らせを出して null を返します） */
  function rpcCall(name, args) {
    return sb.rpc(name, args || {}).then(function (q) {
      if (q.error) { fail(q.error); return null; }
      return q.data;
    });
  }

  /* ============================================================ AI・送信 */

  function loadAi() {
    rpcCall("ai_settings_get", {}).then(function (s2) {
      if (!s2) return;
      S.ai = s2;
      $("ai_p").value = s2.ai_provider || "off";
      $("ai_m").value = s2.ai_model || "";
      $("ai_t").value = s2.ai_tone || "polite";
      $("ml_p").value = s2.mail_provider || "off";
      $("ml_f").value = s2.mail_from || "";
      $("ml_n").value = s2.mail_from_name || "";
      $("ln_e").value = s2.line_enabled ? "1" : "0";
      $("ml_s").textContent = s2.has_mail_key ? "登録ずみです" : "まだ登録されていません";
      $("ln_s").textContent = s2.has_line_token ? "登録ずみです" : "まだ登録されていません";

      var can = !!s2.can_edit;
      ["ai_p", "ai_m", "ai_t", "ml_p", "ml_f", "ml_n", "ml_k", "ln_e", "ln_k", "aiSave"]
        .forEach(function (id) { $(id).disabled = !can; });
      if (!can) {
        toast("この設定を変えられるのは、オーナーの方だけです");
      }
      loadOutbox();
    });
  }

  $("aiSave").addEventListener("click", function () {
    rpcCall("ai_settings_set", {
      p_ai_provider: $("ai_p").value,
      p_ai_model: $("ai_m").value.trim(),
      p_ai_tone: $("ai_t").value,
      p_mail_provider: $("ml_p").value,
      p_mail_from: $("ml_f").value.trim(),
      p_mail_from_name: $("ml_n").value.trim(),
      p_line_enabled: $("ln_e").value === "1"
    }).then(function (r) {
      if (!r) return;
      var jobs = [];
      if ($("ml_k").value.trim()) {
        jobs.push(rpcCall("secret_set", {
          p_key: $("ml_p").value === "sendgrid" ? "sendgrid_api_key" : "resend_api_key",
          p_value: $("ml_k").value.trim()
        }));
      }
      if ($("ln_k").value.trim()) {
        jobs.push(rpcCall("secret_set", {
          p_key: "line_channel_token", p_value: $("ln_k").value.trim()
        }));
      }
      Promise.all(jobs).then(function () {
        $("ml_k").value = ""; $("ln_k").value = "";
        toast("保存しました", "ok");
        loadAi();
      });
    });
  });

  /* ---- 送信箱 ---- */

  var OB = { queued: "送信待ち", sent: "送りました", failed: "失敗", canceled: "取り消し" };

  $("obReload").addEventListener("click", loadOutbox);

  function loadOutbox() {
    if (!S.store) return;
    rpcCall("outbox_list", { p_store: S.store.id, p_status: null }).then(function (rows) {
      rows = rows || [];
      $("obEmpty").classList.toggle("hidden", rows.length > 0);
      if (!rows.length) { $("obTable").innerHTML = ""; return; }
      $("obTable").innerHTML =
        "<thead><tr><th>いつ</th><th>方法</th><th>だれに</th><th>件名</th>" +
        "<th>状態</th><th class='num'>回数</th><th>うまくいかなかった理由</th>" +
        "</tr></thead><tbody>" +
        rows.map(function (o) {
          return "<tr><td class='mono' style='font-size:12px'>" +
              new Date(o.created_at).toLocaleString("ja-JP",
                { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }) +
            "</td>" +
            "<td>" + (o.channel === "line" ? "LINE" : "メール") + "</td>" +
            "<td>" + esc(o.subject_name || "") +
              "<br><span class='mono' style='font-size:11px;color:var(--muted)'>" +
              esc(o.to_addr) + "</span></td>" +
            "<td>" + esc(o.subject || "") + "</td>" +
            "<td>" + (OB[o.status] || o.status) + "</td>" +
            "<td class='num'>" + o.tries + "</td>" +
            "<td style='color:var(--bad);font-size:12px;max-width:260px'>" +
              esc(o.error || "") + "</td></tr>";
        }).join("") + "</tbody>";
    });
  }

  $("obSend").addEventListener("click", function () {
    toast("送信のしくみに頼んでいます…");
    callFn("send-outbox", {}).then(function (r) {
      if (!r) return;
      toast((r.sent || 0) + "件を送りました" +
        (r.failed ? "／" + r.failed + "件は送れませんでした" : ""),
        r.failed ? "err" : "ok");
      loadOutbox();
    });
  });

  $("obRetry").addEventListener("click", function () {
    rpcCall("outbox_retry", { p_id: null }).then(function (n) {
      if (n === null) return;
      toast(n + "件を送信待ちに戻しました", "ok");
      loadOutbox();
    });
  });


  /* -------------------------------------------------------------- 起動 */

  sb.auth.onAuthStateChange(function (ev) {
    if (ev === "SIGNED_OUT") showLogin();
  });

  boot();
})();
