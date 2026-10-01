/* ============================================================================
   だんどりシリーズ / シフト希望・承認（お店の画面）
   shiftwish.js
   置き場所： サイトのルート（shiftwish.html と同じ階層）

   募集を開く → 出てきた希望を見る → 承認して確定 → 本人に返す。
   ナイト・キャスト・フードのどれでも、同じように動きます。
   ============================================================================ */
(function () {
  "use strict";

  var $ = K.$, esc = K.esc, stat = K.stat;

  /* ============================================================ 希望・承認 */

  var PERIODS = [];
  var PEOPLE = [];

  function loadPeriods(keep) {
    return K.rpc("shift_period_list", { p_store: K.S.store.id, p_limit: 12 })
      .then(function (rows) {
        PERIODS = rows || [];
        if (!PERIODS.length) {
          $("pSel").innerHTML = "<option value=''>募集がありません</option>";
          $("pHead").innerHTML = K.empty(
            "まだ募集がありません。「つぎの募集を開く」を押してください。");
          $("pTable").innerHTML = "";
          return;
        }
        $("pSel").innerHTML = PERIODS.map(function (p) {
          return "<option value='" + p.id + "'>" +
            K.md(p.period_from) + "〜" + K.md(p.period_to) +
            "（" + p.status_label + " " + p.submitted + "/" + p.people + "）</option>";
        }).join("");
        if (keep && PERIODS.filter(function (p) { return p.id === keep; }).length) {
          $("pSel").value = keep;
        }
        loadWish();
      });
  }

  function curPeriod() {
    var id = $("pSel").value;
    return PERIODS.filter(function (p) { return p.id === id; })[0];
  }

  function loadWish() {
    var p = curPeriod();
    if (!p) return;
    K.rpc("shift_people", { p_store: K.S.store.id }).then(function (r) {
      PEOPLE = r || [];
    });
    K.rpc("wish_board", { p_period: p.id }).then(function (rows) {
      rows = rows || [];
      var sub = rows.filter(function (r) { return r.status === "submitted"; }).length;
      var app2 = rows.filter(function (r) { return r.status === "approved"; }).length;
      var yet = rows.filter(function (r) { return r.status === "draft"; }).length;

      $("pHead").innerHTML =
        "<div class='stats'>" +
        stat("対象", rows.length + " 名") +
        stat("出ています", sub + " 名", sub ? "warn" : "") +
        stat("確定ずみ", app2 + " 名") +
        stat("まだ", yet + " 名", yet ? "warn" : "") +
        "</div>" +
        "<div class='row' style='justify-content:flex-end;margin-bottom:8px'>" +
        (p.status === "open"
          ? "<button class='btn ghost' id='pClose'>受付を締め切る</button>"
          : "<button class='btn ghost' id='pOpen'>受付を開け直す</button>") +
        "</div>" +
        (p.deadline_at
          ? "<p class='hint'>締切： " +
            new Date(p.deadline_at).toLocaleString("ja-JP",
              { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }) +
            "</p>"
          : "");

      var c = $("pClose") || $("pOpen");
      if (c) c.addEventListener("click", function () {
        K.rpc("shift_period_status", {
          p_period: p.id, p_status: p.status === "open" ? "closed" : "open"
        }).then(function (r) { if (r) loadPeriods(p.id); });
      });

      var body = rows.map(function (r) {
        return "<tr>" +
          "<td><b>" + esc(r.name) + "</b><br><small>" + esc(r.job_label || "") + "</small></td>" +
          "<td>" + esc(r.status_label) + "</td>" +
          "<td>" + esc(r.source_label) + "</td>" +
          "<td class='num'>" + r.days + "</td>" +
          "<td class='num'>" + (r.ng_days || "") + "</td>" +
          "<td>" + (r.submitted_at
            ? new Date(r.submitted_at).toLocaleString("ja-JP",
                { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })
            : "—") + "</td>" +
          "<td>" + (r.warn ? K.pill(r.warn) : "") +
            (r.note ? "<small>" + esc(r.note) + "</small>" : "") + "</td>" +
          "<td class='right'>" +
            "<button class='btn small' data-w='" + r.subject_kind + "|" + r.subject_id +
              "|" + (r.wish_id || "") + "'>中身</button> " +
            "<button class='btn small' data-lk='" + r.subject_kind + "|" + r.subject_id +
              "'>リンク</button>" +
          "</td></tr>";
      });
      $("pTable").innerHTML = K.table(
        ["スタッフ", "ようす", "出し方", { label: "日数", num: true },
         { label: "休み", num: true }, "出した日時", "", ""], body);

      K.bind($("pTable"), "[data-w]", "w", function (v) {
        var q = v.split("|");
        openWish(p, q[0], q[1], q[2]);
      });
      K.bind($("pTable"), "[data-lk]", "lk", function (v) {
        var q = v.split("|");
        showLink(p.id, q[0], q[1]);
      });
    });
  }

  function openWish(p, kind, sid, wid) {
    if (!wid) {
      /* まだ出ていない方は、お店の端末で代わりに入れます */
      editWish(p, kind, sid, null);
      return;
    }
    K.rpc("wish_detail", { p_wish: wid }).then(function (d) {
      if (!d) return;
      var list = (d.days || []).map(function (x) {
        return "<tr><td>" + K.md(x.date) + "</td>" +
          "<td>" + kindLabel(x.kind) + "</td>" +
          "<td>" + (x.kind === "ng" ? "—"
                    : esc(x.slot_name || "") + " " +
                      esc(x.from || "") + "〜" + esc(x.to || "")) + "</td>" +
          "<td><small>" + esc(x.note || "") + "</small></td></tr>";
      }).join("");

      K.modal(
        "<h2 style='margin-top:0'>" + esc(d.name) + " さんの希望</h2>" +
        (d.note ? "<div class='box'>" + esc(d.note) + "</div>" : "") +
        "<div class='tablewrap'><table class='mini'>" +
        "<thead><tr><th>日</th><th>希望</th><th>時間</th><th></th></tr></thead>" +
        "<tbody>" + list + "</tbody></table></div>" +
        ((d.fixed || []).length
          ? "<h3>いま確定しているぶん</h3><table class='mini'>" +
            d.fixed.map(function (f) {
              return "<tr><td>" + K.md(f.date) + "</td><td>" +
                esc(f.from || "") + "〜" + esc(f.to || "") + "</td></tr>";
            }).join("") + "</table>"
          : "") +
        "<p class='hint'>承認すると、シフト表に入ります。" +
        "「入れます」と「入りたい」の日だけが入り、「休みたい」の日は入りません。</p>" +
        "<div class='row' style='justify-content:space-between;margin-top:16px;flex-wrap:wrap'>" +
        "<button class='btn ghost' id='w_edit'>お店で直す</button>" +
        "<div class='row'>" +
        "<button class='btn ghost' id='w_ret'>差し戻す</button>" +
        "<button class='btn ghost' id='f_no'>とじる</button>" +
        "<button class='btn primary' id='w_ok'>承認して確定</button>" +
        "</div></div>",
        function (root) {
          root.querySelector("#f_no").addEventListener("click", K.closeModal);
          root.querySelector("#w_edit").addEventListener("click", function () {
            K.closeModal();
            editWish(p, kind, sid, d);
          });
          root.querySelector("#w_ok").addEventListener("click", function () {
            K.rpc("wish_approve", { p_wish: wid, p_note: null }).then(function (r) {
              if (!r) return;
              K.closeModal();
              K.toast(r.message || "確定しました");
              askSend(wid, d.name);
              loadPeriods(p.id);
            });
          });
          root.querySelector("#w_ret").addEventListener("click", function () {
            K.modal(
              "<h2 style='margin-top:0'>差し戻す</h2>" +
              "<p>どう直してほしいかを、ひとこと書いてください。そのまま本人に届きます。</p>" +
              "<label class='field'><span>ひとこと</span>" +
              "<textarea id='r_note' rows='3' placeholder='10/3は人が足りないので、夕方だけでも入れませんか'></textarea></label>" +
              "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
              "<button class='btn ghost' id='f_no'>やめる</button>" +
              "<button class='btn primary' id='f_ok'>差し戻す</button></div>",
              function (r2) {
                r2.querySelector("#f_no").addEventListener("click", K.closeModal);
                r2.querySelector("#f_ok").addEventListener("click", function () {
                  K.rpc("wish_return", {
                    p_wish: wid, p_note: $("r_note").value
                  }).then(function (x) {
                    if (!x) return;
                    K.closeModal();
                    K.toast(x.message || "差し戻しました");
                    loadPeriods(p.id);
                  });
                });
              });
          });
        });
    });
  }

  function kindLabel(k) {
    return { ok: "入れます", want: "入りたい", ng: "休みたい" }[k] || k;
  }

  /* お店の端末で、代わりに入れる */
  function editWish(p, kind, sid, d) {
    Promise.resolve().then(function () {
      return K.sb.from("shift_slot").select("*").eq("store_id", K.S.store.id)
        .eq("is_active", true).order("sort_no");
    }).then(function (q) {
      var slots = q.data || [];
      var picked = {};
      ((d && d.days) || []).forEach(function (x) {
        picked[x.date] = { kind: x.kind, slot_id: x.slot_id, from: x.from, to: x.to };
      });

      var name = (d && d.name) || (PEOPLE.filter(function (x) {
        return x.subject_id === sid;
      })[0] || {}).name || "";

      function grid() {
        var from = new Date(p.period_from + "T00:00:00");
        var to = new Date(p.period_to + "T00:00:00");
        var h = "<div class='wishgrid'>";
        var dd = new Date(from);
        while (dd <= to) {
          var key = K.ymd(dd);
          var x = picked[key];
          h += "<button class='wishcell " + (x ? x.kind : "") + "' data-d='" + key + "'>" +
               "<b>" + (dd.getMonth() + 1) + "/" + dd.getDate() + "</b>" +
               "<span>" + ["日","月","火","水","木","金","土"][dd.getDay()] + "</span>" +
               "<small>" + (x ? (x.kind === "ng" ? "休み"
                  : (slotOf(slots, x.slot_id) || (x.from ? x.from + "〜" : "おまかせ")))
                  : "") + "</small></button>";
          dd.setDate(dd.getDate() + 1);
        }
        return h + "</div>";
      }

      function redraw(root) {
        root.querySelector("#w_grid").innerHTML = grid();
        K.bind(root.querySelector("#w_grid"), "[data-d]", "d", function (key) {
          cyclePick(key, slots, picked, function () { redraw(root); });
        });
      }

      K.modal(
        "<h2 style='margin-top:0'>" + esc(name) + " さんの希望（お店で入力）</h2>" +
        "<p class='hint'>日にちを押すたびに、" +
        "入れます → 入りたい → 休みたい → なし　と変わります。" +
        "長く押すと、時間帯をえらべます。</p>" +
        "<div id='w_grid'></div>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn ghost' id='f_no'>やめる</button>" +
        "<button class='btn primary' id='f_ok'>保存</button></div>",
        function (root) {
          redraw(root);
          root.querySelector("#f_no").addEventListener("click", K.closeModal);
          root.querySelector("#f_ok").addEventListener("click", function () {
            var arr = Object.keys(picked).sort().map(function (k) {
              var x = picked[k];
              return { date: k, kind: x.kind, slot_id: x.slot_id || null,
                       from: x.from || null, to: x.to || null };
            });
            K.rpc("wish_set_by_staff", {
              p_period: p.id, p_kind: kind, p_id: sid, p_days: arr
            }).then(function (r) {
              if (!r) return;
              K.closeModal();
              K.toast("保存しました");
              loadPeriods(p.id);
            });
          });
        });
    });
  }

  function slotOf(slots, id) {
    if (!id) return null;
    var s = slots.filter(function (x) { return x.id === id; })[0];
    return s ? s.name : null;
  }

  function cyclePick(key, slots, picked, then) {
    var x = picked[key];
    if (!x) {
      picked[key] = { kind: "ok", slot_id: slots.length ? slots[0].id : null,
                      from: slots.length ? slots[0].start_time.slice(0, 5) : null,
                      to: slots.length ? slots[0].end_time.slice(0, 5) : null };
    } else if (x.kind === "ok") {
      /* 同じ日をもう一度押すと、つぎの時間帯へ。最後まで行ったら「入りたい」へ */
      var i = slots.map(function (s) { return s.id; }).indexOf(x.slot_id);
      if (i >= 0 && i < slots.length - 1) {
        var s2 = slots[i + 1];
        picked[key] = { kind: "ok", slot_id: s2.id,
                        from: s2.start_time.slice(0, 5), to: s2.end_time.slice(0, 5) };
      } else {
        picked[key] = { kind: "want", slot_id: x.slot_id, from: x.from, to: x.to };
      }
    } else if (x.kind === "want") {
      picked[key] = { kind: "ng" };
    } else {
      delete picked[key];
    }
    then();
  }

  /* 本人用リンク */
  function showLink(pid, kind, sid) {
    K.rpc("wish_link", {
      p_period: pid, p_kind: kind, p_id: sid, p_base: baseUrl()
    }).then(function (j) {
      if (!j) return;
      K.modal(
        "<h2 style='margin-top:0'>" + esc(j.name) + " さんの提出リンク</h2>" +
        "<p class='hint'>下の文をまるごとコピーして、LINEやメールでお送りください。</p>" +
        "<textarea id='lk_text' rows='10' style='width:100%'>" + esc(j.message) + "</textarea>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn ghost' id='lk_copy'>コピー</button>" +
        "<button class='btn primary' id='f_no'>とじる</button></div>",
        function (root) {
          root.querySelector("#f_no").addEventListener("click", K.closeModal);
          root.querySelector("#lk_copy").addEventListener("click", function () {
            var ta = $("lk_text");
            ta.select();
            if (navigator.clipboard) {
              navigator.clipboard.writeText(ta.value).then(function () {
                K.toast("コピーしました");
              });
            } else { K.toast("長押しでコピーしてください"); }
          });
        });
    });
  }

  function baseUrl() {
    return location.href.replace(/[^/]*$/, "");
  }

  function askSend(wid, name) {
    K.confirm("確定版を本人に送りますか",
      "<p>" + esc(name) + " さんに、確定したシフトをお送りします。</p>" +
      "<p class='hint'>LINE・メールの登録があれば、そちらへ。" +
      "なければ、印刷用の文を出します。</p>",
      "送る",
      function () {
        K.rpc("wish_send", { p_wish: wid, p_method: null }).then(function (r) {
          if (!r) return;
          K.closeModal();
          if (r.method === "print") {
            K.modal("<h2 style='margin-top:0'>印刷して、お渡しください</h2>" +
              "<div class='box' style='white-space:pre-wrap'>" + esc(r.body) + "</div>" +
              "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
              "<button class='btn ghost' id='p_pr'>印刷</button>" +
              "<button class='btn primary' id='f_no'>とじる</button></div>",
              function (root) {
                root.querySelector("#f_no").addEventListener("click", K.closeModal);
                root.querySelector("#p_pr").addEventListener("click", function () {
                  window.print();
                });
              });
          } else {
            K.toast(r.message || "送信箱に入れました");
          }
        });
      });
  }


  /* ------------------------------------------------------------ 起動 */

  K.wireLogin();
  K.boot(function () {
    loadPeriods($("pSel").value || null);
  });

  $("pSel").addEventListener("change", loadWish);
  $("pNew").addEventListener("click", function () {
    K.rpc("shift_period_open", { p_store: K.S.store.id }).then(function (p) {
      if (!p) return;
      K.toast("募集を開きました");
      loadPeriods(p.id);
    });
  });
  $("pRemind").addEventListener("click", function () {
    var p = curPeriod();
    if (!p) return;
    K.rpc("wish_remind", { p_period: p.id, p_base: baseUrl() }).then(function (r) {
      if (r) K.toast(r.message || "送信箱に入れました");
    });
  });
  $("pLinks").addEventListener("click", function () {
    var p = curPeriod();
    if (!p) return;
    K.rpc("wish_link_all", { p_period: p.id, p_base: baseUrl() }).then(function (rows) {
      rows = rows || [];
      var text = rows.map(function (r) {
        return "── " + r.name + " ──\n" + r.message;
      }).join("\n\n");
      K.modal("<h2 style='margin-top:0'>みんなの提出リンク</h2>" +
        "<p class='hint'>ひとりぶんずつコピーして、LINEやメールでお送りください。" +
        "全員ぶんをまとめて送るなら、「まだの人に催促」のほうが早いです。</p>" +
        "<textarea rows='14' style='width:100%' id='all_text'>" + esc(text) + "</textarea>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn primary' id='f_no'>とじる</button></div>",
        function (root) {
          root.querySelector("#f_no").addEventListener("click", K.closeModal);
        });
    });
  });
  $("pCount").addEventListener("click", function () {
    var p = curPeriod();
    if (!p) return;
    K.rpc("wish_day_count", { p_period: p.id }).then(function (rows) {
      rows = rows || [];
      K.modal("<h2 style='margin-top:0'>日ごとの人数</h2>" +
        "<div class='tablewrap'><table class='mini'>" +
        "<thead><tr><th>日</th><th class='num'>入れる</th><th class='num'>入りたい</th>" +
        "<th class='num'>休み</th><th>だれ</th><th></th></tr></thead><tbody>" +
        rows.map(function (r) {
          return "<tr><td>" + K.md(r.business_date) + "</td>" +
            "<td class='num'>" + r.ok_count + "</td>" +
            "<td class='num'>" + r.want_count + "</td>" +
            "<td class='num'>" + r.ng_count + "</td>" +
            "<td><small>" + esc(r.names || "") + "</small></td>" +
            "<td>" + (r.warn ? K.pill(r.warn) : "") + "</td></tr>";
        }).join("") + "</tbody></table></div>" +
        "<div class='row' style='justify-content:flex-end;margin-top:16px'>" +
        "<button class='btn primary' id='f_no'>とじる</button></div>",
        function (root) {
          root.querySelector("#f_no").addEventListener("click", K.closeModal);
        });
    });
  });
})();
