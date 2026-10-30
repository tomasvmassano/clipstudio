import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { NO_ACCESS, as, expect, expectNoCrash, settle, sidebar } from "./helpers";

// W8 (ADR-0041): portal do cliente (SCALE-08). Aprovação pelas RPCs de sempre, entregas sem dinheiro, desempenho
// indisponível com motivo, pedidos de conteúdo, isolamento entre clientes e staff da agência "como o cliente vê".
test.describe.configure({ mode: "serial" });

const tag = `E2E portal ${Date.now() % 1_000_000}`;
let approved: string | null = null;

function setFlag(key: string, stage: "all" | null) {
  sql(`delete from feature_flags where key = '${key}' and workspace_id = '${WS_A}'`);
  if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${key}', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
}
async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (email: string, fn: string, body: unknown) => {
  const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: await token(email), body: JSON.stringify(body) });
  return { status: r.status, json: await r.json().catch(() => null) };
};

test.beforeAll(() => { setFlag("client.portal", null); });
test.afterAll(async () => {
  setFlag("client.portal", null);
  // devolve o guião aprovado pelo teste à revisão, pela RPC de sempre (scripts.approve)
  if (approved) await rpc(users.clientA, "content_transition", { p_id: approved, p_to: "in_review", p_reason: "E2E portal: repor" });
  sql(`update ideas set status = 'descartada', status_reason = 'E2E' where kind = 'talent_request' and resumo like 'E2E portal%' and status <> 'descartada'`);
});

as("clientA")("com a flag desligada o portal não aparece", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/portal`);
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  await expect(sidebar(page).getByRole("link", { name: "Portal", exact: true })).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: com a flag desligada o portal recusa (55000)", async () => {
  const r = await rpc(users.clientA, "portal_home", { p_ws: WS_A });
  expect(r.status).not.toBe(200);
  expect(r.json.code).toBe("55000");
});

as("clientA")("cliente abre o portal pelo Início e vê os cinco blocos", async ({ page, errors }) => {
  setFlag("client.portal", "all");
  await page.goto(`/c/${WS_A}`);
  await page.locator("[data-portal-hint]").getByRole("link", { name: "Abrir o portal" }).click();
  await expect(page).toHaveURL(new RegExp(`/c/${WS_A}/portal$`));
  await expect(page.getByRole("heading", { name: "Portal", exact: true })).toBeVisible();
  for (const id of ["guioes", "publicacoes", "entregas", "relatorios", "pedidos"]) await expect(page.locator(`[data-portal-block="${id}"]`)).toBeVisible();
  await expect(page.locator("[data-portal-as-client]")).toHaveCount(0);
  await expect(sidebar(page).getByRole("link", { name: "Portal", exact: true })).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("aprovar um guião no portal grava a transição presa à versão", async ({ page, errors }) => {
  const id = sql(`select id from guioes where client_id = '${WS_A}' and editorial_status = 'in_review' order by date, n limit 1`)[0];
  expect(id, "precisa de um guião em revisão no numeiro").toBeTruthy();
  await page.goto(`/c/${WS_A}/portal`);
  const card = page.locator(`[data-portal-script="${id}"]`);
  await card.getByRole("button", { name: "Aprovar guião" }).click();
  await expect(page.getByText(/^Guião \d+ aprovado\.$/)).toBeVisible();
  approved = id;
  await expect(card).toHaveCount(0);
  expect(sql(`select editorial_status || '/' || (approved_version_id = current_version_id) from guioes where id = '${id}'`)[0]).toBe("approved/true");
  expect(sql(`select count(*) from content_transitions where content_id = '${id}' and to_status = 'approved' and actor_kind = 'user'`)[0]).not.toBe("0");
  expect(errors).toEqual([]);
});

as("clientA")("entregas sem dinheiro; desempenho e publicações indisponíveis com motivo", async ({ page, errors }) => {
  setFlag("pub.planning", null); setFlag("perf.center", null);
  await page.goto(`/c/${WS_A}/portal`);
  const del = page.locator('[data-portal-block="entregas"]');
  await expect(del.locator('[data-delivery="videos"]')).toBeVisible();
  await expect(del).not.toContainText("€");
  await expect(del).not.toContainText("AED");
  await expect(page.locator('[data-portal-block="relatorios"] [data-unavailable="desligado"]')).toContainText("O centro de desempenho ainda não está ligado");
  await expect(page.locator('[data-portal-block="publicacoes"] [data-unavailable="desligado"]')).toContainText("O calendário de publicações ainda não está ligado");
  const r = await rpc(users.clientA, "portal_block", { p_ws: WS_A, p_block: "deliveries" });
  expect(r.status).toBe(200);
  for (const k of ["amount", "currency", "payment", "billing", "renewal", "notes", "margin", "cost"]) expect(JSON.stringify(r.json)).not.toContain(k);
  expect(errors).toEqual([]);
});

as("clientA")("pedido de conteúdo criado no portal fica registado e aparece como recebido", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/portal`);
  const box = page.locator('[data-portal-block="pedidos"]');
  await box.getByLabel("Novo pedido").fill(tag);
  await box.getByRole("button", { name: "Enviar pedido" }).click();
  await expect(box.getByText("Pedido enviado. A agência vê-o na triagem.")).toBeVisible();
  const id = sql(`select id from ideas where client_id = '${WS_A}' and kind = 'talent_request' and resumo = '${tag}'`)[0];
  expect(id).toBeTruthy();
  await expect(box.locator(`[data-portal-request="${id}"]`)).toContainText("Recebido");
  await expect(box.locator(`[data-portal-request="${id}"]`)).toContainText("teu");
  expect(errors).toEqual([]);
});

as("staff")("staff da agência atribuído vê o portal como o cliente vê", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/portal`);
  await expect(page.locator("[data-portal-as-client]")).toBeVisible();
  await expect(page.locator('[data-portal-block="pedidos"]')).toContainText(tag);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientB")("cliente B não abre o portal do numeiro", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/portal`);
  await settle(page);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
  await expect(page.getByText(tag)).toHaveCount(0);
  expect(errors).toEqual([]);
});

test("API: cliente B recebe 403 no portal e nos blocos do numeiro; o seu não mostra nada do A", async () => {
  for (const [fn, body] of [["portal_home", { p_ws: WS_A }], ["portal_block", { p_ws: WS_A, p_block: "requests" }]] as const) {
    const r = await rpc(users.clientB, fn, body);
    expect(r.status, fn).toBe(403);
  }
  sql(`delete from feature_flags where key = 'client.portal' and workspace_id = '${WS_B}'`);
  sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'client.portal', id, '${WS_B}', 'all' from organizations where slug = 'clipstudio'`);
  const own = await rpc(users.clientB, "portal_home", { p_ws: WS_B });
  sql(`delete from feature_flags where key = 'client.portal' and workspace_id = '${WS_B}'`);
  expect(own.status).toBe(200);
  expect(JSON.stringify(own.json)).not.toContain(WS_A);
  expect(JSON.stringify(own.json)).not.toContain(tag);
});
