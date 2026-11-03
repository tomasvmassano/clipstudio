import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, NO_ACCESS } from "./helpers";

// W6 (ADR-0034): a minha fila no Início (FR-01-03), minha área de trabalho com ver/adiar/passar (OPS-03, FR-17-01),
// quem trabalha em quê com estados distintos (OPS-02, OPS-04) e presença só do próprio cliente (OPS-10).
test.describe.configure({ mode: "serial" });

const FLAGS = ["ops.workspace", "ops.team_presence"];
const tag = `E2E ops ${Date.now() % 1_000_000}`;
const uid = (email: string) => sql(`select id from auth.users where email = '${email}'`)[0];

function setFlags(stage: "all" | null) {
  for (const k of FLAGS) {
    sql(`delete from feature_flags where key = '${k}' and workspace_id = '${WS_A}'`);
    if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${k}', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
  }
}
function task(title: string, assignee: string) {
  return sql(`insert into tasks (workspace_id, title, assignee_id, priority, created_kind, created_label)
              values ('${WS_A}', '${title}', '${uid(assignee)}', 'high', 'system', 'E2E') returning id`)[0];
}

test.beforeAll(() => setFlags("all"));
test.afterAll(() => setFlags(null));

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}

as("clientA")("a minha fila no Início mostra a minha tarefa e abre-a", async ({ page, errors }) => {
  const id = task(`${tag} fila`, users.clientA);
  await page.goto(`/c/${WS_A}`);
  const queue = page.locator('[aria-labelledby="my-queue-title"]');
  await expect(queue.getByText(`${tag} fila`)).toBeVisible();
  await queue.getByText(`${tag} fila`).click();
  await expect(page).toHaveURL(new RegExp(`/c/${WS_A}/tarefas\\?task=${id}`));
  expect(errors).toEqual([]);
});

as("clientA")("ver e adiar ficam guardados e voltam depois de atualizar", async ({ page, errors }) => {
  const id = task(`${tag} adiar`, users.clientA);
  await page.goto(`/c/${WS_A}/caixa`);
  await expect(page.getByRole("heading", { name: "Minha área de trabalho" })).toBeVisible();
  const row = page.locator(`[data-queue-item="task:${id}"]`);
  await row.getByRole("button", { name: /Marcar como visto/ }).click();
  await expect(row.getByRole("button", { name: /Marcar como visto/ })).toHaveCount(0);
  expect(sql(`select count(*) from inbox_item_states where item_key = 'task:${id}' and acknowledged_at is not null`)[0]).toBe("1");
  await row.getByRole("button", { name: /^Adiar/ }).click();
  await page.getByRole("menuitem", { name: "Daqui a 1 hora" }).click();
  await expect(page.locator(`[aria-label="Itens por tratar"] [data-queue-item="task:${id}"]`)).toHaveCount(0);
  await page.reload();
  await page.getByRole("button", { name: /Adiados/ }).click();
  const snoozed = page.locator(`[aria-label="Itens adiados"] [data-queue-item="task:${id}"]`);
  await expect(snoozed).toBeVisible();
  await snoozed.getByRole("button", { name: "Mostrar já" }).click();
  await expect(page.locator(`[aria-label="Itens por tratar"] [data-queue-item="task:${id}"]`)).toBeVisible();
  expect(sql(`select count(*) from audit_events where entity_id = 'task:${id}' and action like 'inbox.%'`)[0]).toBe("3");
  expect(errors).toEqual([]);
});

as("staff")("staff da agência passa a sua tarefa a alguém do cliente; notifica uma vez", async ({ page, errors }) => {
  const id = task(`${tag} passar`, users.staff);
  await page.goto("/caixa");
  await expect(page.getByRole("heading", { name: "Minha área de trabalho" })).toBeVisible();
  const row = page.locator(`[data-queue-item="task:${id}"]`);
  await row.getByRole("button", { name: "Passar", exact: true }).click();
  const dlg = page.getByRole("dialog");
  await dlg.getByLabel("Para quem").selectOption({ label: users.clientA });
  await dlg.getByRole("button", { name: "Confirmar" }).click();
  await expect(dlg).toHaveCount(0);
  await expect(row).toHaveCount(0);
  expect(sql(`select assignee_id from tasks where id = '${id}'`)[0]).toBe(uid(users.clientA));
  expect(sql(`select count(*) from notifications where entity_id = '${id}' and kind = 'task_delegated'`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

as("clientA")("quem trabalha em quê: estou online e escolho o meu estado", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/quem-trabalha`);
  await expect(page.getByRole("heading", { name: "Quem trabalha em quê" })).toBeVisible();
  await page.getByLabel("Estado").selectOption("busy");
  const me = page.locator(`[data-member="${users.clientA}"]`);
  await expect(me.getByText("Ocupado")).toBeVisible();
  await page.getByRole("button", { name: "Atualizar" }).click();
  await expect(me.locator("[data-slot=badge]", { hasText: /^Online/ })).toBeVisible();
  await page.getByLabel("Estado").selectOption("");
  expect(errors).toEqual([]);
});

as("clientB")("cliente B não abre a equipa nem a fila do numeiro", async ({ page }) => {
  await page.goto(`/c/${WS_A}/quem-trabalha`);
  await expect(page.getByText(NO_ACCESS).or(page.getByText("Esta funcionalidade ainda está em teste"))).toBeVisible();
  await expect(page.getByText(users.clientA)).toHaveCount(0);
});

test("API: cliente B recebe 403 na presença, na fila e no canal do numeiro", async () => {
  const h = await token(users.clientB);
  for (const [fn, body] of [["team_presence", { p_ws: WS_A }], ["my_queue", { p_ws: WS_A }], ["presence_ping", { p_ws: WS_A }]] as const) {
    const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(body) });
    expect(r.status, fn).toBe(403);
  }
  const direct = await fetch(`${API_URL}/rest/v1/member_presence?select=user_id&limit=1`, { headers: h });
  expect([401, 403]).toContain(direct.status);
});

as("clientA")("com as flags desligadas a caixa fica como estava", async ({ page, errors }) => {
  setFlags(null);
  await page.goto(`/c/${WS_A}/caixa`);
  await expect(page.getByRole("heading", { name: "Caixa de entrada" })).toBeVisible();
  await page.goto(`/c/${WS_A}`);
  await expect(page.locator('[aria-labelledby="my-queue-title"]')).toHaveCount(0);
  expect(errors).toEqual([]);
});
