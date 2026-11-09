import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash, sidebar } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";

// W10-22 (ADR-0071), decisões do dono de 2026-11-09: a equipa do cliente não vê custos (FR-10-01); etiquetar ia-* na
// Biblioteca pede a declaração de direitos e fica no histórico (EDL-07/EDL-11); a equipa do cliente lê as regras da
// agência em vigor, só leitura (LRN-04).
test.describe.configure({ mode: "serial" });

const PENDING = "supabase/migrations/PENDING_w10_decisoes_dono.sql";   // já aplicada e com versão: o supabase start aplica-a; só um PENDING_ se aplica aqui
const tag = `e2edd${Date.now() % 1_000_000}`;
let asset = "";
let prevAgency = "";
let newAgency = "";

test.beforeAll(() => {
  // A stack local só aplica migrações com carimbo; a desta PR ainda é PENDING_ (idempotente: create or replace).
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  flagsOnForA(["media.library", "learn.lessons", "costs.content"]);
  asset = sql(`insert into media_assets (workspace_id, kind, title, tags) values ('${WS_A}', 'imagem', 'Ferrari ${tag}', array['dubai']) returning id`)[0];
  prevAgency = sql(`select coalesce((select id::text from lrn_lesson_versions where level = 'agency' and active
                      and organization_id = (select organization_id from clients where id = '${WS_A}')), '')`)[0] ?? "";
  newAgency = sql(`select (public._lrn_new_version('agency', (select organization_id from clients where id = '${WS_A}'), null,
                     jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'category', 'hook', 'text', 'Regra da agência ${tag}')),
                     '{"action":"approve"}'::jsonb, '{"kind":"system","label":"e2e"}'::jsonb)).id`)[0];
});

test.afterAll(() => {
  sql(`update lrn_lesson_versions set active = false where id = '${newAgency}'`);
  if (prevAgency) sql(`update lrn_lesson_versions set active = true where id = '${prevAgency}'`);
  restoreFlags();
});

async function headers(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}

as("clientA")("equipa do cliente: sem Custos no menu, na página e na API", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/custos`);
  await expect(page.getByText("Não tens permissão para esta página neste cliente.", { exact: false })).toBeVisible();
  await expect(sidebar(page).getByRole("link", { name: "Custos" })).toHaveCount(0);
  const r = await fetch(`${API_URL}/rest/v1/rpc/costs_ai_usage`, { method: "POST", headers: await headers(users.clientA), body: JSON.stringify({ p_ws: WS_A, p_days: 7 }) });
  expect(r.ok).toBe(false);
  expect((await r.json()).code).toBe("42501");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("owner")("dono da agência continua a ver os custos do cliente", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/custos`);
  await expect(page.getByRole("heading", { name: "Consumo de IA" })).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("etiqueta ia-imagem pede a declaração de direitos e fica no histórico", async ({ page, errors }) => {
  // sem confirmação o servidor recusa (o botão também fica desligado)
  const h = await headers(users.clientA);
  const bad = await fetch(`${API_URL}/rest/v1/rpc/media_asset_save`, { method: "POST", headers: h,
    body: JSON.stringify({ p_ws: WS_A, p_id: asset, p_fields: { tags: ["dubai", "ia-imagem"] } }) });
  expect((await bad.json()).code).toBe("22023");

  await page.goto(`/c/${WS_A}/biblioteca?asset=${asset}`);
  const tags = page.getByLabel("Etiquetas");
  await tags.fill("dubai ia-imagem");
  await expect(page.getByText(/deixa a IA\s+usar este ficheiro/)).toBeVisible();
  const save = page.getByRole("button", { name: "Guardar" });
  await expect(save).toBeDisabled();
  await page.getByLabel("Confirmo que o cliente tem direitos para a IA usar este ficheiro.").check();
  await expect(save).toBeEnabled();
  await save.click();
  await expect(page.getByText("Guardado.", { exact: true })).toBeVisible();
  await expect.poll(() => sql(`select count(*) from audit_events where action = 'media.ai_rights_declared' and entity_id = '${asset}'
    and after->'tags' = '["ia-imagem"]' and (after->>'confirmed')::boolean`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

as("clientA")("lições: regras da agência em vigor, só leitura", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/aprendizagem/licoes`);
  const sec = page.getByRole("region", { name: /Regras da agência/ });
  await expect(sec).toBeVisible();
  await expect(sec.getByText(`Regra da agência ${tag}`)).toBeVisible();
  await expect(sec.getByRole("button")).toHaveCount(0);
  expect(errors).toEqual([]);
});
