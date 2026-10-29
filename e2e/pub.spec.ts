import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W7 (ADR-0036): calendário de publicações (PUB-04) com limites das APIs (PUB-02), aprovação presa à versão e ao destino
// (PUB-06, FR-21-02), política por cliente (TEAM-10) e contas por ligar (FR-21-01). Nada publica.
test.describe.configure({ mode: "serial" });

const tag = `E2E pub ${Date.now() % 1_000_000}`;
const day = (() => {
  const d = new Date(Date.now() + 7 * 86400_000);
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Dubai", year: "numeric", month: "2-digit", day: "2-digit" }).format(d);
})();

function setFlag(stage: "all" | null) {
  sql(`delete from feature_flags where key = 'pub.planning' and workspace_id = '${WS_A}'`);
  if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'pub.planning', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
}
function cleanup() {
  sql(`update pub_publications set status = 'cancelada', approved_revision = null, approved_at = null, cancelled_reason = 'E2E'
       where workspace_id = '${WS_A}' and caption like 'E2E pub%' and status <> 'cancelada'`);
  sql(`delete from pub_approval_policies where workspace_id = '${WS_A}'`);
}
const content = () => sql(`select g.id from guioes g where g.client_id = '${WS_A}' and g.approved_version_id is not null and g.editorial_status = 'approved'
  and not exists (select 1 from pub_publications p where p.content_id = g.id and p.status <> 'cancelada' and p.platform = 'instagram')
  order by g.date desc, g.n limit 1`)[0];
const pubId = () => sql(`select id from pub_publications where caption = '${tag}' and status <> 'cancelada'`)[0];

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}

test.beforeAll(() => { cleanup(); setFlag(null); });
test.afterAll(() => { cleanup(); setFlag(null); });

