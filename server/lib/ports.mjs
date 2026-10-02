// 3_サーバー の関数ごとのポート番号。
// フォルダ名を並べた順に FN_BASE_PORT から1つずつ割り当てる（入口と PM2 で同じ計算をする）。
import fs from "node:fs";
import path from "node:path";

export const FUNCTIONS_DIR = path.resolve(import.meta.dirname, "..", "..", "3_サーバー");

export function functionNames() {
  return fs.readdirSync(FUNCTIONS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && fs.existsSync(path.join(FUNCTIONS_DIR, d.name, "index.ts")))
    .map((d) => d.name)
    .sort();
}

export function functionPorts(base = Number(process.env.FN_BASE_PORT || 38041)) {
  const out = {};
  functionNames().forEach((n, i) => { out[n] = base + i; });
  return out;
}
