import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, NO_ACCESS, settle, sidebar } from "./helpers";

// R-13, R-14, TEAM-04, QA-02: cada cliente só vê o seu espaço; o endereço não abre outro cliente.

as("clientA")("equipa do cliente A entra direto no seu cliente, sem menu de agência", async ({ page, errors }) => {
  await page.goto("/");
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
  await expect(page.getByRole("heading", { name: "Início" })).toBeVisible();
  const nav = sidebar(page);
  await expect(nav.getByRole("link", { name: "Guiões", exact: true })).toHaveAttribute("href", `/c/${WS_A}/guioes`);
  await expect(nav.getByRole("link", { name: "Painel", exact: true })).toHaveCount(0);
  await expect(nav.getByRole("link", { name: "Clientes", exact: true })).toHaveCount(0);
  await expect(nav.getByRole("link", { name: "Equipa da agência" })).toHaveCount(0);
  expect(errors).toEqual([]);
});

as("clientA")("cliente A não abre o cliente B pelo endereço, nem rotas de agência", async ({ page }) => {
  for (const path of [`/c/${WS_B}`, `/c/${WS_B}/guioes`, `/c/nao-existe`]) {
    await page.goto(path);
    await expect(page.getByText(NO_ACCESS)).toBeVisible();
    await expect(page.getByText("Corpo secreto do cliente B")).toHaveCount(0);
    await expect(page.locator("[data-widget]")).toHaveCount(0);
  }
  await page.goto("/equipa-agencia");
  await settle(page);
  await expect(page.getByRole("heading", { name: "Equipa da agência" })).toHaveCount(0);
});

test("cliente A não lê nem escreve no B pela API, mesmo com o id de B", async () => {
  const token = await accessToken(users.clientA);
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" };
  // leitura direta da tabela: o RLS devolve zero linhas de B
  const rows = await (await fetch(`${API_URL}/rest/v1/guioes?select=id&client_id=eq.${WS_B}`, { headers: h })).json();
  expect(rows).toEqual([]);
  // RPC com o workspace de B: recusada
  const rpc = await fetch(`${API_URL}/rest/v1/rpc/dashboard_get`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_B, p_from: "2026-01-01", p_to: "2026-01-07" }) });
  expect(rpc.ok).toBe(false);
  // escrita no guião de B por id: nada muda
  await fetch(`${API_URL}/rest/v1/guioes?id=eq.${WS_B}-segredo`, { method: "PATCH", headers: h, body: JSON.stringify({ corpo: "adulterado" }) });
  const [corpo] = sql(`select corpo from guioes where id = '${WS_B}-segredo'`);
  expect(corpo).toBe("Corpo secreto do cliente B");
});

as("clientB")("equipa do cliente B vê só o B", async ({ page }) => {
  await page.goto("/");
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_B}`));
  await page.goto(`/c/${WS_B}/guioes`);
  await expect(page.getByText("Corpo secreto do cliente B")).toBeVisible();
  await page.goto(`/c/${WS_A}/guioes`);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
});

as("staff")("staff da agência só com acesso ao A: não vê o B", async ({ page }) => {
  await page.goto(`/c/${WS_A}`);
  await expect(page.getByRole("heading", { name: "Início" })).toBeVisible();
  await page.goto(`/c/${WS_B}`);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
});

as("owner")("dono da agência entra no Painel e abre os dois clientes", async ({ page, errors }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Painel da agência" })).toBeVisible();
  const nav = sidebar(page);
  for (const name of ["Painel", "Clientes", "Caixa de entrada", "Equipa da agência"]) {
    await expect(nav.getByRole("link", { name, exact: true })).toBeVisible();
  }
  await page.goto(`/c/${WS_B}/guioes`);
  await expect(page.getByText("Corpo secreto do cliente B")).toBeVisible();
  await page.goto(`/c/${WS_A}`);
  await expect(page.getByRole("heading", { name: "Início" })).toBeVisible();
  expect(errors).toEqual([]);
});

async function accessToken(email: string) {
  const r = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  expect(r.ok).toBe(true);
  return (await r.json()).access_token as string;
}
