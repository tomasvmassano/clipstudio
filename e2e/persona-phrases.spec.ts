import { test, type Page } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { NO_ACCESS, as, expect, expectNoCrash } from "./helpers";

// W5-14 (R-17, CHG-003; ADR-0053): lista de frases-persona por cliente, versionada. Quem envolve outra pessoa precisa do
// consentimento registado; o manager (staff da agência) só lê; outro cliente não chega lá.
test.describe.configure({ mode: "serial" });

const tag = `e2epp${Date.now() % 1_000_000}`;
const P1 = `O homem mais rico de Portugal ${tag}`;
const P2 = `O melhor amigo do Cristiano ${tag}`;
let base = 0; // versão em vigor antes destes testes (0 numa base nova)

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

async function openTab(page: Page) {
  await page.goto(`/c/${WS_A}/agentes/configuracao`);
  await expect(page.getByRole("heading", { name: "Agentes" })).toBeVisible();
  await page.getByRole("button", { name: "Frases-persona" }).click();
  await expect(page.getByText("Hipérbole sobre o próprio criador")).toBeVisible();
}

test.beforeAll(() => {
  base = Number(sql(`select coalesce(max(version), 0) from persona_lists where workspace_id = '${WS_A}'`)[0]);
});

as("clientA")("admin junta uma frase e grava a versão seguinte", async ({ page, errors }) => {
  await openTab(page);
  await page.getByRole("button", { name: "Juntar frase" }).click();
  await page.getByRole("textbox", { name: /^Frase \d+$/ }).last().fill(P1);
  await page.getByLabel("Nota da versão").fill(`E2E ${tag}`);
  await page.getByRole("button", { name: `Gravar versão ${base + 1}` }).click();
  await expect(page.getByText(`Versão ${base + 1} gravada. As próximas execuções dos agentes usam esta lista.`)).toBeVisible();
  await expect(page.getByText(`versão ${base + 1}`, { exact: true })).toBeVisible();
  expect(sql(`select phrases @> '[{"text": "${P1}"}]' from persona_lists where workspace_id = '${WS_A}' and version = ${base + 1}`)).toEqual(["t"]);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("frase com outra pessoa: bloqueada sem consentimento (UI e servidor), gravada com consentimento; histórico v1/v2", async ({ page, errors }) => {
  await openTab(page);
  await page.getByRole("button", { name: "Juntar frase" }).click();
  const n = await page.getByRole("textbox", { name: /^Frase \d+$/ }).count();
  const field = page.getByRole("textbox", { name: `Frase ${n}`, exact: true });
  const row = page.locator("div.rounded-md.border").filter({ has: field });
  await field.fill(P2);
  await row.getByRole("button", { name: "Outra pessoa" }).click();
  await row.getByLabel("Quem é").fill("Cristiano");
  const save = page.getByRole("button", { name: `Gravar versão ${base + 2}` });
  await expect(page.locator("p[role=alert]")).toHaveText(`Frase ${n} envolve Cristiano: regista o consentimento (quem o deu e em que dia).`);
  await expect(save).toBeDisabled();

  // o servidor recusa o mesmo pedido sem consentimento, mesmo saltando a UI
  const h = await token(users.clientA);
  const current = await (await rpc(h, "persona_list_get", { p_ws: WS_A })).json();
  const bad = await rpc(h, "persona_list_save", {
    p_ws: WS_A, p_expected: base + 1, p_phrases: [...current.phrases, { id: "x99", text: P2, involves: { name: "Cristiano" } }],
  });
  expect(bad.status).toBe(400);
  const err = await bad.json();
  expect(err.code).toBe("22023");
  expect(err.details).toContain("regista o consentimento");
  expect(sql(`select count(*) from persona_lists where workspace_id = '${WS_A}'`)).toEqual([String(base + 1)]);

  await row.getByLabel("Consentimento dado por").fill("Equipa do Cristiano");
  await row.getByLabel("Em que dia").fill("2026-11-01");
  await expect(page.locator("p[role=alert]")).toHaveCount(0);
  await save.click();
  await expect(page.getByText(`Versão ${base + 2} gravada.`, { exact: false })).toBeVisible();
  expect(sql(`select phrases @> '[{"text": "${P2}", "involves": {"name": "Cristiano", "consent_by": "Equipa do Cristiano", "consent_at": "2026-11-01"}}]'
              from persona_lists where workspace_id = '${WS_A}' and version = ${base + 2}`)).toEqual(["t"]);

  // histórico: as duas versões, a mais recente em vigor; abrir a anterior mostra só a primeira frase
  const cur = page.getByRole("button", { name: new RegExp(`^v${base + 2} · \\d+ frases? · em vigor`) });
  const prev = page.getByRole("button", { name: new RegExp(`^v${base + 1} · \\d+ frases?`) });
  await expect(cur).toBeVisible();
  await expect(prev).toBeVisible();
  await expect(prev).toContainText(`E2E ${tag}`);
  await prev.click();
  const old = page.locator("div.border-dashed");
  await expect(old).toContainText(`Versão ${base + 1}`);
  await expect(old).toContainText(P1);
  await expect(old).not.toContainText(P2);
  await expect(old.getByRole("button", { name: "Usar como base" })).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("manager vê a lista só para leitura e o servidor recusa gravar (42501)", async ({ page, errors }) => {
  await openTab(page);
  const first = page.getByRole("textbox", { name: /^Frase \d+$/ }).first();
  await expect(first).toBeDisabled();
  await expect(page.getByRole("textbox", { name: /^Frase \d+$/ }).last()).toBeDisabled();
  await expect(page.getByRole("button", { name: "Juntar frase" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Outra pessoa" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: /^Gravar versão/ })).toHaveCount(0);
  await expect(page.getByText("Só quem tem “Aprovar frases-persona” muda esta lista.")).toBeVisible();
  await expect(page.getByRole("button", { name: new RegExp(`^v${base + 2} · .* em vigor`) })).toBeVisible();
  await page.getByRole("button", { name: new RegExp(`^v${base + 1} · `) }).click();
  await expect(page.locator("div.border-dashed")).toContainText(P1);
  await expect(page.getByRole("button", { name: "Usar como base" })).toHaveCount(0);

  const r = await rpc(await token(users.staff), "persona_list_save", { p_ws: WS_A, p_expected: base + 2, p_phrases: [] });
  expect(r.status).toBe(403);
  expect((await r.json()).code).toBe("42501");
  expect(sql(`select max(version) from persona_lists where workspace_id = '${WS_A}'`)).toEqual([String(base + 2)]);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientB")("outro cliente não abre nem lê a lista de A", async ({ page }) => {
  await page.goto(`/c/${WS_A}/agentes/configuracao`);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
  await expect(page.getByText(tag)).toHaveCount(0);
  const h = await token(users.clientB);
  for (const [fn, args] of [
    ["persona_list_get", { p_ws: WS_A }],
    ["persona_list_version", { p_ws: WS_A, p_version: base + 1 }],
    ["persona_list_save", { p_ws: WS_A, p_expected: base + 2, p_phrases: [] }],
  ] as const) {
    const r = await rpc(h, fn, args);
    expect(r.status, fn).toBe(403);
    expect((await r.json()).code, fn).toBe("42501");
  }
});
