import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect } from "./helpers";

// W7 (ADR-0037): motivos de rejeição e retrabalho (FR-17-10), experiências (FR-17-11), vencedores (FR-17-12),
// recomendações (SCALE-06), cargo no convite (BIZ-08), os meus dados (FR-14-05) e custos por guião (FR-10-05).
test.describe.configure({ mode: "serial" });

const FLAGS = ["learn.rework", "learn.experiments", "team.job_titles", "profile.data_export", "costs.content"];
const tag = `E2E learn ${Date.now() % 1_000_000}`;
const uid = (email: string) => sql(`select id from auth.users where email = '${email}'`)[0];
const NO_PERM = "Não tens permissão para esta página neste cliente.";
// W10-10: a migração entra como PENDING_w10_custos.sql e o Supabase CLI só aplica ficheiros com data. Enquanto a capacidade
// costs.export não existir na stack local, os testes dos custos de IA ficam saltados com o motivo (nunca fingidos) e a aba
// "Consumo de IA" (a primeira de /custos) responde 404 pela RPC em falta.
const costsReady = () => sql(`select 1 from capabilities where key = 'costs.export'`).length > 0;
const SKIP_COSTS = "Migração W10-10 ainda com o nome PENDING: o Supabase CLI não a aplica.";

function setFlags(stage: "all" | null) {
  for (const k of FLAGS) {
    sql(`delete from feature_flags where key = '${k}' and workspace_id = '${WS_A}'`);
    if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${k}', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
  }
}

// um guião do dia em revisão, que este teste devolve ao estado inicial no fim
const GID = sql(`select id from guioes where client_id = '${WS_A}' and editorial_status = 'in_review' and date = (now() at time zone 'Asia/Dubai')::date order by n desc limit 1`)[0];

test.beforeAll(() => setFlags("all"));
test.afterAll(() => {
  setFlags(null);
  if (GID) sql(`update guioes set editorial_status = 'in_review', status = 'aprovado', motivo_rejeicao = null where id = '${GID}'`);
  sql(`delete from privacy_requests where user_id = '${uid(users.clientA)}'`);
  sql(`update invitations set revoked_at = now() where email like 'e2e-learn-%' and revoked_at is null`);
});

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}

as("clientA")("motivos: começar pela lista sugerida e pedir alterações com categoria", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/aprendizagem/retrabalho`);
  await expect(page.getByRole("heading", { name: "Retrabalho", exact: true })).toBeVisible();
  const seed = page.getByRole("button", { name: "Começar pela lista sugerida" });
  if (await seed.isVisible().catch(() => false)) await seed.click();
  await expect(page.getByText("hook_fraco", { exact: true })).toBeVisible();
  await expect(page.getByText(/Vídeo \(revisão de media\): indisponível/)).toBeVisible();

  await page.goto(`/c/${WS_A}/guioes`);
  const card = page.locator(`[data-guiao="${GID}"]`);
  await card.getByRole("button", { name: "Pedir alterações" }).click();
  const cat = card.getByLabel("Categoria do pedido de alterações");
  await expect(cat).toBeVisible();
  await card.getByLabel("O que tem de mudar").fill(`${tag}: o hook não prende`);
  await expect(card.getByRole("button", { name: "Pedir alterações" })).toBeDisabled();   // categoria obrigatória com a flag
  await cat.selectOption("hook_fraco");
  await card.getByRole("button", { name: "Pedir alterações" }).click();
  await expect(card.getByText(`Alterações pedidas: ${tag}: o hook não prende`)).toBeVisible();
  expect(sql(`select count(*) from content_transition_reasons where content_id = '${GID}' and code = 'hook_fraco'`)[0]).not.toBe("0");

  await page.goto(`/c/${WS_A}/aprendizagem/retrabalho`);
  await expect(page.getByText("Hook fraco").first()).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("experiência com amostra insuficiente nunca declara líder", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/aprendizagem/experiencias`);
  await page.getByRole("button", { name: "Experiência nova" }).click();
  const sheet = page.getByRole("dialog");
  await sheet.getByLabel("Título").fill(tag);
  await sheet.getByLabel("Hipótese").fill("Hooks com número prendem mais do que perguntas.");
  await sheet.getByLabel("Valor da variante A").selectOption("numero");
  await sheet.getByLabel("Valor da variante B").selectOption("pergunta");
  await sheet.getByRole("button", { name: "Guardar rascunho" }).click();
  const detail = page.getByRole("dialog");
  await expect(detail.getByText("Pré-visualização com os dados de hoje (não fica guardada).")).toBeVisible();
  await detail.getByRole("button", { name: "Começar" }).click();
  await expect(detail.getByText("A decorrer")).toBeVisible();
  await expect(detail.getByText("amostra insuficiente").first()).toBeVisible();
  await expect(detail.getByText("Sem líder enquanto houver variantes com amostra insuficiente.")).toBeVisible();
  await expect(detail.getByRole("option", { name: /Confirmada \(critério por cumprir\)/ })).toHaveAttribute("disabled", "");
  await page.keyboard.press("Escape");
  await page.getByRole("tab", { name: "Vencedores" }).click();
  await expect(page.getByText(/Repetir cria um guião em rascunho/)).toBeVisible();
  await page.getByRole("tab", { name: "Recomendações" }).click();
  await expect(page.getByText(/Nenhuma recomendação muda a estratégia/)).toBeVisible();
  sql(`update learn_experiments set status = 'cancelada' where title = '${tag}'`);
  expect(errors).toEqual([]);
});

