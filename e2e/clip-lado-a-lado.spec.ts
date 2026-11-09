import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";

// W10-24 (CLIP-06, ADR-0073): no editor, um corte do Clip Miner mostra o original (ordem do master) ao lado do cortado
// (ordem da versão aberta), com o que foi movido e o que foi cortado, e clicar num trecho leva a pré-visualização até ele.
// O documento v1 é escrito aqui como o worker o grava (engine/clips.py build_doc; o insert é o de clips_worker_save).
test.describe.configure({ mode: "serial" });

const tag = `e2ecl${Date.now() % 1_000_000}`;
let asset = "";
let plain = "";

const w = (id: string, word: string, s: number, e: number) => ({ id, w: word, s, e });
const base = {
  schema: 1, fps: 30, size: [1080, 1920], style: "S15",
  source: { kind: "long", time: "session", windows: null, cams: { front: `master-${tag}.mp4` }, audio: "front", offsets: { front: 0 } },
  captions: { words: [w("w1", "Primeira", 30.2, 35), w("w2", "frase.", 35, 37), w("w3", "Segunda", 37.5, 41.8),
    w("w4", `Gancho ${tag}!`, 42.1, 45.9), w("w5", "Quarta", 46.2, 50), w("w6", "frase", 50, 54.8)] },
  cameras: [{ s: 30, e: 55, cam: "front", zoom: 1 }], hook: { text: `Título ${tag}` }, notes: [],
  overlays: [{ id: "cta", kind: "text", label: "Vê o episódio completo", asset: null, s: 53.5, e: 55 }],
  audio: { music: null, sfx: [], gains: [] },
};

function insertDoc(title: string, doc: object) {
  const a = sql(`insert into media_assets (workspace_id, kind, title, tags) values ('${WS_A}', 'video', '${title}', array['corte']) returning id`)[0];
  const d = sql(`insert into edit_documents (workspace_id, asset_id) values ('${WS_A}', '${a}') returning id`)[0];
  const v = sql(`insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
                 values ('${WS_A}', '${d}', 1, '${JSON.stringify(doc).replace(/'/g, "''")}'::jsonb, 'ai', 'Clip Miner') returning id`)[0];
  sql(`update edit_documents set current_version_id = '${v}' where id = '${d}'`);
  return a;
}

test.beforeAll(() => {
  flagsOnForA(["edit.studio", "media.library", "clips.miner"]);
  asset = insertDoc(`Corte ${tag}`, {
    ...base,
    segments: [{ id: "s01", in: 42, out: 46, section: "hook" }, { id: "s02", in: 30, out: 42, section: "body" }, { id: "s03", in: 46, out: 55, section: "body" }],
    ai: { clip: { original: [["f0001", "f0004"]], parts: [["f0003"], ["f0001", "f0002"], ["f0004"]], reordered: true,
      prompt_version: "clip-miner-1", rubric_version: "clip-rubric-1" } },
  });
  // um vídeo editado sem ai.clip: a vista não aparece
  plain = insertDoc(`Pacote ${tag}`, { ...base, segments: [{ id: "s01", in: 30, out: 55, section: "hook" }] });
});
test.afterAll(() => restoreFlags());

as("clientA")("original vs. cortado: movido, cortado depois de tirar um trecho, e clicar leva a pré-visualização", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/editor?asset=${asset}`);
  const view = page.getByTestId("clip-order");
  await expect(view.getByRole("heading", { name: "Original vs. cortado" })).toBeVisible();
  await expect(view.getByText("Trecho do master 0:30-0:55.")).toBeVisible();
  await expect(view.getByText(/A IA passou o gancho para o início \(3 trechos/)).toBeVisible();
  const original = view.getByRole("list", { name: "Original, pela ordem do master" });
  const cut = view.getByRole("list", { name: "Cortado, pela ordem em que se ouve" });
  await expect(original.getByRole("button")).toHaveCount(3);
  await expect(cut.getByRole("button").first()).toContainText("movido de 2.º para 1.º");
  await expect(cut.getByRole("button").first()).toContainText(`Gancho ${tag}!`);
  await expect(original.getByRole("button").first()).toContainText("0:30-0:42");
  await expect(view.getByText("1 movido")).toBeVisible();
  await expect(view.getByText("0 cortados")).toBeVisible();

  // clicar no 3.º do cortado leva o cursor ao início dele na saída (4 s + 12 s = 0:16.0)
  await cut.getByRole("button").nth(2).click();
  await expect(page.getByText("0:16.0 / 0:25.0")).toBeVisible();
  await expect(cut.getByRole("button").nth(2)).toHaveAttribute("aria-current", "true");
  // teclado: Tab até ao 1.º do original e Enter
  await original.getByRole("button").first().focus();
  await page.keyboard.press("Enter");
  await expect(page.getByText("0:04.0 / 0:25.0")).toBeVisible();

  // tirar o último trecho na linha do tempo: passa a "cortado" com os tempos do master, sem botão (não está na saída)
  await page.locator('[role="button"][title="3"]').first().click();
  await page.getByRole("button", { name: "Tirar corte" }).click();
  await expect(view.getByText("1 cortado", { exact: true })).toBeVisible();
  await expect(original.getByRole("listitem").last()).toContainText("cortado: 0:46-0:54");
  await expect(original.getByRole("button")).toHaveCount(2);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("modo guiado: a mesma vista, só leitura, no passo Corte", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/editor?asset=${asset}&modo=guiado`);
  await page.getByRole("tab", { name: /Corte/ }).click();
  const view = page.getByTestId("clip-order");
  await expect(view.getByRole("heading", { name: "Original vs. cortado" })).toBeVisible();
  await view.getByRole("list", { name: "Cortado, pela ordem em que se ouve" }).getByRole("button").nth(1).click();
  await expect(page.getByText("0:04.0 / 0:25.0")).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("sem ai.clip a vista não aparece; a 390 px as colunas empilham", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/editor?asset=${plain}`);
  await expect(page.getByText("Linha do tempo", { exact: true })).toBeVisible();
  await expect(page.getByTestId("clip-order")).toHaveCount(0);

  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto(`/c/${WS_A}/editor?asset=${asset}`);
  const view = page.getByTestId("clip-order");
  await expect(view).toBeVisible();
  const o = await view.getByRole("list", { name: "Original, pela ordem do master" }).boundingBox();
  const c = await view.getByRole("list", { name: "Cortado, pela ordem em que se ouve" }).boundingBox();
  expect(c!.y).toBeGreaterThan(o!.y + o!.height - 1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  expect(errors).toEqual([]);
});

test("cliente B não lê o documento do corte de A", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const r = await fetch(`${API_URL}/rest/v1/rpc/edit_doc_get`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_asset: asset }) });
  expect(r.status).toBeGreaterThanOrEqual(400);
});
