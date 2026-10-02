// ============================================================================
//  ナイトだんどり / Edge Function を素の Deno で動かすための小さな土台
//
//    deno run --allow-net --allow-env --allow-read server/functions/run.ts <関数名> <ポート>
//
//  3_サーバー/<関数名>/index.ts は Supabase 向けに `Deno.serve(handler)` と書いてあり、
//  そのままだとポート 8000 で待ち受けてしまいます。
//  ここで Deno.serve を差し替えて、127.0.0.1 の指定ポートで待つようにしてから読み込みます。
//  関数の中身は1行も変えません。
// ============================================================================
const [name, portArg] = Deno.args;
const port = Number(portArg);
if (!/^[a-z0-9][a-z0-9_-]*$/.test(name ?? "") || !port) {
  console.error("使い方: run.ts <関数名> <ポート>");
  Deno.exit(2);
}

const original = Deno.serve;
// deno-lint-ignore no-explicit-any
(Deno as any).serve = (a: unknown, b?: unknown) => {
  const handler = (typeof a === "function" ? a : (b ?? (a as { handler: unknown }).handler)) as Deno.ServeHandler;
  const opts = (typeof a === "function" ? {} : a) as Record<string, unknown>;
  return original({ ...opts, hostname: "127.0.0.1", port, onListen: () => console.log(`${name}: 127.0.0.1:${port}`) }, handler);
};

const here = new URL(".", import.meta.url);
await import(new URL(`../../3_サーバー/${name}/index.ts`, here).href);
