import { test, type Page } from "@playwright/test";
import { createHmac } from "node:crypto";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql } from "./env";
import { as, expect, settle } from "./helpers";

// FR-14-01 (e partes de FR-14-02/03/04): perfil, palavra-passe, verificação em dois passos aplicada no servidor.
const stamp = Date.now();

async function newUser(email: string) {
  const key = process.env.E2E_SERVICE_KEY!;
  const r = await fetch(`${API_URL}/auth/v1/admin/users`, {
    method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
  });
  expect(r.ok).toBe(true);
  sql(`insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role)
       select '${WS_A}', id, 'client_staff', 'contributor' from auth.users where email = '${email}'`);
}

async function login(page: Page, email: string, password = PASSWORD) {
  await page.goto("/login");
  await page.locator("#email").fill(email);
  await page.locator("button[type=submit]").click();
  await page.locator("#password").fill(password);
  await page.locator("button[type=submit]").click();
}

/** TOTP (RFC 6238, SHA-1, 30 s, 6 dígitos) a partir da chave base32 que o Supabase devolve. */
function totp(secret: string, at = Date.now()) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = "";
  for (const c of secret.replace(/=+$/, "").toUpperCase()) bits += alphabet.indexOf(c).toString(2).padStart(5, "0");
  const key = Buffer.from(bits.match(/.{8}/g)!.map((b) => parseInt(b, 2)));
  const msg = Buffer.alloc(8); msg.writeBigUInt64BE(BigInt(Math.floor(at / 30000)));
  const h = createHmac("sha1", key).update(msg).digest();
  const o = h[h.length - 1] & 0xf;
  return String((h.readUInt32BE(o) & 0x7fffffff) % 1_000_000).padStart(6, "0");
}

as("clientA")("perfil: nome, cliente preferido e tema ficam guardados", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/perfil`);
  await expect(page.getByRole("heading", { name: "Perfil" })).toBeVisible();
  await expect(page.getByText("verificado")).toBeVisible();
  await page.locator("#pf-name").fill("Ana do Cliente A");
  await page.getByRole("button", { name: "Guardar" }).click();
  await expect(page.getByText("Nome guardado.")).toBeVisible();
  await page.locator("select[aria-label=\"Cliente ao entrar\"]").selectOption(WS_A);
  await expect(page.getByText("Cliente preferido guardado.")).toBeVisible();
  await page.locator("select[aria-label=Tema]").selectOption("light");
  await expect(page.getByText("Tema guardado.")).toBeVisible();
  await page.reload(); await settle(page);
  await expect(page.locator("#pf-name")).toHaveValue("Ana do Cliente A");
  await expect(page.locator("select[aria-label=Tema]")).toHaveValue("light");
  await expect(page.locator("select[aria-label=\"Cliente ao entrar\"]").locator("option")).toHaveCount(2);   // "o último" + só o A, nunca o B
  await page.getByRole("button", { name: "Menu da conta" }).click();
  await expect(page.getByText("Ana do Cliente A").first()).toBeVisible();
  await page.keyboard.press("Escape");
  await page.locator("select[aria-label=Tema]").selectOption("dark");
  await expect(page.getByText("Histórico recente")).toBeVisible();
  await expect(page.getByText("Perfil alterado").first()).toBeVisible();
  expect(errors).toEqual([]);
});

test("palavra-passe: recusa a atual errada e muda com a certa", async ({ page }) => {
  const email = `senha-${stamp}@e2e.test`;
  await newUser(email);
  await login(page, email);
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
  await page.goto(`/c/${WS_A}/perfil`);
  await page.locator("#pf-cur").fill("errada-errada");
  await page.locator("#pf-new").fill("nova-palavra-passe-1");
  await page.locator("#pf-new2").fill("nova-palavra-passe-1");
  await page.getByRole("button", { name: "Mudar palavra-passe" }).click();
  await expect(page.getByText("A palavra-passe atual não está certa.")).toBeVisible();
  await page.locator("#pf-cur").fill(PASSWORD);
  await page.getByRole("button", { name: "Mudar palavra-passe" }).click();
  await expect(page.getByText(/Palavra-passe mudada/)).toBeVisible();
  const r = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: "nova-palavra-passe-1" }),
  });
  expect(r.ok).toBe(true);
});

test("verificação em dois passos: liga, pede o código ao entrar e o servidor recusa sessões sem código", async ({ page }) => {
  const email = `mfa-${stamp}@e2e.test`;
  await newUser(email);
  await login(page, email);
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
  await page.goto(`/c/${WS_A}/perfil`);
  await page.getByRole("button", { name: "Ligar" }).click();
  const secret = (await page.locator("code").first().textContent())!.trim();
  await page.locator("#mfa-code").fill(totp(secret));
  await page.getByRole("button", { name: "Confirmar" }).click();
  await expect(page.getByText(/Ligada\. Da próxima vez/)).toBeVisible();

  // servidor: uma sessão só com palavra-passe (aal1) não chega a nada
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  const aal1 = (await t.json()).access_token;
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${aal1}`, "Content-Type": "application/json" };
  const ctx = await (await fetch(`${API_URL}/rest/v1/rpc/my_context`, { method: "POST", headers: h, body: "{}" })).json();
  expect(ctx.mfa_required).toBe(true);
  expect(ctx.workspaces).toEqual([]);
  const team = await fetch(`${API_URL}/rest/v1/rpc/workspace_team`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect(team.ok).toBe(false);
  const rows = await (await fetch(`${API_URL}/rest/v1/guioes?select=id&client_id=eq.${WS_A}`, { headers: h })).json();
  expect(rows).toEqual([]);

  // app: sair, entrar, pede o código; código errado recusa; certo entra
  await page.getByRole("button", { name: "Menu da conta" }).click();
  await page.getByRole("menuitem", { name: "Sair" }).click();
  await page.waitForURL(/\/login/);
  await login(page, email);
  await expect(page.getByRole("heading", { name: "Verificação em dois passos" })).toBeVisible();
  await page.goto(`/c/${WS_A}/guioes`);
  await page.waitForURL(/\/login\?mfa=1/);
  await page.locator("#otp").fill("000000");
  await page.getByRole("button", { name: "Verificar" }).click();
  await expect(page.getByText(/Código errado/)).toBeVisible();
  await page.locator("#otp").fill(totp(secret));
  await page.getByRole("button", { name: "Verificar" }).click();
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
  await expect(page.getByRole("heading", { name: "Guiões" })).toBeVisible();
  await page.goto(`/c/${WS_B}`);
  await expect(page.getByText("Não tens acesso a este cliente, ou ele não existe.")).toBeVisible();
});
