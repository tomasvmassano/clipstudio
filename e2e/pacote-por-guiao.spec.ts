import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W10-20 (STU-03; ADR-0070): pacote de um guião a partir das gravações curtas desse guião (frente + lado), ligadas na
// Biblioteca. As gravações são semeadas por SQL já verificadas (o worker e o R2 não existem na stack local); o pedido, a
// ligação e as negações passam pelas RPCs reais. O cliente B não liga nem pede nada no cliente A.
test.describe.configure({ mode: "serial" });

const PENDING = "supabase/migrations/20261106131955_w10_pacote_por_guiao.sql";
const tag = `e2epg${Date.now() % 1_000_000}`;
const GID = `${WS_A}-2026-10-28-21`;
const FLAGS = ["media.library", "edit.studio", "media.r2", "edit.package_script"];
let savedFlags: string[] = [];
const ids: Record<"front" | "side", string> = { front: "", side: "" };
// a ficha pré-visualiza a versão R2 pronta; o R2 não está configurado na stack local/CI: o único erro esperado é esse 503,
// e o ecrã mostra-o (mesmo padrão de e2e/review-stored.spec.ts)
const R2_OFF = /O armazenamento de vídeo \(R2\) ainda não está configurado no servidor\./;
const only503 = (errors: string[]) => errors.filter((e) => !/Failed to load resource: the server responded with a status of 503/.test(e));

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

/** Gravação de vídeo no R2 já verificada (como o worker a deixa). */
function recording(name: string) {
  const a = sql(`insert into media_assets (workspace_id, kind, title, tags, created_label) values ('${WS_A}', 'video', '${name}', '{}', 'E2E') returning id`)[0];
  const path = `${WS_A}/e2e/${tag}/${name}`;
  const v = sql(`insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_provider, storage_bucket, storage_path,
                                             original_name, size_bytes, mime, sha256)
                 values ('${WS_A}', '${a}', 1, 'upload', 'pendente', 'r2', 'r2', '${path}', '${name}', 1234, 'video/mp4', repeat('a', 64)) returning id`)[0];
  sql(`update media_versions set state = 'pronta', checksum_verified = true, checksum_verified_at = now(), completed_at = now(),
         media_info = '{"duration": 75}'::jsonb where id = '${v}'`);
  sql(`update media_assets set current_version_id = '${v}' where id = '${a}'`);
  return a;
}

test.beforeAll(async () => {
  // A stack local só aplica migrações com carimbo; a desta PR ainda é PENDING_ (idempotente).
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  savedFlags = sql(`select key || '=' || stage from feature_flags where workspace_id = '${WS_A}' and key in (${FLAGS.map((f) => `'${f}'`).join(",")})`);
  sql(`delete from feature_flags where workspace_id in ('${WS_A}', '${WS_B}') and key in (${FLAGS.map((f) => `'${f}'`).join(",")});
       insert into feature_flags (key, organization_id, workspace_id, stage)
         select k, o.id, w, 'all' from organizations o, unnest(array[${FLAGS.map((f) => `'${f}'`).join(",")}]) k, unnest(array['${WS_A}', '${WS_B}']) w
          where o.slug = 'clipstudio'`);
  ids.front = recording(`${tag}_g21_frente.mp4`);
  ids.side = recording(`${tag}_g21_lado.mp4`);
  const h = await token(users.clientA);
  for (const cam of ["front", "side"] as const) {
    const r = await rpc(h, "media_clip_link", { p_ws: WS_A, p_asset: ids[cam], p_guiao: GID, p_camera: cam, p_source: "biblioteca" });
    expect(r.ok).toBe(true);
  }
});

test.afterAll(() => {
  sql(`delete from feature_flags where workspace_id in ('${WS_A}', '${WS_B}') and key in (${FLAGS.map((f) => `'${f}'`).join(",")})`);
  for (const kv of savedFlags) {
    const [k, stage] = kv.split("=");
    sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${k}', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
  }
});

as("clientA")("guião com as duas gravações: pedir o pacote só desse guião", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/edicao-automatica`);
  const section = page.getByRole("region", { name: "Pacote por guião" });
  await expect(section).toBeVisible();
  const row = section.getByRole("listitem").filter({ hasText: `${tag}_g21_frente.mp4` });
  await expect(row).toContainText(`${tag}_g21_lado.mp4`);
  await expect(row.getByText("pronto para o pacote")).toBeVisible();
  await row.getByRole("button", { name: "Criar pacote deste guião" }).click();
  await expect(row.getByText("pacote na fila")).toBeVisible();
  const job = sql(`select input->>'mode' || '|' || jsonb_array_length(input->'guioes') || '|' || (input->'front'->>'name') from media_jobs
                   where kind = 'package' and input->>'guiao_id' = '${GID}' and input->'front'->>'name' = '${tag}_g21_frente.mp4'`);
  expect(job).toEqual([`script|1|${tag}_g21_frente.mp4`]);
  // o pacote por guião não aparece na lista dos pacotes da sessão
  await expect(page.getByRole("region", { name: "Pacotes" }).getByText(`${tag}_g21_frente.mp4`)).toHaveCount(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("ficha do ficheiro mostra de que guião e câmara é a gravação", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/biblioteca?asset=${ids.side}`);
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: "Gravação de um guião" })).toBeVisible();
  await expect(sheet.getByText(/Câmara lado \(com o som\) do guião ligado/)).toBeVisible();
  await expect(sheet.getByText(R2_OFF)).toBeVisible();
  await expectNoCrash(page);
  expect(only503(errors)).toEqual([]);
});

test("cliente B não liga gravações nem pede pacotes no cliente A", async () => {
  const h = await token(users.clientB);
  const r1 = await rpc(h, "media_clip_link", { p_ws: WS_A, p_asset: ids.front, p_guiao: GID, p_camera: "side" });
  expect(r1.status).toBeGreaterThanOrEqual(400);
  const r2 = await rpc(h, "edit_package_script_request", { p_ws: WS_A, p_guiao: GID });
  expect(r2.status).toBeGreaterThanOrEqual(400);
  const r3 = await rpc(h, "edit_package_script_list", { p_ws: WS_A });
  expect(r3.status).toBeGreaterThanOrEqual(400);
  const r4 = await rpc(h, "package_script_settings_set", { p_ws: WS_A, p_auto_package: true, p_auto_export: true });
  expect(r4.status).toBeGreaterThanOrEqual(400);
  expect(sql(`select count(*) from recording_clips where asset_id = '${ids.front}' and camera = 'front'`)).toEqual(["1"]);
});
