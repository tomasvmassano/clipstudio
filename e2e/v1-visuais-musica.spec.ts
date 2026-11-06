import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";

// W10-18 (EDL-07, ADR-0068): a versão 1 do pacote traz visuais e música escolhidos pela IA; o editor mostra o que a IA
// escolheu e porquê, o que ficou vazio e porquê, e deixa trocar, tirar e mudar a posição de um visual (versão nova).
// O documento v1 é escrito aqui como o worker o grava (media_worker_package_save faz o mesmo insert, testado em SQL).
test.describe.configure({ mode: "serial" });

const PENDING = "supabase/migrations/PENDING_w10_v1_visuais_musica.sql";
const tag = `e2evm${Date.now() % 1_000_000}`;
let asset = "";
let img = "";

test.beforeAll(() => {
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  flagsOnForA(["edit.studio", "media.library", "edit.ai_visuals"]);
  // imagem da biblioteca autorizada para a IA (etiqueta ia-imagem); só a referência importa para o editor
  img = sql(`insert into media_assets (workspace_id, kind, title, tags) values ('${WS_A}', 'imagem', 'Ferrari ${tag}', array['ia-imagem']) returning id`)[0];
  asset = sql(`insert into media_assets (workspace_id, kind, title, tags) values ('${WS_A}', 'video', 'Pacote ${tag}', array['pacote','hook_2']) returning id`)[0];
  const doc = {
    schema: 1, fps: 30, size: [1080, 1920], style: "S15",
    segments: [{ id: "s01", in: 0, out: 3, section: "hook" }, { id: "s02", in: 5, out: 12, section: "body" }],
    captions: { words: [{ id: "w1", w: "Olá", s: 0.5, e: 1 }, { id: "w2", w: "corpo", s: 5.5, e: 6 }] },
    cameras: [], hook: { text: `Hook ${tag}` }, notes: [],
    overlays: [
      { id: "ai_img", kind: "graphic", label: `Ferrari ${tag}`, asset: img, s: 5, e: 8, box: [108, 500, 864, 560] },
      { id: "ai_frase", kind: "text", label: "O homem mais rico de Portugal", asset: null, s: 5, e: 8, box: [120, 230, 840, 220] },
    ],
    audio: { music: null, sfx: [], gains: [] },
    ai: { visuals: { version: 1, recipe: "imagem_frase", persona_version: 2, phrase_options: ["O homem mais rico de Portugal", "O rei do Dubai"],
      picks: [
        { slot: "imagem", overlays: ["ai_img"], asset: img, label: `Ferrari ${tag}`, why: `Título ou etiquetas em comum com o guião: ferrari ${tag}.` },
        { slot: "frase", overlays: ["ai_frase"], asset: null, label: "O homem mais rico de Portugal", why: "Frase da lista aprovada v2 (R-17)." },
      ],
      empty: [{ slot: "musica", why: "Sem música: o estilo pedido não tem música e não há áudio com a etiqueta ia-musica na Biblioteca." }] } },
  };
  const d = sql(`insert into edit_documents (workspace_id, asset_id) values ('${WS_A}', '${asset}') returning id`)[0];
  const v = sql(`insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
                 values ('${WS_A}', '${d}', 1, '${JSON.stringify(doc).replace(/'/g, "''")}'::jsonb, 'ai', 'IA') returning id`)[0];
  sql(`update edit_documents set current_version_id = '${v}' where id = '${d}'`);
});
test.afterAll(() => restoreFlags());

as("clientA")("o editor mostra as escolhas da IA e porquê; tirar e mudar a posição gravam versão nova", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/editor?asset=${asset}`);
  const panel = page.getByRole("region", { name: "Escolhas da IA" });
  await expect(panel.getByText("Escolhas da IA na versão 1")).toBeVisible();
  await expect(panel.getByText("Imagem + frase-persona")).toBeVisible();
  await expect(panel.getByText(`Porquê: Título ou etiquetas em comum com o guião: ferrari ${tag}.`)).toBeVisible();
  await expect(panel.getByText("Porquê: Frase da lista aprovada v2 (R-17).")).toBeVisible();
  await expect(panel.getByText(/Porquê: Sem música: .*ia-musica/)).toBeVisible();
  await expect(panel.getByText("vazio", { exact: true })).toBeVisible();

  // trocar a frase só por outra da lista aprovada
  const trocar = panel.getByLabel("Trocar Frase-persona");
  await expect(trocar.locator("option")).toContainText(["Trocar por…", "O homem mais rico de Portugal", "O rei do Dubai"]);
  await trocar.selectOption("O rei do Dubai");
  await expect(panel.getByText("trocada por ti")).toBeVisible();
  // tirar a imagem
  await panel.locator("li").filter({ hasText: `Ferrari ${tag}` }).getByRole("button", { name: "Tirar" }).click();
  await expect(panel.getByText("tirada", { exact: true })).toBeVisible();

  // posição de um visual: a frase passa para cima das legendas
  await page.getByText("O rei do Dubai", { exact: true }).last().waitFor();
  await page.getByRole("button", { name: /^Ver aos/ }).first().click();
  const track = page.locator('[title="O rei do Dubai"]').first();
  await track.click();
  await page.getByLabel("Posição do visual").selectOption("lower");
  await page.getByRole("button", { name: /Gravar versão 2/ }).click();
  await expect(page.getByText(/Versão 2 \(editada/)).toBeVisible();
  const saved = JSON.parse(sql(`select v.doc::text from edit_documents d join edit_versions v on v.id = d.current_version_id where d.asset_id = '${asset}'`)[0]);
  expect(saved.overlays).toEqual([{ id: "ai_frase", kind: "text", label: "O rei do Dubai", asset: null, s: 5, e: 8, box: [120, 1100, 840, 200] }]);
  expect(sql(`select count(*) from edit_versions v join edit_documents d on d.id = v.document_id where d.asset_id = '${asset}' and v.version_no = 1 and jsonb_array_length(v.doc->'overlays') = 2`)[0]).toBe("1");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("modo guiado: só mostra as escolhas e os motivos", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/editor?asset=${asset}&modo=guiado`);
  await page.getByRole("tab", { name: "Visual e música" }).click();
  const panel = page.getByRole("region", { name: "Escolhas da IA" });
  await expect(panel.getByText(/Porquê: Sem música/)).toBeVisible();
  await expect(panel.getByRole("button", { name: "Tirar" })).toHaveCount(0);
  expect(errors).toEqual([]);
});

test("cliente B não lê o documento de A nem pede o pacote de A", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const r = await fetch(`${API_URL}/rest/v1/rpc/edit_doc_get`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_asset: asset }) });
  expect(r.status).toBeGreaterThanOrEqual(400);
  const p = await fetch(`${API_URL}/rest/v1/rpc/edit_package_request`, { method: "POST", headers: h,
    body: JSON.stringify({ p_ws: WS_A, p_front: asset, p_side: img, p_guioes: ["x"] }) });
  expect(p.status).toBeGreaterThanOrEqual(400);
});
