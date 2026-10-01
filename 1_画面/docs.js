/* ============================================================================
   だんどりシリーズ / 届出・許可証、LINEの登録
   docs.js
   置き場所： サイトのルート（docs.html と同じ階層）
   ============================================================================ */
(function () {
  "use strict";

  var $ = K.$, esc = K.esc;

  /* ==================================================== 届出・許可証 */

  var DOC_CATS = [
    ["license", "許可・免許"], ["notify", "届出"], ["insurance", "保険"],
    ["contract", "契約"], ["inspection", "点検・検査"], ["other", "そのほか"]
  ];

  function docCatLabel(c) {
    var h = DOC_CATS.filter(function (x) { return x[0] === c; })[0];
    return h ? h[1] : c;
  }

  function loadDocs() {
    Promise.all([
      K.rpc("store_doc_list", { p_store: K.S.store.id, p_category: null, p_all: true }),
      K.rpc("store_doc_alerts", { p_store: K.S.store.id })
    ]).then(function (out) {
      var rows = out[0] || [], al = out[1] || [];

      $("adAlert").innerHTML = !al.length
        ? "<div class='box'>期限が近い書類はありません。</div>"
        : "<div class='box warn'><b>期限のお知らせ</b><ul>" +
          al.map(function (a) { return "<li>" + esc(a.message) + "</li>"; }).join("") +
          "</ul></div>";

      if (!rows.length) {
        $("adTable").innerHTML = "";
        return;
      }
      var body = rows.map(function (d) {
        return "<tr class='" + (d.state === "expired" ? "bad" : "") +
               (d.is_active ? "" : " off") + "'>" +
          "<td>" + esc(d.category_label) + "</td>" +
          "<td><b>" + esc(d.name) + "</b>" +
            (d.doc_no ? "<br><small>" + esc(d.doc_no) + "</small>" : "") +
            (d.must_post ? "<br><small>掲示が要ります</small>" : "") + "</td>" +
          "<td>" + esc(d.issuer || "") + "</td>" +
          "<td class='nw'>" + (d.expires_on ? K.md(d.expires_on) : "期限なし") +
            (d.days_left != null
              ? "<br><small>" + (d.days_left < 0
                  ? (-d.days_left) + "日すぎ" : "あと" + d.days_left + "日") + "</small>"
              : "") + "</td>" +
          "<td class='nw'>" + esc(d.visibility_label) + "</td>" +
          "<td class='num'>" + (d.files || "") + "</td>" +
          "<td>" + (d.warn ? K.pill(d.warn, d.state === "expired" ? "bad" : "warn") : "") + "</td>" +
          "<td class='right nw'>" +
            "<button class='btn small' data-df='" + d.id + "'>控え</button> " +
            "<button class='btn small' data-de='" + d.id + "'>直す</button>" +
          "</td></tr>";
      });
      $("adTable").innerHTML = K.table(
        ["種類", "書類", "出しているところ", "期限", "見せる範囲",
         { label: "控え", num: true }, "", ""], body);

      K.bind($("adTable"), "[data-de]", "de", function (id) { editDoc(id, rows); });
      K.bind($("adTable"), "[data-df]", "df", function (id) { docFiles(id, rows); });
    });
  }

  function docForm(d) {
    return "<h2 style='margin-top:0'>" + (d ? "書類を直す" : "書類を足す") + "</h2>" +
      "<div class='grid2'>" +
      "<label class='field'><span>書類の名前</span><input id='o_name' value='" +
        esc(d ? d.name : "") + "'></label>" +
      "<label class='field'><span>種類</span><select id='o_cat'>" +
        DOC_CATS.map(function (c) {
          return "<option value='" + c[0] + "'" +
                 (d && d.category === c[0] ? " selected" : "") + ">" + c[1] + "</option>";
        }).join("") + "</select></label>" +
      "<label class='field'><span>番号（許可番号・証券番号）</span><input id='o_no' value='" +
        esc(d ? (d.doc_no || "") : "") + "'></label>" +
      "<label class='field'><span>名義</span><input id='o_holder' value='" +
        esc(d ? (d.holder || "") : "") + "'></label>" +
      "<label class='field'><span>出しているところ</span><input id='o_issuer' value='" +
        esc(d ? (d.issuer || "") : "") + "'></label>" +
      "<label class='field'><span>交付日</span><input id='o_issued' type='date' value='" +
        esc(d ? (d.issued_on || "") : "") + "'></label>" +
      "<label class='field'><span>期限（ないものは空のまま）</span>" +
        "<input id='o_exp' type='date' value='" +
        esc(d ? (d.expires_on || "") : "") + "'></label>" +
      "<label class='field'><span>何日前からお知らせするか</span>" +
        "<input id='o_lead' type='number' value='" +
        (d ? d.renew_lead_days : 60) + "'></label>" +
      "<label class='field'><span>見せる範囲</span><select id='o_vis'>" +
        "<option value='boss'" + (d && d.visibility === "boss" ? " selected" : "") +
          ">店長以上だけ</option>" +
        "<option value='staff'" + (d && d.visibility === "staff" ? " selected" : "") +
          ">みんな</option></select></label>" +
      "</div>" +
      "<label class='row' style='gap:8px;margin:8px 0'>" +
        "<input type='checkbox' id='o_post'" +
        (d && d.must_post ? " checked" : "") + "><span>店内に掲示が要る書類</span></label>" +
      "<label class='field'><span>覚え書き</span><input id='o_note' value='" +
        esc(d ? (d.note || "") : "") + "'></label>" +
      (d ? "<label class='row' style='gap:8px;margin-top:8px'>" +
           "<input type='checkbox' id='o_act'" + (d.is_active ? " checked" : "") + ">" +
           "<span>いま使っている</span></label>" : "") +
      "<p class='hint'>許可証には、代表者名や住所が入っていることがあります。" +
      "はじめは「店長以上だけ」にしてあります。" +
      "店内掲示が要るものだけ「みんな」に変えてください。</p>" +
      "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
      "<button class='btn ghost' id='f_no'>やめる</button>" +
      "<button class='btn primary' id='f_ok'>保存</button></div>";
  }

  function saveDoc(id) {
    K.rpc("store_doc_save", {
      p_store: K.S.store.id, p_id: id || null,
      p_name: $("o_name").value.trim(),
      p_category: $("o_cat").value,
      p_no: $("o_no").value.trim() || null,
      p_holder: $("o_holder").value.trim() || null,
      p_issuer: $("o_issuer").value.trim() || null,
      p_issued: $("o_issued").value || null,
      p_expires: $("o_exp").value || null,
      p_lead: Number($("o_lead").value || 60),
      p_visibility: $("o_vis").value,
      p_must_post: $("o_post").checked,
      p_note: $("o_note").value.trim() || null,
      p_active: $("o_act") ? $("o_act").checked : null
    }).then(function (r) {
      if (!r) return;
      K.closeModal();
      K.toast("保存しました");
      loadDocs();
    });
  }

  function newDoc() {
    K.modal(docForm(null), function (root) {
      root.querySelector("#f_no").addEventListener("click", K.closeModal);
      root.querySelector("#f_ok").addEventListener("click", function () { saveDoc(null); });
    });
  }

  function editDoc(id, rows) {
    var d = rows.filter(function (x) { return x.id === id; })[0];
    K.modal(docForm(d), function (root) {
      root.querySelector("#f_no").addEventListener("click", K.closeModal);
      root.querySelector("#f_ok").addEventListener("click", function () { saveDoc(id); });
    });
  }

  /* ---- 控え（写真・PDF）---- */

  function docFiles(id, rows) {
    var d = rows.filter(function (x) { return x.id === id; })[0];
    K.rpc("store_doc_files", { p_doc: id }).then(function (files) {
      files = files || [];
      var h = "<h2 style='margin-top:0'>" + esc(d.name) + " の控え</h2>" +
        (d.expires_on
          ? "<p>期限： " + K.md(d.expires_on) + "</p>"
          : "<p class='hint'>期限のない書類です。</p>") +
        "<div id='fx_list'></div>" +
        "<h3>取りこむ</h3>" +
        "<input id='fx_file' type='file' accept='image/*,.pdf' capture='environment'>" +
        "<p class='hint'>スマホなら、その場で撮った写真をそのまま入れられます。" +
        "1枚に収まらない書類は、何枚でも足せます。</p>" +
        "<div class='row' style='justify-content:flex-end;margin-top:8px'>" +
        "<button class='btn' id='fx_up'>この1枚を入れる</button></div>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn primary' id='f_no'>とじる</button></div>";

      K.modal(h, function (root) {
        drawFiles(files, id, rows);
        root.querySelector("#f_no").addEventListener("click", K.closeModal);
        root.querySelector("#fx_up").addEventListener("click", function () {
          uploadDoc(id, rows);
        });
      });
    });
  }

  function drawFiles(files, id, rows) {
    if (!files.length) {
      $("fx_list").innerHTML = K.empty("まだ控えがありません。");
      return;
    }
    $("fx_list").innerHTML = "<table class='mini'>" +
      files.map(function (f) {
        return "<tr><td>" + (f.page || 1) + "枚目</td>" +
          "<td>" + esc(f.file_name || "") + "</td>" +
          "<td><small>" + new Date(f.uploaded_at).toLocaleDateString("ja-JP") +
            "　" + esc(f.uploaded_name || "") + "</small></td>" +
          "<td class='right'>" +
            "<button class='btn small' data-see='" + esc(f.path) + "'>ひらく</button> " +
            "<button class='btn small' data-rm='" + f.id + "'>消す</button></td></tr>";
      }).join("") + "</table>";

    K.bind($("fx_list"), "[data-see]", "see", function (path) {
      K.sb.storage.from("docs").createSignedUrl(path, 300).then(function (r) {
        if (r.error) { K.fail(r.error); return; }
        window.open(r.data.signedUrl, "_blank", "noopener");
      });
    });
    K.bind($("fx_list"), "[data-rm]", "rm", function (fid) {
      K.rpc("store_doc_file_remove", { p_id: fid }).then(function (ok) {
        if (!ok) return;
        K.toast("消しました");
        docFiles(id, rows);
      });
    });
  }

  function uploadDoc(id, rows) {
    var f = $("fx_file").files[0];
    if (!f) { K.toast("ファイルをえらんでください", "err"); return; }
    if (f.size > 20 * 1024 * 1024) {
      K.toast("20MBまでにしてください。写真なら、もう少し小さく撮ってください", "err");
      return;
    }
    var ext = (f.name.split(".").pop() || "bin").toLowerCase();
    var path = K.S.me.tenant_id + "/" + K.S.store.id + "/" + id + "/" +
               Date.now() + "." + ext;

    K.toast("入れています…");
    K.sb.storage.from("docs").upload(path, f, { contentType: f.type || undefined })
      .then(function (r) {
        if (r.error) { K.fail(r.error); return; }
        return K.rpc("store_doc_file_add", {
          p_doc: id, p_path: path, p_file_name: f.name,
          p_mime: f.type || null, p_bytes: f.size,
          p_page: null
        }).then(function (x) {
          if (!x) return;
          K.toast("入れました");
          docFiles(id, rows);
          loadDocs();
        });
      });
  }

  /* ==================================================== LINEの登録 */

  function loadLine() {
    var qrUrl = (K.cfg && K.cfg.lineAddUrl) || "";
    var qrImg = (K.cfg && K.cfg.lineQrImage) || "";
    var qrHtml = (qrUrl || qrImg)
      ? "<div class='box linejoin'><div class='ljtext'>" +
          "<b>お店のLINEを友だち追加</b>" +
          "<p class='hint'>スタッフさんに、このQRコードを読んでもらってください。" +
          "スマホでこの画面を見ているときは、下のボタンからでも追加できます。</p>" +
          (qrUrl ? "<p><a class='btn primary' href='" + qrUrl +
            "' target='_blank' rel='noopener'>友だち追加</a></p>" +
            "<p class='hint mono ljurl'><small>" + qrUrl + "</small></p>" : "") +
        "</div>" +
        (qrImg ? "<img class='ljimg' src='" + qrImg +
          "' alt='LINE友だち追加のQRコード'>" : "") +
        "</div>"
      : "";

    $("lnHelp").innerHTML = qrHtml +
      "<div class='box'><b>やりかた</b>" +
      "<ol>" +
      "<li>スタッフさんに、お店のLINE公式アカウントを友だち追加してもらいます</li>" +
      "<li>追加されると、下の一覧に出ます</li>" +
      "<li>名簿のだれかをえらんで、結びつけます</li>" +
      "</ol>" +
      "<p class='hint'>結びつけると、その方はLINEのトークに" +
      "「10/1 10-17」のように送るだけでシフト希望が出せます。" +
      "給与明細や、確定シフトのお知らせも、そのLINEに届きます。</p>" +
      "<p class='hint'>ここに出てこないときは、" +
      "「AI・送信」でLINEの鍵（チャネルシークレット／アクセストークン）が" +
      "入っているか、LINEの管理画面でWebhookのアドレスが入っているかを見てください。</p>" +
      "</div>";

    K.rpc("line_pending", { p_store: K.S.store.id }).then(function (rows) {
      rows = rows || [];
      if (!rows.length) {
        $("lnTable").innerHTML = "";
        return;
      }
      var body = rows.map(function (l) {
        return "<tr>" +
          "<td>" + (l.picture_url
            ? "<img src='" + esc(l.picture_url) + "' alt='' " +
              "style='width:36px;height:36px;border-radius:50%'>" : "") + "</td>" +
          "<td><b>" + esc(l.display_name || "（名前なし）") + "</b></td>" +
          "<td class='mono'><small>" + esc(l.line_user_id) + "</small></td>" +
          "<td>" + new Date(l.first_seen_at).toLocaleDateString("ja-JP") + "</td>" +
          "<td class='right'><button class='btn small primary' data-lnk='" + l.id +
            "'>だれのか決める</button></td></tr>";
      });
      $("lnTable").innerHTML = K.table(
        ["", "LINEの表示名", "ID（一部）", "はじめて来た日", ""], body);

      K.bind($("lnTable"), "[data-lnk]", "lnk", function (lid) {
        K.rpc("shift_people", { p_store: K.S.store.id }).then(function (ppl) {
          ppl = ppl || [];
          var h = "<h2 style='margin-top:0'>だれのLINEですか</h2>" +
            "<div class='picklist'>" +
            ppl.map(function (p) {
              return "<button class='pickrow' data-p='" + p.subject_kind + "|" +
                p.subject_id + "'><span>" + esc(p.name) + "</span>" +
                "<span class='num'>" + esc(p.job_label || "") + "</span></button>";
            }).join("") + "</div>" +
            "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
            "<button class='btn ghost' id='f_no'>やめる</button></div>";
          K.modal(h, function (root) {
            root.querySelector("#f_no").addEventListener("click", K.closeModal);
            K.bind(root, "[data-p]", "p", function (v) {
              var q = v.split("|");
              K.rpc("line_link_set", {
                p_id: lid, p_kind: q[0], p_subject: q[1]
              }).then(function (r) {
                if (!r) return;
                K.closeModal();
                K.toast(r.message || "登録しました");
                loadLine();
              });
            });
          });
        });
      });
    });
  }


  /* ------------------------------------------------------------ 起動 */

  var VIEWS = ["doc", "line"];

  function switchView(v) {
    VIEWS.forEach(function (n) {
      var el = $("view-" + n);
      if (el) el.classList.toggle("hidden", n !== v);
    });
    Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
      b.setAttribute("aria-selected", String(b.dataset.view === v));
    });
    if (v === "doc") loadDocs();
    if (v === "line") loadLine();
  }

  Array.prototype.forEach.call(document.querySelectorAll("nav.tabs button"), function (b) {
    b.addEventListener("click", function () { switchView(b.dataset.view); });
  });

  K.wireLogin();
  K.boot(function () { switchView("doc"); });

  $("adNew").addEventListener("click", newDoc);
  $("adReload").addEventListener("click", loadDocs);
  $("adSeed").addEventListener("click", function () {
    K.rpc("store_doc_seed", { p_store: K.S.store.id, p_industry: null })
      .then(function (n) {
        if (n == null) return;
        K.toast("ひな形を入れました（ぜんぶで " + n + "件）");
        loadDocs();
      });
  });
  $("lnReload").addEventListener("click", loadLine);
})();
