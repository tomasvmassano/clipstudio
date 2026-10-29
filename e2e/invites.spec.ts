import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql } from "./env";
import { as, expect, settle } from "./helpers";

// FR-13-01: convidar, link (sem email configurado no CI aparece para copiar), recusar, aceitar, reenviar e isolamento.
const stamp = Date.now();
const declines = `recusa-${stamp}@e2e.test`;
const accepts = `aceita-${stamp}@e2e.test`;

async function inviteAndGetLink(page: import("@playwright/test").Page, email: string) {
  await page.goto(`/c/${WS_A}/equipa`);
  await page.locator("#inv-email").fill(email);
  await page.getByRole("button", { name: "Convidar", exact: true }).click();
  const link = page.getByLabel("Link do convite");
  await expect(link).toBeVisible();
  return link.inputValue();
}

as("clientA")("admin do cliente convida, quem recebe recusa pelo link", async ({ page, browser, errors }) => {
  const url = await inviteAndGetLink(page, declines);
  expect(url).toMatch(/\/convite\?t=[0-9a-f]{48}$/);
  await expect(page.getByRole("cell", { name: declines, exact: true })).toBeVisible();

  const anon = await browser.newPage({ storageState: { cookies: [], origins: [] } });
  await anon.goto(url);
  await expect(anon.getByRole("heading", { name: /Convite para Numeiro/ })).toBeVisible();
  await expect(anon.getByText(declines).first()).toBeVisible();
  await anon.getByRole("button", { name: "Recusar convite" }).click();
  await expect(anon.getByRole("heading", { name: "Convite recusado" })).toBeVisible();
  await anon.close();

  await page.reload(); await settle(page);
  const row = page.getByRole("row", { name: new RegExp(declines) });
  await expect(row.getByText("Recusado")).toBeVisible();
  await expect(row.getByRole("button", { name: /Reenviar/ })).toHaveCount(0);
  expect(errors).toEqual([]);
});

as("clientA")("quem recebe cria conta com o email do convite, aceita e entra só no cliente", async ({ page, browser }) => {
  const url = await inviteAndGetLink(page, accepts);
  // a conta é criada na stack local (o passo de confirmar o email é do Supabase, não da app)
  const key = process.env.E2E_SERVICE_KEY!;
  const r = await fetch(`${API_URL}/auth/v1/admin/users`, {
    method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email: accepts, password: PASSWORD, email_confirm: true }),
  });
  expect(r.ok).toBe(true);

  const guest = await browser.newPage({ storageState: { cookies: [], origins: [] } });
  await guest.goto(url);
  await guest.getByRole("button", { name: /Aceitar: entrar ou criar conta/ }).click();
  await guest.waitForURL(/\/login/);
  await expect(guest.locator("#email")).toHaveValue(accepts);
  await guest.locator("button[type=submit]").click();
  await guest.locator("#password").fill(PASSWORD);
  await guest.locator("button[type=submit]").click();
  await guest.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`) || u.pathname.startsWith("/convite"), { timeout: 30_000 });
  if (guest.url().includes("/convite")) {
    // a app já aceitou ao entrar; o link mostra-o e leva ao cliente
    await expect(guest.getByRole("heading", { name: "Convite aceite" })).toBeVisible();
  }
  await guest.goto(`/c/${WS_A}`);
  await expect(guest.getByRole("heading", { name: "Início" })).toBeVisible();
  await guest.goto("/c/e2e-b");
  await expect(guest.getByText("Não tens acesso a este cliente, ou ele não existe.")).toBeVisible();
  await guest.close();
  const [role] = sql(`select a.workspace_role from workspace_access a join auth.users u on u.id = a.user_id where u.email = '${accepts}' and a.workspace_id = '${WS_A}'`);
  expect(role).toBe("contributor");
});

as("clientA")("reenviar dá um link novo e o antigo deixa de valer", async ({ page, browser }) => {
  const email = `reenvio-${stamp}@e2e.test`;
  const first = await inviteAndGetLink(page, email);
  sql(`update invitations set last_sent_at = now() - interval '2 minutes' where email = '${email}'`);
  await page.reload(); await settle(page);
  await page.getByRole("row", { name: new RegExp(email) }).getByRole("button", { name: /Reenviar/ }).click();
  const link = page.getByLabel("Link do convite");
  await expect(link).not.toHaveValue(first);
  const anon = await browser.newPage({ storageState: { cookies: [], origins: [] } });
  await anon.goto(first);
  await expect(anon.getByRole("heading", { name: "Link inválido" })).toBeVisible();
  await anon.close();
});

test("a API de envio recusa quem não pode convidar nesse cliente", async () => {
  const [id] = sql(`select id from invitations where workspace_id = '${WS_A}' and accepted_at is null and revoked_at is null and declined_at is null order by created_at desc limit 1`);
  expect(id).toBeTruthy();
  // conta do cliente B a tentar gerar o link de um convite do cliente A, direto na base de dados com o token dela
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: "cliente-b@e2e.test", password: PASSWORD }),
  });
  const token = (await t.json()).access_token;
  const r = await fetch(`${API_URL}/rest/v1/rpc/invitation_issue_link`, {
    method: "POST", headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify({ p_id: id }),
  });
  expect(r.status).toBe(403);
});

as("clientB")("a rota de envio da app também recusa (403)", async ({ page }) => {
  const [id] = sql(`select id from invitations where workspace_id = '${WS_A}' and accepted_at is null and revoked_at is null and declined_at is null order by created_at desc limit 1`);
  await page.goto("/c/e2e-b");
  const status = await page.evaluate(async (i) => (await fetch(`/api/invites/${i}/send`, { method: "POST" })).status, id);
  expect(status).toBe(403);
});
