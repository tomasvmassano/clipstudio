import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, expectNoCrash, sidebar } from "./helpers";

// W10-01 (ADR-0058): saúde do sistema (FR-17-15). Painel da agência só com dados persistidos e alertas idempotentes.
// A migração entra no repositório como PENDING_w10_saude.sql e o Supabase CLI só aplica ficheiros com data: enquanto
// a capacidade não existir na stack local, os testes ficam saltados com o motivo (nunca fingidos).
test.describe.configure({ mode: "serial" });

const ready = () => sql(`select 1 from capabilities where key = 'ops.health'`).length > 0;
const WORKER = "e2e-saude-worker";

function seed() {
  cleanup();
  sql(`insert into agent_workers (id, kinds, last_seen, version) values ('${WORKER}', array['ingest'], now() - interval '30 minutes', 'e2e')`);
  sql(`insert into media_jobs (workspace_id, kind, idempotency_key, status, attempts, max_attempts, last_error, finished_at, next_attempt_at) values
       ('${WS_B}', 'ingest', 'e2e-saude-q', 'queued', 0, 5, null, null, now() - interval '20 minutes'),
       ('${WS_A}', 'export', 'e2e-saude-dead', 'dead', 5, 5, 'falhou token=e2esegredo', now() - interval '1 hour', now())`);
}
function cleanup() {
  if (!ready()) return;
  sql(`delete from notifications where kind = 'system_health'`);
  sql(`delete from ops_health_alerts where workspace_id in ('${WS_A}', '${WS_B}')`);
  sql(`delete from media_jobs where idempotency_key like 'e2e-saude-%'`);
  sql(`delete from agent_workers where id = '${WORKER}'`);
}

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const call = async (email: string, fn: string) => {
  const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: await token(email), body: "{}" });
  return { status: r.status, json: await r.json() };
};

test.beforeEach(() => { test.skip(!ready(), "Migração W10-01 ainda com o nome PENDING: o Supabase CLI não a aplica."); });
test.beforeAll(() => { if (ready()) seed(); });
test.afterAll(() => cleanup());

test("API: staff sem ops.health e equipas dos clientes recebem 42501; o browser não corre o tick", async () => {
  for (const u of [users.staff, users.clientA, users.clientB]) {
    const r = await call(u, "ops_health");
    expect(r.status).not.toBe(200);
    expect(r.json.code).toBe("42501");
  }
  const t = await call(users.owner, "ops_health_tick");
  expect(t.status).not.toBe(200);
});

test("tick: um aviso por incidente, repetir não duplica", async () => {
  sql(`select public.ops_health_tick()`);
  const n = Number(sql(`select count(*) from notifications where kind = 'system_health'`)[0]);
  expect(n).toBeGreaterThanOrEqual(2);
  sql(`select public.ops_health_tick()`);
  expect(Number(sql(`select count(*) from notifications where kind = 'system_health'`)[0])).toBe(n);
  expect(sql(`select count(*) from notifications n join auth.users u on u.id = n.user_id where n.kind = 'system_health' and u.email <> '${users.owner}'`)[0]).toBe("0");
});

as("owner")("dono vê workers, filas, falhas sem segredos e alertas, com links para o cliente", async ({ page, errors }) => {
  await page.goto("/saude");
  await expect(page.getByRole("heading", { name: "Saúde do sistema" })).toBeVisible();
  await expect(sidebar(page).locator('a[href="/saude"]')).toBeVisible();
  await expect(page.locator(`[data-worker="${WORKER}"]`)).toContainText("sem contacto");
  await expect(page.locator('[data-health="bad"]')).toContainText("sem worker visto");
  await expect(page.locator('[data-section="workers"]')).toBeVisible();
  const fail = page.locator("[data-failure]").filter({ hasText: "Exportar vídeo" }).first();
  await expect(fail).toContainText("[removido]");
  await expect(page.getByText("e2esegredo")).toHaveCount(0);
  await expect(page.locator(`[data-client="${WS_B}"]`)).toBeVisible();
  await expect(page.locator('[data-alert="worker_down"]').first()).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("staff da agência sem ops.health: sem item no menu e acesso recusado", async ({ page, errors }) => {
  await page.goto("/saude");
  await expect(page.getByText("A saúde do sistema é do dono e dos administradores da agência.")).toBeVisible();
  await expect(sidebar(page).locator('a[href="/saude"]')).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("equipa do cliente: acesso recusado, sem página de erro", async ({ page, errors }) => {
  await page.goto("/saude");
  await expect(page.getByText("A saúde do sistema é do dono e dos administradores da agência.")).toBeVisible();
  await expect(page.getByText(WS_B)).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});
