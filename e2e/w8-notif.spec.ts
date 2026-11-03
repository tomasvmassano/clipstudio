import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { NO_ACCESS, as, expect, expectNoCrash } from "./helpers";

// W8 (ADR-0040): notificações por evento com canais e preferências (FR-15-05, FR-14-02). Flag notifications.prefs.
// cliente-a é workspace_admin do numeiro (gere), staff é manager no numeiro (só vê as do cliente; tem as suas), cliente-b só vê e2e-b.
// Só "na app" envia; email e resumo diário aparecem como indisponíveis.
test.describe.configure({ mode: "serial" });

function setFlag(stage: "all" | null) {
  sql(`delete from feature_flags where key = 'notifications.prefs' and workspace_id in ('${WS_A}', '${WS_B}')`);
  if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'notifications.prefs', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
}
function cleanup() {
  sql(`delete from notification_ws_prefs where workspace_id in ('${WS_A}', '${WS_B}')`);
  sql(`delete from notification_user_prefs where workspace_id in ('${WS_A}', '${WS_B}')`);
  sql(`delete from notification_mutes where workspace_id in ('${WS_A}', '${WS_B}')`);
}
async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (email: string, fn: string, body: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: await token(email), body: JSON.stringify(body) });

test.beforeAll(() => { cleanup(); setFlag(null); });
test.afterAll(() => { cleanup(); setFlag(null); });

as("clientA")("com a flag desligada as definições e o perfil ficam como estavam", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes`);
  await expect(page.getByRole("heading", { name: "Definições" })).toBeVisible();
  await expect(page.locator(`a[href="/c/${WS_A}/definicoes/notificacoes"]`)).toHaveCount(0);
  await page.goto(`/c/${WS_A}/definicoes/notificacoes`);
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  await page.goto(`/c/${WS_A}/perfil`);
  await expect(page.getByRole("heading", { name: "Perfil" })).toBeVisible();
  await expect(page.locator("[data-my-notif]")).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: com a flag desligada mudar recusa (55000)", async () => {
  const r = await rpc(users.clientA, "notif_settings_set", { p_ws: WS_A, p_kind: "task_done", p_channel: "in_app", p_enabled: false, p_required: false });
  expect(r.status).not.toBe(200);
  expect((await r.json()).code).toBe("55000");
});

as("clientA")("quem gere desliga um evento; obrigatórias travadas; email indisponível com motivo", async ({ page, errors }) => {
  setFlag("all");
  await page.goto(`/c/${WS_A}/definicoes`);
  await page.locator(`a[href="/c/${WS_A}/definicoes/notificacoes"]`).click();
  await expect(page.locator("[data-notif-settings]")).toBeVisible();
  await expect(page.locator("[data-notif-unavailable]")).toContainText("Email: indisponível.");
  await expect(page.locator('[data-notif-switch="automation_error:in_app"]')).toHaveAttribute("aria-disabled", "true");
  await expect(page.locator('[data-notif-switch="task_assigned:in_app"]')).toHaveAttribute("aria-disabled", "true");
  const done = page.locator('[data-notif-switch="task_done:in_app"]');
  await expect(done).toHaveAttribute("aria-checked", "true");
  await done.click();
  await expect(page.getByRole("status")).toContainText("Guardado");
  await expect(done).toHaveAttribute("aria-checked", "false");
  expect(sql(`select enabled from notification_ws_prefs where workspace_id = '${WS_A}' and kind = 'task_done' and channel = 'in_app'`)).toEqual(["f"]);
  expect(Number(sql(`select count(*) from audit_events where workspace_id = '${WS_A}' and action = 'notif.ws_pref_set' and entity_id = 'task_done:in_app'`)[0])).toBeGreaterThan(0);
  await page.reload();
  await expect(page.locator('[data-notif-switch="task_done:in_app"]')).toHaveAttribute("aria-checked", "false");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("staff (manager) vê as definições sem mudar e escolhe as suas no perfil", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes/notificacoes`);
  await expect(page.locator("[data-notif-settings]")).toBeVisible();
  await expect(page.locator('[data-notif-switch="task_mention:in_app"]')).toHaveAttribute("aria-disabled", "true");
  await page.goto(`/c/${WS_A}/perfil`);
  const card = page.locator("[data-my-notif]");
  await expect(card).toBeVisible();
  await card.locator("[data-my-notif-ws]").selectOption(WS_A);
  await expect(card.locator('[data-my-notif-switch="task_done:in_app"]')).toHaveAttribute("aria-disabled", "true");      // o cliente desligou
  await expect(card.locator('[data-my-notif-switch="task_assigned:in_app"]')).toHaveAttribute("aria-disabled", "true");  // obrigatória
  const mention = card.locator('[data-my-notif-switch="task_mention:in_app"]');
  await mention.click();
  await expect(mention).toHaveAttribute("aria-checked", "false");
  expect(sql(`select p.enabled from notification_user_prefs p join auth.users u on u.id = p.user_id
              where u.email = '${users.staff}' and p.workspace_id = '${WS_A}' and p.kind = 'task_mention' and p.channel = 'in_app'`)).toEqual(["f"]);
  await card.locator("[data-my-notif-mute-go]").click();
  await expect(card.locator("[data-my-notif-unmute]")).toBeVisible();
  await card.locator("[data-my-notif-unmute]").click();
  await expect(card.locator("[data-my-notif-mute-go]")).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: staff não muda as do cliente (42501); cliente B não vê A (42501)", async () => {
  let r = await rpc(users.staff, "notif_settings_set", { p_ws: WS_A, p_kind: "task_mention", p_channel: "in_app", p_enabled: false, p_required: false });
  expect((await r.json()).code).toBe("42501");
  r = await rpc(users.clientB, "notif_settings", { p_ws: WS_A });
  expect((await r.json()).code).toBe("42501");
  r = await rpc(users.clientB, "my_notif_prefs", { p_ws: WS_A });
  expect((await r.json()).code).toBe("42501");
  r = await rpc(users.clientA, "notif_settings_set", { p_ws: WS_A, p_kind: "automation_error", p_channel: "in_app", p_enabled: false, p_required: false });
  expect((await r.json()).code).toBe("22023");
});

as("clientB")("cliente B: não abre as de A e não vê notificações no perfil (flag só em A)", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/definicoes/notificacoes`);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
  await page.goto(`/c/${WS_B}/perfil`);
  await expect(page.getByRole("heading", { name: "Perfil" })).toBeVisible();
  await expect(page.locator("[data-my-notif]")).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});
