import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W8 (ADR-0039): centro de integrações (FR-15-03, FR-17-16). Só estados reais: contas sociais por ligar, ligar e renovar
// indisponíveis com o motivo, recolha de métricas e motor de agentes lidos da base, testar e revogar reais. Nada liga contas.
test.describe.configure({ mode: "serial" });

let igA = "";
/** Conta Instagram do cliente A (lida da base na primeira vez). */
const ig = () => (igA ||= sql(`select id from accounts where client_id = '${WS_A}' and role = 'client' and platform = 'instagram' order by id limit 1`)[0]);

function setFlag(stage: "all" | null) {
  sql(`delete from feature_flags where key = 'integrations.center' and workspace_id in ('${WS_A}', '${WS_B}')`);
  if (stage) {
    sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'integrations.center', id, w, '${stage}'
         from organizations, unnest(array['${WS_A}', '${WS_B}']) w where slug = 'clipstudio'`);
  }
}
// O serviço de OAuth ainda não existe (PLAT-01): para testar o revogar, a conta fica no estado que ele deixará.
function connectForTest() {
  sql(`update social_accounts set connection_state = 'ligada', token_ref = 'vault:' || gen_random_uuid(), scopes = array['instagram_business_basic'],
       token_expires_at = now() + interval '40 days', connected_at = now(), connected_label = 'E2E' where account_id = '${ig()}'`);
}
function cleanup() {
  sql(`update social_accounts set connection_state = 'por_ligar', token_ref = null, scopes = '{}', token_expires_at = null, connected_at = null,
       connected_label = null where account_id = '${ig()}'`);
}

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const call = async (email: string, fn: string, body: Record<string, unknown>) => {
  const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: await token(email), body: JSON.stringify(body) });
  return { status: r.status, json: await r.json() };
};

test.beforeAll(() => { cleanup(); setFlag(null); });
test.afterAll(() => { cleanup(); setFlag(null); });

test("API: com a flag desligada o centro recusa (55000)", async () => {
  const r = await call(users.clientA, "integrations_overview", { p_ws: WS_A });
  expect(r.status).not.toBe(200);
  expect(r.json.code).toBe("55000");
});

as("clientA")("com a flag desligada o item não aparece no menu", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes`);
  await expect(page.getByRole("heading", { name: "Definições" })).toBeVisible();
  await expect(page.locator(`a[href="/c/${WS_A}/definicoes/integracoes"]`)).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("admin do cliente vê estados reais: por ligar, ligar indisponível, recolha e worker", async ({ page, errors }) => {
  setFlag("all");
  await page.goto(`/c/${WS_A}/definicoes/integracoes`);
  await expect(page.getByRole("heading", { name: "Integrações" })).toBeVisible();
  const ig = page.locator('[data-integration="instagram"]');
  await expect(ig.locator('[data-state="por_ligar"]').first()).toBeVisible();
  await expect(ig.locator('[data-action-off="ligar"]')).toContainText("Ligar: indisponível.");
  await expect(ig.locator('[data-action-off="renovar"]')).toContainText("Renovar: indisponível.");
  await expect(ig.locator("[data-revoke]")).toHaveCount(0);
  await expect(page.locator('[data-integration="scraping"]')).toContainText("Última sincronização");
  await expect(page.locator('[data-integration="agents_worker"]')).toContainText("Último contacto do worker");
  await expect(page.locator('[data-test-integration="instagram"]')).toHaveCount(0);   // só se testa o que é real
  await expect(page.locator('[data-integration="google_drive"]')).toHaveCount(0);      // é da agência
  const html = await page.content();
  expect(html).not.toContain("vault:");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("testar a recolha de métricas guarda um teste real", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes/integracoes`);
  const before = Number(sql(`select count(*) from integration_checks where workspace_id = '${WS_A}' and integration_key = 'scraping'`)[0]);
  await page.locator('[data-test-integration="scraping"]').click();
  await expect(page.locator('[data-integration="scraping"] [data-outcome]')).toBeVisible();
  expect(Number(sql(`select count(*) from integration_checks where workspace_id = '${WS_A}' and integration_key = 'scraping'`)[0])).toBe(before + 1);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("revogar uma conta ligada pede motivo e fica revogada", async ({ page, errors }) => {
  connectForTest();
  await page.goto(`/c/${WS_A}/definicoes/integracoes`);
  await page.locator(`[data-revoke="${ig()}"]`).click();
  await expect(page.locator("[data-revoke-confirm]")).toBeDisabled();
  await page.locator("[data-revoke-reason]").fill("Teste E2E de revogação");
  await page.locator("[data-revoke-confirm]").click();
  await expect(page.locator(`[data-social="${ig()}"] [data-state="revogada"]`)).toBeVisible();
  expect(sql(`select connection_state || ':' || (token_ref is null) from social_accounts where account_id = '${ig()}'`)[0]).toBe("revogada:true");
  expect(Number(sql(`select count(*) from audit_events where action = 'integrations.social_revoked' and entity_id = '${ig()}' and after->>'reason' = 'Teste E2E de revogação'`)[0])).toBeGreaterThan(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("staff da agência (gestor) lê, mas não testa nem revoga", async ({ page, errors }) => {
  connectForTest();
  await page.goto(`/c/${WS_A}/definicoes/integracoes`);
  await expect(page.getByRole("heading", { name: "Integrações" })).toBeVisible();
  await expect(page.locator("[data-test-integration]")).toHaveCount(0);
  await expect(page.locator("[data-revoke]")).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: gestor não revoga; cliente B não lê nem revoga em A", async () => {
  connectForTest();
  expect((await call(users.staff, "integrations_social_revoke", { p_ws: WS_A, p_account_id: ig(), p_reason: "não devia" })).json.code).toBe("42501");
  expect((await call(users.clientB, "integrations_overview", { p_ws: WS_A })).json.code).toBe("42501");
  expect((await call(users.clientB, "integrations_social_revoke", { p_ws: WS_A, p_account_id: ig(), p_reason: "não devia" })).json.code).toBe("42501");
  expect((await call(users.clientB, "integrations_social_revoke", { p_ws: WS_B, p_account_id: ig(), p_reason: "não devia" })).json.code).toBe("P0002");
  const b = await call(users.clientB, "integrations_overview", { p_ws: WS_B });
  expect(b.status).toBe(200);
  expect(JSON.stringify(b.json)).not.toContain(ig());
  expect(sql(`select connection_state from social_accounts where account_id = '${ig()}'`)[0]).toBe("ligada");
});

as("clientB")("cliente B não abre as integrações de A pelo endereço", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes/integracoes`);
  await expect(page.locator("[data-integration]")).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("owner")("dono da agência vê as integrações da agência e o estado de cada cliente", async ({ page, errors }) => {
  await page.goto("/integracoes");
  await expect(page.getByRole("heading", { name: "Integrações da agência" })).toBeVisible();
  for (const k of ["google_drive", "cloudflare_r2", "resend"]) {
    await expect(page.locator(`[data-integration="${k}"] [data-state="por_ligar"]`)).toBeVisible();
  }
  await expect(page.locator('[data-integration="platform_limits"]')).toContainText("Limite da API");
  await expect(page.locator(`[data-client="${WS_A}"]`)).toBeVisible();
  await expect(page.locator(`[data-client="${WS_B}"]`)).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("staff da agência não vê a vista da agência", async ({ page, errors }) => {
  await page.goto("/integracoes");
  await expect(page.getByText("As integrações da agência são só do dono da agência.")).toBeVisible();
  await expect(page.locator("[data-integration]")).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});
