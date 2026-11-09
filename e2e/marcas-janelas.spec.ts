import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W10-17 (ING-03, EDL-01, EDL-08): a página Edição automática mostra, por guião, de onde veio a janela na gravação longa
// (marcas do teleprompter ou só a transcrição, e porquê). Só com a flag edit.package_marks; o cliente B não vê pacotes de A.
test.describe.configure({ mode: "serial" });

const PENDING = "supabase/migrations/PENDING_w10_marcas_janelas.sql";   // já aplicada e com versão: o supabase start aplica-a; só um PENDING_ se aplica aqui
const tag = `e2emj${Date.now() % 1_000_000}`;
let g1 = "", g2 = "";

test.beforeAll(async () => {
  // A stack local só aplica migrações com carimbo; a desta PR ainda é PENDING_ (idempotente).
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  [g1, g2] = sql(`select id from guioes where client_id = '${WS_A}' and deleted_at is null order by date, n limit 2`);
  const guioes = JSON.stringify([{ id: g1, n: 1, tema: `Casas ${tag}` }, { id: g2, n: 2, tema: `Ouro ${tag}` }]);
  const windows = JSON.stringify({
    clock: { ok: true, method: "transcricao+hora_do_ficheiro", anchors: 2, support: 2, session: null },
    items: {
      [g1]: { source: "marks", reason: null, windows: [[14, 95.5]], passes: 2, takes: 2, agree: true, hooks: ["hook_1", "hook_2"] },
      [g2]: { source: "transcript", reason: "sem_marcas", windows: [[200, 320]], passes: 0, takes: 0, agree: null, hooks: [] },
    },
  });
  // um pacote acabado tal como o worker novo o deixa (result.windows) e um de um worker anterior (sem windows)
  sql(`insert into media_jobs (workspace_id, kind, idempotency_key, input, status, result, created_label, finished_at)
       values ('${WS_A}', 'package', '${tag}-novo', jsonb_build_object('front', jsonb_build_object('name', 'Frente ${tag}.mp4'),
               'side', jsonb_build_object('name', 'Lado.mp4'), 'guioes', '${guioes}'::jsonb), 'done',
               jsonb_build_object('documents', '[]'::jsonb, 'missing', '[]'::jsonb, 'windows', '${windows}'::jsonb), 'e2e', now()),
              ('${WS_A}', 'package', '${tag}-antigo', jsonb_build_object('front', jsonb_build_object('name', 'Antigo ${tag}.mp4'),
               'side', jsonb_build_object('name', 'Lado.mp4'), 'guioes', '${guioes}'::jsonb), 'done',
               jsonb_build_object('documents', '[]'::jsonb), 'e2e', now() - interval '1 minute') returning id`);
});

test.afterAll(() => {
  sql(`delete from feature_flags where key = 'edit.package_marks' and workspace_id = '${WS_A}' returning id`);
});

as("owner")("dono vê a origem das janelas por guião (marcas ou transcrição, e porquê)", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/edicao-automatica`);
  const row = page.locator("div.rounded-md.border").filter({ hasText: `Frente ${tag}.mp4` });
  const summary = row.getByText("Janelas por guião: 1 de 2 pelas marcas do teleprompter");
  await expect(summary).toBeVisible();
  await summary.focus();
  await page.keyboard.press("Enter");     // <details> abre pelo teclado
  await expect(row.getByText("Marcas do teleprompter acertadas com a câmara pela transcrição, confirmado pela hora da câmara (2 de 2 guiões a concordar).")).toBeVisible();
  const li1 = row.locator("li").filter({ hasText: `Casas ${tag}` });
  await expect(li1).toContainText("marcas do teleprompter");
  await expect(li1).toContainText("2 passagens · hooks 1, 2 · 2 takes marcados");
  await expect(li1).toContainText("0:14-1:36");
  const li2 = row.locator("li").filter({ hasText: `Ouro ${tag}` });
  await expect(li2).toContainText("transcrição");
  await expect(li2).toContainText("o teleprompter não registou leituras deste guião");
  // pacote de um worker anterior: diz que não há registo, não inventa
  await expect(page.locator("div.rounded-md.border").filter({ hasText: `Antigo ${tag}.mp4` })
    .getByText("Este pacote foi feito antes de o worker registar a origem das janelas por guião.")).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("owner")("flag desligada no cliente: a página fica como antes", async ({ page, errors }) => {
  const org = sql(`select organization_id from clients where id = '${WS_A}'`)[0];
  sql(`insert into feature_flags (key, organization_id, workspace_id, stage) values ('edit.package_marks', '${org}', '${WS_A}', 'off') returning id`);
  await page.goto(`/c/${WS_A}/edicao-automatica`);
  await expect(page.getByText(`Frente ${tag}.mp4`, { exact: false })).toBeVisible();
  await expect(page.getByText(/Janelas por guião/)).toHaveCount(0);
  await expect(page.getByText(/antes de o worker registar/)).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("cliente B não lê os pacotes (nem as janelas) de A", async () => {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const r = await fetch(`${API_URL}/rest/v1/rpc/edit_package_list`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A }) });
  expect(r.status).toBeGreaterThanOrEqual(400);
  expect(JSON.stringify(await r.json())).not.toContain(tag);
  const m = await fetch(`${API_URL}/rest/v1/rpc/_package_marks`, { method: "POST", headers: h, body: JSON.stringify({ p_ws: WS_A, p_guioes: [g1] }) });
  expect(m.status).toBeGreaterThanOrEqual(400);   // função interna sem EXECUTE para authenticated
});