as("clientA")("com a flag desligada o calendário fica como estava", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/calendario?l=pub`);
  await expect(page.getByRole("heading", { name: "Calendário" })).toBeVisible();
  await expect(page.getByRole("tab", { name: "Publicações" })).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: com a flag desligada o módulo recusa (55000)", async () => {
  const h = await token(users.clientA);
  const r = await fetch(`${API_URL}/rest/v1/rpc/pub_calendar`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_from: day, p_to: day }) });
  expect(r.status).not.toBe(200);
  expect((await r.json()).code).toBe("55000");
});

as("staff")("staff planeia uma publicação: fica por aprovar, presa à versão aprovada", async ({ page, errors }) => {
  setFlag("all");
  const gid = content();
  expect(gid, "precisa de um guião aprovado no numeiro").toBeTruthy();
  await page.goto(`/c/${WS_A}/calendario?l=pub&v=week&d=${day}`);
  await expect(page.getByRole("tab", { name: "Publicações", selected: true })).toBeVisible();
  await expect(page.getByText("Publicação automática chega quando as plataformas aprovarem a app.")).toBeVisible();
  await page.getByRole("button", { name: "Planear publicação" }).click();
  const sheet = page.getByRole("dialog");
  await sheet.getByLabel("Guião", { exact: true }).selectOption(gid);
  await expect(sheet.getByLabel("Versão do guião", { exact: true })).toContainText("aprovada");
  await sheet.getByLabel("Conta", { exact: true }).selectOption("numeiro-ig");
  await sheet.getByLabel("Dia e hora", { exact: true }).fill(`${day}T18:00`);
  await sheet.getByLabel("Legenda", { exact: true }).fill(tag);
  await sheet.getByLabel("Hashtags", { exact: true }).fill("dinheiro dubai");
  await sheet.getByRole("button", { name: "Planear", exact: true }).click();
  await expect(sheet).toHaveCount(0);
  const id = pubId();
  expect(id).toBeTruthy();
  expect(sql(`select status || '/' || revision || '/' || (content_version_id = (select approved_version_id from guioes where id = '${gid}')) from pub_publications where id = '${id}'`)[0]).toBe("planeada/1/true");
  expect(sql(`select array_to_string(hashtags, ' ') from pub_publications where id = '${id}'`)[0]).toBe("#dinheiro #dubai");
  await expect(page.locator(`[data-pub="${id}"]`)).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("cliente aprova exatamente a versão e o destino", async ({ page, errors }) => {
  const id = pubId();
  await page.goto(`/c/${WS_A}/calendario?l=pub&v=week&d=${day}`);
  await page.locator(`[data-pub="${id}"]`).click();
  await page.getByRole("button", { name: "Aprovar esta versão e destino" }).click();
  const dlg = page.getByRole("dialog", { name: "Aprovar esta publicação?" });
  await expect(dlg).toContainText("@");
  await expect(dlg).toContainText(tag);
  await dlg.getByRole("button", { name: "Aprovar", exact: true }).click();
  await expect(page.getByText(/^Aprovada\./)).toBeVisible();
  expect(sql(`select status || '/' || approved_revision from pub_publications where id = '${id}'`)[0]).toBe("aprovada/1");
  expect(sql(`select side || '/' || snapshot->>'caption' from pub_approvals where publication_id = '${id}' and invalidated_at is null`)[0]).toBe(`cliente/${tag}`);
  expect(errors).toEqual([]);
});

as("staff")("mudar a legenda depois de aprovada retira a aprovação", async ({ page, errors }) => {
  const id = pubId();
  await page.goto(`/c/${WS_A}/calendario?l=pub&v=week&d=${day}`);
  await page.locator(`[data-pub="${id}"]`).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByText(/Está aprovada/)).toBeVisible();
  await sheet.getByLabel("Hashtags", { exact: true }).fill("dinheiro");
  await sheet.getByRole("button", { name: "Guardar", exact: true }).click();
  await expect(page.getByText(/A aprovação anterior deixou de valer/)).toBeVisible();
  expect(sql(`select status || '/' || revision from pub_publications where id = '${id}'`)[0]).toBe("planeada/2");
  expect(sql(`select count(*) from pub_approvals where publication_id = '${id}' and invalidated_at is not null`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

as("clientA")("política: autoaprovação proibida explica porque não posso aprovar", async ({ page, errors }) => {
  sql(`insert into pub_approval_policies (workspace_id, required, forbid_self) values ('${WS_A}', 'qualquer', true)`);
  const id = pubId();
  sql(`update pub_publications set revision_by = (select id from auth.users where email = '${users.clientA}') where id = '${id}'`);
  await page.goto(`/c/${WS_A}/calendario?l=pub&v=week&d=${day}`);
  await page.locator(`[data-pub="${id}"]`).click();
  await expect(page.getByRole("button", { name: "Aprovar esta versão e destino" })).toHaveCount(0);
  await expect(page.getByText("Neste cliente quem planeou ou mudou a publicação não a pode aprovar.")).toBeVisible();
  expect(errors).toEqual([]);
});

test("API: cliente B não lê nem aprova publicações do numeiro; tabelas fechadas", async () => {
  const id = pubId();
  const h = await token(users.clientB);
  for (const [fn, body] of [["pub_calendar", { p_ws: WS_A, p_from: day, p_to: day }], ["pub_approve", { p_ws: WS_A, p_id: id, p_revision: 2 }],
    ["pub_save", { p_ws: WS_A, p_id: id, p_input: { caption: "x" } }]] as const) {
    const r = await fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(body) });
    expect(r.status, fn).toBe(403);
  }
  const hA = await token(users.clientA);
  const direct = await fetch(`${API_URL}/rest/v1/pub_publications?select=id&limit=1`, { headers: hA });
  expect([401, 403]).toContain(direct.status);
});

test("API: staff da agência não muda a política nem os limites", async () => {
  const h = await token(users.staff);
  const r1 = await fetch(`${API_URL}/rest/v1/rpc/pub_policy_save`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_policy: { required: "cliente" } }) });
  expect(r1.status).toBe(403);
  const r2 = await fetch(`${API_URL}/rest/v1/rpc/pub_limit_save`, { method: "POST", headers: h,
    body: JSON.stringify({ p_ws: WS_A, p_platform: "instagram", p_patch: { max_posts: 1, verified_on: day } }) });
  expect(r2.status).toBe(403);
});

as("owner")("regras e contas: limites com data de verificação e contas por ligar", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/calendario?l=pub&v=week&d=${day}`);
  await page.getByRole("button", { name: "Regras e contas" }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.locator('[data-limit="instagram"]')).toContainText("100 publicações por conta, 24 h móveis");
  await expect(sheet.locator('[data-limit="instagram"]')).toContainText(/verificado a 29/);
  await expect(sheet.locator('[data-account="numeiro-ig"]')).toContainText("Por ligar");
  await expect(sheet.getByRole("button", { name: "Editar Instagram" })).toBeVisible();
  expect(errors).toEqual([]);
});
