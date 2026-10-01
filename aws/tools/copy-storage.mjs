// ============================================================================
//  ナイトだんどり / ファイル（Storage）を Supabase から AWS へ写す
//
//  使い方（Node 18 以上。追加のインストールは不要）:
//    SRC_URL=https://xxxx.supabase.co  SRC_KEY=<Supabase の service_role キー> \
//    DST_URL=https://xxxx.cloudfront.net DST_KEY=<AWS 側の service_role キー> \
//    node aws/tools/copy-storage.mjs [バケット名...]
//
//  バケット名を省くと、移行元にあるバケットをすべて写します。
//  同じ名前のファイルは上書きするので、何度流しても大丈夫です。
//  ★ service_role キーはこのコマンドの間だけ使い、ファイルやチャットに残さないでください。
// ============================================================================
const need = (k) => {
  const v = (process.env[k] || "").trim().replace(/\/+$/, "");
  if (!v) { console.error(`${k} が空です`); process.exit(2); }
  return v;
};
const SRC = { url: need("SRC_URL"), key: need("SRC_KEY") };
const DST = { url: need("DST_URL"), key: need("DST_KEY") };

const headers = (side, extra = {}) => ({ Authorization: `Bearer ${side.key}`, apikey: side.key, ...extra });
const enc = (path) => path.split("/").map(encodeURIComponent).join("/");

async function call(side, method, path, body, extra) {
  const r = await fetch(`${side.url}/storage/v1/${path}`, { method, headers: headers(side, extra), body });
  if (!r.ok) throw new Error(`${method} ${side.url}/storage/v1/${path} → ${r.status} ${await r.text()}`);
  return r;
}

async function listAll(bucket, prefix = "") {
  const files = [];
  for (let offset = 0; ; offset += 1000) {
    const r = await call(SRC, "POST", `object/list/${bucket}`,
      JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: "name", order: "asc" } }),
      { "Content-Type": "application/json" });
    const items = await r.json();
    for (const it of items) {
      const full = prefix ? `${prefix}/${it.name}` : it.name;
      if (it.id === null) files.push(...(await listAll(bucket, full)));  // フォルダ
      else files.push({ path: full, type: it.metadata?.mimetype || "application/octet-stream" });
    }
    if (items.length < 1000) return files;
  }
}

async function ensureBucket(b) {
  const r = await fetch(`${DST.url}/storage/v1/bucket/${b.id}`, { headers: headers(DST) });
  if (r.ok) return;
  await call(DST, "POST", "bucket", JSON.stringify({ id: b.id, name: b.name, public: b.public }),
    { "Content-Type": "application/json" });
  console.log(`   バケット ${b.id} を作りました`);
}

const all = await (await call(SRC, "GET", "bucket")).json();
const wanted = process.argv.slice(2);
const buckets = wanted.length ? all.filter((b) => wanted.includes(b.id)) : all;

let ok = 0, ng = 0;
for (const b of buckets) {
  console.log(`== ${b.id}`);
  await ensureBucket(b);
  const files = await listAll(b.id);
  console.log(`   ${files.length} 件`);
  for (const f of files) {
    try {
      const src = await call(SRC, "GET", `object/authenticated/${b.id}/${enc(f.path)}`);
      const body = Buffer.from(await src.arrayBuffer());
      await call(DST, "POST", `object/${b.id}/${enc(f.path)}`, body,
        { "Content-Type": f.type, "x-upsert": "true" });
      ok++;
    } catch (e) {
      ng++;
      console.error(`   !! ${f.path}: ${e.message}`);
    }
  }
}
console.log(`== 完了: 成功 ${ok} 件 / 失敗 ${ng} 件`);
process.exit(ng ? 1 : 0);
