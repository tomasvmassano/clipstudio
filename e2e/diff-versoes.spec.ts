import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W10-13 (FR-02-06, FR-05-06, FR-05-07): comparar duas versões de um guião palavra a palavra e restaurar pelo servidor.
// A aprovação fica presa à versão aprovada; o cliente B não lê nem restaura nada de A.
test.describe.configure({ mode: "serial" });

const GID = "numeiro-2026-10-28-13";
const PENDING = "supabase/migrations/PENDING_w10_diff_versoes.sql";
const tag = `e2edf${Date.now() % 1_000_000}`;
let original = "";
let approvedId = "";

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

test.beforeAll(async () => {
  // A stack local só aplica migrações com carimbo; a desta PR ainda é PENDING_ (idempotente: create or replace).
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  original = sql(`select corpo from guioes where id = '${GID}'`)[0];
  const h = await token(users.clientA);
  // v1 aprovada (texto original); depois o texto muda e é submetido com motivo (v2)
  if (sql(`select editorial_status from guioes where id = '${GID}'`)[0] !== "approved")
    expect((await rpc(h, "content_transition", { p_id: GID, p_to: "approved" })).ok).toBe(true);
  approvedId = sql(`select approved_version_id from guioes where id = '${GID}'`)[0];
  const r = await rpc(h, "content_save", { p_id: GID, p_patch: { corpo: `Corpo reescrito ${tag}, sem pressa!` } });
  expect(r.ok).toBe(true);
  expect((await rpc(h, "content_transition", { p_id: GID, p_to: "in_review", p_reason: `mais curto ${tag}` })).ok).toBe(true);
});

as("clientA")("compara versões palavra a palavra e restaura sem tocar na aprovada", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/guioes`);
  const card = page.locator(`[data-guiao="${GID}"]`);
  await card.getByRole("button", { name: "Histórico" }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByText(`“mais curto ${tag}”`).first()).toBeVisible();
  await sheet.getByRole("tab", { name: "Comparar" }).click();
  const cmp = sheet.getByTestId("version-compare");
  await expect(cmp).toBeVisible();

  // lado a lado: antes = aprovada, depois = em vigor; corpo alterado com marcadores e texto para leitores de ecrã
  const corpo = cmp.locator('[data-field="corpo"]');
  await expect(corpo).toHaveAttribute("data-status", "changed");
  await expect(corpo.getByLabel("antes").locator("del").first()).toContainText("−");
  await expect(corpo.getByLabel("depois").locator("ins").filter({ hasText: tag })).toContainText("+");
  await expect(corpo.locator("del .sr-only").first()).toHaveText("[removido: ");
  await expect(cmp.getByText(/campos? mud/)).toBeVisible();
  await expect(cmp.getByText("aprovada", { exact: true }).first()).toBeVisible();

  // em linha: os dois lados no mesmo parágrafo
  await cmp.getByRole("button", { name: "Em linha" }).click();
  await expect(cmp.getByRole("button", { name: "Em linha" })).toHaveAttribute("aria-pressed", "true");
  await expect(corpo.locator("p")).toHaveCount(1);

  // restaurar a aprovada pede confirmação e passa pelo servidor
  await cmp.getByRole("button", { name: "Restaurar esta versão" }).first().click();
  await expect(cmp.getByRole("alertdialog")).toContainText("Nenhuma versão é apagada");
  await cmp.getByRole("alertdialog").getByRole("button", { name: "Restaurar", exact: true }).click();
  await expect(sheet.getByText(/está agora na cópia de trabalho/)).toBeVisible();
  expect(sql(`select corpo from guioes where id = '${GID}'`)[0]).toBe(original);
  expect(sql(`select approved_version_id from guioes where id = '${GID}'`)[0]).toBe(approvedId);
  expect(sql(`select corpo from content_versions where id = '${approvedId}'`)[0]).toBe(original);
  expect(sql(`select count(*) from audit_events where entity_id = '${GID}' and action = 'script.version_restored'`)[0]).not.toBe("0");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("cliente B não lê o histórico nem restaura versões de A", async () => {
  const h = await token(users.clientB);
  const r1 = await rpc(h, "content_history", { p_id: GID });
  expect(r1.status).toBeGreaterThanOrEqual(400);
  expect((await r1.json()).code).toBe("42501");
  const r2 = await rpc(h, "content_restore_version", { p_id: GID, p_version: approvedId });
  expect(r2.status).toBeGreaterThanOrEqual(400);
  expect((await r2.json()).code).toBe("42501");
  expect(sql(`select corpo from guioes where id = '${GID}'`)[0]).toBe(original);
});
