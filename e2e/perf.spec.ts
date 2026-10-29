import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, sidebar } from "./helpers";

// PERF-01..07, R-16, R-18 (W6): centro de desempenho em teste (flag perf.center, por defeito só o dono da agência).
// Dados: leituras sintéticas por idade da fixture (supabase/tests/fixtures/seed.sql), nunca dados reais.
const CENTRO = `/c/${WS_A}/desempenho/centro`;
const flagOn = () => sql(`insert into feature_flags (key, organization_id, workspace_id, stage)
  select 'perf.center', id, '${WS_A}', 'all' from organizations where slug = 'clipstudio' on conflict do nothing`);
const flagOff = () => sql(`delete from feature_flags where key = 'perf.center' and workspace_id = '${WS_A}'`);

as("owner")("dono vê o centro: contas, publicações com índice, vistas e alavancas", async ({ page, errors }) => {
  await page.goto(CENTRO);
  await expect(page.getByRole("heading", { name: "Centro de desempenho" })).toBeVisible();
  await expect(page.locator('[data-account="numeiro-ig"]')).toContainText("@itsnumeiro");
  await expect(page.getByRole("list", { name: "Cobertura por idade" })).toContainText("72 h");

  await page.getByRole("tab", { name: "Publicações" }).click();
  const table = page.getByRole("table", { name: "Publicações" });
  await expect(table.getByRole("row").nth(1)).toBeVisible();
  await expect(table).toContainText("Externo");                       // R-16: importadas entram como externas
  await table.getByRole("row").nth(1).getByRole("button").click();
  const sheet = page.getByRole("dialog");
  await expect(sheet).toContainText("Linhagem inferida");
  await expect(sheet.getByRole("region", { name: "Fotografias por idade" })).toBeVisible();
  await page.keyboard.press("Escape");

  await page.getByRole("tab", { name: "Vistas" }).click();
  await expect(page.getByText(/Sem publicações com origem sistema/)).toBeVisible();   // "Só o que fizemos" por defeito
  await page.getByRole("switch", { name: "Só o que fizemos" }).click();
  await page.getByLabel("Ver por").selectOption("format");
  await expect(page.locator('[data-group="mecanismo"]')).toBeVisible();

  await page.getByRole("tab", { name: "O que replicar" }).click();
  await expect(page.locator('[data-lever="format:mecanismo"]')).toContainText("×");
  await page.getByRole("tab", { name: "Métricas" }).click();
  await expect(page.getByText("Taxa de saltos (IG reels_skip_rate)")).toBeVisible();
  await expect(page.getByText("Indisponível até ligar a conta pela API oficial").first()).toBeVisible();
  expect(errors).toEqual([]);
});

as("staff")("staff sem a flag: item fora do menu, página explica que está em teste; desempenho clássico continua", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/desempenho`);
  await expect(page.getByRole("heading", { name: "Desempenho", exact: true })).toBeVisible();
  await expect(sidebar(page).getByRole("link", { name: "Desempenho", exact: true })).toBeVisible();
  await expect(sidebar(page).getByRole("link", { name: "Centro de desempenho" })).toHaveCount(0);
  await page.goto(CENTRO);
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  expect(errors).toEqual([]);
});

test.describe("cliente A com a flag ligada", () => {
  test.describe.configure({ mode: "serial" });
  test.beforeAll(() => { flagOn(); });
  test.afterAll(() => {
    flagOff();
    sql(`update perf_accounts set health_state = 'sem_registo', health_note = null where account_id = 'numeiro-ig'`);
  });

  as("clientA")("admin do cliente regista o estado da conta (auditado)", async ({ page, errors }) => {
    await page.goto(`/c/${WS_A}`);
    await expect(sidebar(page).getByRole("link", { name: "Centro de desempenho" })).toBeVisible();
    await page.goto(CENTRO);
    const card = page.locator('[data-account="numeiro-ig"]');
    await card.getByRole("button", { name: "Mudar camada e estado" }).click();
    await card.getByLabel("Estado da conta (registado à mão)").selectOption("alcance_reduzido");
    await card.getByLabel("Nota do estado").fill("Teste E2E");
    await card.getByRole("button", { name: "Gravar conta" }).click();
    await expect(card).toContainText("Alcance reduzido · Teste E2E");
    const [n] = sql(`select count(*) from audit_events where workspace_id = '${WS_A}' and action = 'perf.account_set' and after->>'health_note' = 'Teste E2E'`);
    expect(Number(n)).toBeGreaterThan(0);
    expect(errors).toEqual([]);
  });
});

test("o cliente B não lê nem corrige o desempenho do numeiro (403)", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  for (const [fn, body] of [
    ["perf_center", { p_ws: WS_A }],
    ["perf_publications", { p_ws: WS_A, p_filters: {} }],
    ["perf_breakdown", { p_ws: WS_A, p_dimension: "account" }],
    ["perf_levers", { p_ws: WS_A, p_only_system: false }],
    ["perf_account_set", { p_ws: WS_A, p_account: "numeiro-ig", p_patch: { tier: "D" } }],
    ["perf_origin_set", { p_ws: WS_A, p_account: "numeiro-ig", p_external_id: "FXitsnumeiro1", p_origin: "sistema", p_reason: "tentativa" }],
  ] as const) {
    const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(body) });
    expect(r.status, fn).toBe(403);
  }
  for (const table of ["perf_readings", "publication_lineage", "perf_accounts"]) {
    const direct = await fetch(`${API_URL}/rest/v1/${table}?select=*&limit=1`, { headers: h });
    expect([401, 403], table).toContain(direct.status);
  }
  const capture = await fetch(`${API_URL}/rest/v1/rpc/perf_capture`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect([401, 403, 404]).toContain(capture.status);
});

as("owner")("a 390 px o centro não faz deslocar a página na horizontal", async ({ page, errors }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(CENTRO);
  await expect(page.getByRole("heading", { name: "Centro de desempenho" })).toBeVisible();
  for (const tab of ["Contas", "Publicações", "O que replicar"]) {
    await page.getByRole("tab", { name: tab }).click();
    await page.waitForLoadState("networkidle").catch(() => {});
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow, tab).toBeLessThanOrEqual(1);
  }
  expect(errors).toEqual([]);
});