// ADR-0071 (decisão do dono 2026-11-09): a equipa do cliente nunca vê custos; os custos do cliente leem-se com a agência.
as("owner")("custos por guião: página, vídeo indisponível e CSV", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/custos`);
  await page.getByRole("tab", { name: "Por guião e publicação" }).click();
  await expect(page.getByRole("heading", { name: "Custos por guião e publicação" })).toBeVisible();
  await expect(page.getByText("Por vídeo", { exact: true })).toBeVisible();
  await expect(page.getByText("indisponível", { exact: true })).toBeVisible();
  const [dl] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Exportar CSV" }).click()]);
  expect(dl.suggestedFilename()).toMatch(/^custos-numeiro-6m\.csv$/);
  // sem a migração W10-10 a aba de IA (aberta por defeito) recebe 404 da RPC em falta; é o único erro tolerado
  expect(costsReady() ? errors : errors.filter((e) => !/status of 404/.test(e))).toEqual([]);
});

// W10-10 (FR-10-01, ADR-0062): consumo de IA por agente, modelo e execução, rotulado como estimado, com CSV auditado.
as("owner")("custos de IA do cliente: estimado, tabelas e CSV da tabela visível", async ({ page, errors }) => {
  test.skip(!costsReady(), SKIP_COSTS);
  await page.goto(`/c/${WS_A}/custos`);
  await expect(page.getByRole("heading", { name: "Consumo de IA" })).toBeVisible();
  await expect(page.getByText("Valores estimados.")).toBeVisible();
  await expect(page.getByText("Custo das execuções", { exact: true })).toBeVisible();
  await expect(page.getByRole("tab", { name: "Por cliente" })).toHaveCount(0);
  await page.getByRole("tab", { name: "Por modelo" }).click();
  await page.getByLabel("Período").selectOption("7");
  await expect(page.getByText(/\(7 dias, fuso /)).toBeVisible();
  const [dl] = await Promise.all([page.waitForEvent("download"), page.getByRole("button", { name: "Exportar CSV" }).click()]);
  expect(dl.suggestedFilename()).toMatch(/^custos-ia-numeiro-models-\d{4}-\d{2}-\d{2}-\d{4}-\d{2}-\d{2}\.csv$/);
  await expect.poll(() => sql(`select count(*) from audit_events where action = 'costs.ai_exported' and workspace_id = '${WS_A}' and actor_user_id = '${uid(users.owner)}' and after->>'table' = 'models'`)[0]).not.toBe("0");
  await page.getByLabel("Período").selectOption("custom");
  await page.getByLabel("De", { exact: true }).fill("2026-10-31");
  await page.getByLabel("Até", { exact: true }).fill("2026-10-01");
  await page.getByRole("button", { name: "Aplicar" }).click();
  await expect(page.getByText("A data de início tem de ser anterior ou igual à data de fim.")).toBeVisible();
  expect(errors).toEqual([]);
});

as("owner")("custos da agência: por cliente e sem acesso para a equipa", async ({ page, errors }) => {
  test.skip(!costsReady(), SKIP_COSTS);
  await page.goto("/custos");
  await expect(page.getByRole("heading", { name: "Custos da agência" })).toBeVisible();
  await expect(page.getByRole("tab", { name: "Por cliente" })).toBeVisible();
  await expect(page.getByRole("cell", { name: "Numeiro" }).first()).toBeVisible();
  expect(errors).toEqual([]);
});

as("staff")("staff da agência sem costs.read_agency não vê os custos da agência", async ({ page }) => {
  await page.goto("/custos");
  await expect(page.getByText("Os custos da agência são só para quem tem acesso aos custos da agência.")).toBeVisible();
  await expect(page.getByRole("heading", { name: "Custos da agência" })).toHaveCount(0);
});

as("staff")("staff sem costs.read não vê a página de custos", async ({ page }) => {
  await page.goto(`/c/${WS_A}/custos`);
  await expect(page.getByText(NO_PERM)).toBeVisible();
  await expect(page.getByRole("heading", { name: "Custos por guião e publicação" })).toHaveCount(0);
});

as("clientA")("convidar com cargo pré-seleciona papel e exceções", async ({ page, errors }) => {
  const email = `e2e-learn-${Date.now() % 1_000_000}@e2e.test`;
  await page.goto(`/c/${WS_A}/equipa`);
  await page.getByLabel("Cargo").selectOption("smm");
  await expect(page.getByLabel(/Agendar publicações|Planear publicações/)).toBeChecked();
  await page.locator("#inv-email").fill(email);
  await page.getByRole("button", { name: "Convidar" }).click();
  await expect.poll(() => sql(`select job_title || '|' || array_to_string(suggested_grants, ',') from invitations where email = '${email}'`)[0])
    .toBe("Social Media Manager|calendar.schedule,publishing.schedule");
  expect(errors).toEqual([]);
});

as("clientA")("os meus dados: descarregar JSON e pedir eliminação", async ({ page, errors }) => {
  await page.goto("/perfil");
  const card = page.locator("[data-my-data]");
  await expect(card.getByText("Os meus dados", { exact: true })).toBeVisible();
  const [dl] = await Promise.all([page.waitForEvent("download"), card.getByRole("button", { name: "Descarregar os meus dados (JSON)" }).click()]);
  expect(dl.suggestedFilename()).toMatch(/^os-meus-dados-\d{4}-\d{2}-\d{2}\.json$/);
  await card.getByRole("button", { name: "Pedir eliminação" }).click();
  await card.getByLabel("Pedir a eliminação dos meus dados").fill(tag);
  await card.getByRole("button", { name: "Enviar pedido" }).click();
  await expect(card.getByText("Pedido registado. O dono da agência vai tratá-lo.")).toBeVisible();
  await expect(card.getByText("Eliminação · Pendente")).toBeVisible();
  expect(sql(`select count(*) from privacy_requests where user_id = '${uid(users.clientA)}' and status = 'pendente'`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

as("owner")("o dono da agência vê e trata o pedido de eliminação", async ({ page, errors }) => {
  await page.goto("/equipa-agencia");
  const card = page.locator("[data-privacy-requests]");
  await expect(card.getByText(users.clientA)).toBeVisible();
  await card.getByLabel(`O que foi feito com o pedido de ${users.clientA}`).fill("Tratado no teste E2E");
  await card.getByRole("button", { name: "Marcar tratado" }).click();
  await expect(card.getByText("Resolução: Tratado no teste E2E")).toBeVisible();
  expect(errors).toEqual([]);
});

test("cliente B não lê retrabalho, experiências, vencedores nem custos do numeiro (403)", async () => {
  const h = await token(users.clientB);
  for (const [fn, body] of [
    ["rework_dashboard", { p_ws: WS_A }], ["rework_reasons_list", { p_ws: WS_A }], ["learn_experiments_list", { p_ws: WS_A }],
    ["learn_winners", { p_ws: WS_A }], ["learn_recommendations", { p_ws: WS_A }], ["content_costs", { p_ws: WS_A }],
    ["job_title_templates", { p_ws: WS_A }],
  ] as const) {
    const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(body) });
    expect(r.status, fn).toBe(403);
  }
  const direct = await fetch(`${API_URL}/rest/v1/learn_experiments?select=id&limit=1`, { headers: h });
  expect([401, 403]).toContain(direct.status);
  const privacy = await fetch(`${API_URL}/rest/v1/rpc/privacy_requests_admin`, { method: "POST", headers: h, body: "{}" });
  expect(privacy.status).toBe(403);
});

as("clientA")("com as flags desligadas tudo fica como antes", async ({ page, errors }) => {
  setFlags(null);
  await page.goto(`/c/${WS_A}/aprendizagem/retrabalho`);
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  await page.goto("/perfil");
  await expect(page.getByRole("heading", { name: "Perfil" })).toBeVisible();
  await expect(page.locator("[data-my-data]")).toHaveCount(0);
  setFlags("all");
  expect(errors).toEqual([]);
});
