import { buildReport, rpcName, sessionHeaders, withDenialAudit, wsFromPath, type DenialReport } from "../src/lib/denials.ts";

const JWT = "Bearer aaa.bbb.ccc";
const BASE = "https://x.supabase.co/rest/v1/rpc/";
const cases: [string, unknown, unknown][] = [];
const add = (n: string, got: unknown, exp: unknown) => cases.push([n, got, exp]);

add("rpcName", rpcName(`${BASE}task_update`), "task_update");
add("rpcName com query", rpcName(`${BASE}tasks_list?select=*`), "tasks_list");
add("rpcName de tabela", rpcName("https://x.supabase.co/rest/v1/guioes?select=*"), null);
add("wsFromPath", wsFromPath("/c/numeiro/guioes"), "numeiro");
add("wsFromPath fora do cliente", wsFromPath("/clientes"), null);
add("wsFromPath inválido", wsFromPath("/c/<x>/a"), null);
add("buildReport usa p_ws e o id do recurso, nunca o token",
  buildReport("task_update", JSON.stringify({ p_ws: "ws_a", p_id: "t-1", p_token: "segredo" }), "browser", "outro", "c1"),
  { p_ws: "ws_a", p_action: "rpc:task_update", p_entity: "t-1", p_code: "42501", p_capability: null, p_via: "browser", p_correlation: "c1" });
add("buildReport sem p_ws usa o cliente do endereço", buildReport("task_get", JSON.stringify({ p_id: "t-2" }), "browser", "ws_b", null)?.p_ws, "ws_b");
add("buildReport ignora p_ws inválido", buildReport("x", JSON.stringify({ p_ws: "A;B" }), "api", null, null)?.p_ws, null);
add("buildReport não regista a própria função de registo", buildReport("audit_denied_record", "{}", "browser", null, null), null);
add("buildReport com corpo inválido", buildReport("x", "{oops", "api", null, null)?.p_entity, null);
add("token nunca aparece", JSON.stringify(buildReport("media_share_open", JSON.stringify({ p_share_token: "tok" }), "api", null, null)).includes("tok"), false);
add("sessão: JWT", sessionHeaders({ headers: { Authorization: JWT, apikey: "k" } })?.authorization, JWT);
add("sem sessão: chave pública no lugar do JWT", sessionHeaders({ headers: { Authorization: "Bearer sb_publishable_x", apikey: "sb_publishable_x" } }), null);
add("sem sessão: sem Authorization", sessionHeaders({ headers: {} }), null);

type Call = { url: string; body?: string };
function fake(status: number, body: unknown) {
  const calls: Call[] = [];
  const f = (async (input: RequestInfo | URL, init?: RequestInit) => {
    calls.push({ url: String(input), body: init?.body as string | undefined });
    if (String(input).endsWith("/audit_denied_record")) return new Response('{"recorded":true}', { status: 200 });
    return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  return { f, calls };
}
const init = (args: unknown): RequestInit => ({ method: "POST", headers: { Authorization: JWT, apikey: "k" }, body: JSON.stringify(args) });

{
  const { f, calls } = fake(403, { code: "42501", message: "sem_permissao" });
  const reports: DenialReport[] = [];
  let t = 0;
  const w = withDenialAudit(f, { via: "api", awaitReport: true, now: () => t, onReport: (r) => reports.push(r) });
  const res = await w(`${BASE}guiao_update`, init({ p_ws: "ws_a", p_id: "g-1" }));
  add("resposta original intacta", [res.status, ((await res.json()) as { code: string }).code], [403, "42501"]);
  add("42501 gera um registo em audit_denied_record", calls.map((c) => c.url), [`${BASE}guiao_update`, `${BASE}audit_denied_record`]);
  add("registo leva p_ws, ação e recurso", JSON.parse(calls[1].body!).p_action + "|" + JSON.parse(calls[1].body!).p_ws + "|" + JSON.parse(calls[1].body!).p_entity, "rpc:guiao_update|ws_a|g-1");
  await w(`${BASE}guiao_update`, init({ p_ws: "ws_a", p_id: "g-1" }));
  add("mesma recusa em 60 s não repete", calls.length, 3);
  t = 61_000;
  await w(`${BASE}guiao_update`, init({ p_ws: "ws_a", p_id: "g-1" }));
  add("depois de 60 s volta a registar", calls.length, 5);
  add("onReport chamado", reports.length, 2);
}
{
  const { f, calls } = fake(400, { code: "22023" });
  await withDenialAudit(f, { via: "api", awaitReport: true })(`${BASE}x`, init({}));
  add("erro de validação não regista", calls.length, 1);
}
{
  const { f, calls } = fake(403, { code: "PGRST301" });
  await withDenialAudit(f, { via: "api", awaitReport: true })(`${BASE}x`, init({}));
  add("403 sem 42501 não regista", calls.length, 1);
}
{
  const { f, calls } = fake(401, { code: "42501" });
  await withDenialAudit(f, { via: "api", awaitReport: true })(`${BASE}x`, { method: "POST", headers: { Authorization: "Bearer sb_publishable_x", apikey: "sb_publishable_x" }, body: "{}" });
  add("anónimo não regista (sem sessão)", calls.length, 1);
}
{
  const { f, calls } = fake(403, { code: "42501" });
  await withDenialAudit(f, { via: "api", awaitReport: true })(`${BASE}audit_denied_record`, init({}));
  add("recusa do próprio registo não entra em ciclo", calls.length, 1);
}
{
  const { f, calls } = fake(403, { code: "42501" });
  await withDenialAudit(f, { via: "api", awaitReport: true })("https://x.supabase.co/rest/v1/guioes?select=*", init({}));
  add("pedidos que não são RPC não registam", calls.length, 1);
}
{
  const f = (async (input: RequestInfo | URL) => {
    if (String(input).endsWith("/audit_denied_record")) throw new Error("rede");
    return new Response('{"code":"42501"}', { status: 403 });
  }) as typeof fetch;
  const res = await withDenialAudit(f, { via: "api", awaitReport: true })(`${BASE}x`, init({}));
  add("falha do registo não estraga a resposta original", res.status, 403);
}

let bad = 0;
for (const [n, got, exp] of cases) if (JSON.stringify(got) !== JSON.stringify(exp)) { bad++; console.error(`FAIL ${n}: ${JSON.stringify(got)} != ${JSON.stringify(exp)}`); }
console.log(`denials: ${cases.length - bad}/${cases.length}`);
if (bad) process.exit(1);
