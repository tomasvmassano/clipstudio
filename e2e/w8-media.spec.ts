import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";

// W8 (ADR-0038): biblioteca de media com o Supabase Storage real da stack local. Envio com progresso e retentativa
// (FR-08-01), caminho gerado no servidor e SHA-256 conferido, filtros (FR-08-02), pré-visualização e links temporários
// (FR-08-03), versões (FR-08-04), tipos e quota (FR-08-05), lixo, órfãos e eliminação definitiva (FR-08-06).
test.describe.configure({ mode: "serial" });

const tag = `e2e${Date.now() % 1_000_000}`;
const fileName = `${tag}-capa.png`;
// PNG 1x1 válido
const PNG = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==", "base64");

function setFlag(stage: "all" | null) {
  sql(`delete from feature_flags where key = 'media.library' and workspace_id in ('${WS_A}', '${WS_B}')`);
  if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select 'media.library', id, w, '${stage}' from organizations, unnest(array['${WS_A}', '${WS_B}']) w where slug = 'clipstudio'`);
}
const asset = () => sql(`select a.id from media_assets a join media_versions v on v.asset_id = a.id where a.workspace_id = '${WS_A}' and v.original_name = '${fileName}' order by a.created_at desc limit 1`)[0];
const version = (a: string) => sql(`select id || '|' || storage_path || '|' || state || '|' || checksum_verified from media_versions where asset_id = '${a}' order by version_no desc limit 1`)[0]?.split("|") ?? [];

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

test.beforeAll(() => setFlag(null));
test.afterAll(() => setFlag(null));

as("clientA")("com a flag desligada a biblioteca não abre", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/biblioteca`);
  await expect(page.getByText("Esta funcionalidade ainda está em teste e não está ligada para ti.")).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("API: com a flag desligada o módulo recusa (55000)", async () => {
  const r = await rpc(await token(users.clientA), "media_library", { p_ws: WS_A });
  expect(r.status).not.toBe(200);
  expect((await r.json()).code).toBe("55000");
});

as("clientA")("cliente A carrega uma imagem: progresso, retentativa depois de falha de rede, SHA-256 conferido", async ({ page, errors }) => {
  setFlag("all");
  await page.goto(`/c/${WS_A}/biblioteca`);
  await expect(page.getByRole("heading", { name: "Biblioteca" })).toBeVisible();
  await expect(page.locator('[data-antivirus="off"]')).toHaveText(/Sem antivírus/);
  // a primeira tentativa de envio ao storage falha (rede); a app tem de repetir sozinha
  let failed = false;
  await page.route("**/storage/v1/object/upload/sign/**", async (route) => {
    if (!failed) { failed = true; await route.abort("connectionreset"); } else await route.continue();
  });
  await page.getByRole("button", { name: "Carregar ficheiros" }).click();
  const dlg = page.getByRole("dialog");
  await dlg.getByLabel("Ficheiros", { exact: true }).setInputFiles({ name: fileName, mimeType: "image/png", buffer: PNG });
  await dlg.getByLabel("Etiquetas", { exact: true }).fill(`${tag} capa`);
  await dlg.getByRole("button", { name: /^Carregar/ }).click();
  const row = page.locator(`[data-upload="${fileName}"]`);
  await expect(row).toHaveAttribute("data-phase", "pronta", { timeout: 30_000 });
  expect(failed).toBe(true);
  const a = asset();
  expect(a).toBeTruthy();
  const [, path, state, verified] = version(a);
  expect(path).toBe(`${WS_A}/${a}/1/${fileName}`);
  expect(state).toBe("pronta");
  expect(verified).toBe("true"); // boolean concatenado em texto (||) sai como "true"
  expect(sql(`select (metadata->>'size')::int from storage.objects where bucket_id = 'media' and name = '${path}'`)[0]).toBe(String(PNG.length));
  // console: o envio abortado de propósito aparece como erro de rede; tudo o resto tem de estar limpo
  expect(errors.filter((e) => !/ERR_CONNECTION_RESET|net::|Failed to load resource/.test(e))).toEqual([]);
});

as("clientA")("pesquisa por etiqueta e pré-visualização com link assinado curto", async ({ page, errors }) => {
  const a = asset();
  await page.goto(`/c/${WS_A}/biblioteca`);
  await page.getByLabel("Pesquisar por título ou etiqueta").fill(tag);
  await expect(page.locator(`[data-asset="${a}"]`)).toBeVisible();
  await page.getByLabel("Pesquisar por título ou etiqueta").fill(`${tag}-nada`);
  await expect(page.locator(`[data-asset="${a}"]`)).toHaveCount(0);
  await page.getByLabel("Pesquisar por título ou etiqueta").fill(tag);
  await page.locator(`[data-asset="${a}"] button`).first().click();
  const img = page.locator('[data-preview="image"] img');
  await expect(img).toBeVisible();
  expect(await img.getAttribute("src")).toContain("/storage/v1/object/sign/media/");
  expect(Number(sql(`select count(*) from audit_events where action = 'media.accessed' and entity_id = '${a}'`)[0])).toBeGreaterThan(0);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("storage: sem autorização da RPC ninguém assina nem escreve, e B não chega a A", async () => {
  const a = asset();
  const [vid, path] = version(a);
  const hA = await token(users.clientA);
  const hB = await token(users.clientB);
  // A tem media.read mas não passou por media_access: o storage recusa assinar
  const signA = await fetch(`${API_URL}/storage/v1/object/sign/media/${path}`, { method: "POST", headers: hA, body: JSON.stringify({ expiresIn: 60 }) });
  expect(signA.ok).toBe(false);
  const signB = await fetch(`${API_URL}/storage/v1/object/sign/media/${path}`, { method: "POST", headers: hB, body: JSON.stringify({ expiresIn: 60 }) });
  expect(signB.ok).toBe(false);
  // caminho escolhido pelo browser: recusado
  const up = await fetch(`${API_URL}/storage/v1/object/media/${WS_A}/${a}/9/forjado.png`, {
    method: "POST", headers: { ...hA, "Content-Type": "image/png" }, body: PNG,
  });
  expect(up.ok).toBe(false);
  // RPCs: B não lê nem pede acesso a A, nem trocando o cliente
  expect((await (await rpc(hB, "media_asset", { p_ws: WS_A, p_id: a })).json()).code).toBe("42501");
  expect((await (await rpc(hB, "media_access", { p_ws: WS_B, p_version: vid, p_purpose: "download" })).json()).code).toBe("P0002");
  expect((await (await rpc(hB, "media_library", { p_ws: WS_B })).json()).total).toBe(0);
});

as("clientB")("cliente B não vê a biblioteca de A nem pela rota", async ({ page, errors }) => {
  const [vid] = version(asset());
  await page.goto(`/c/${WS_A}/biblioteca`);
  await expect(page.getByRole("heading", { name: "Biblioteca" })).toHaveCount(0);
  const r = await page.request.get(`/api/media/versions/${vid}/url?ws=${WS_A}&purpose=download`);
  expect(r.status()).toBe(403);
  const r2 = await page.request.get(`/api/media/versions/${vid}/url?ws=${WS_B}&purpose=download`);
  expect(r2.status()).toBe(404);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("staff")("staff cria um link de partilha; abre sem sessão; revogar corta", async ({ page, errors, browser }) => {
  const a = asset();
  await page.goto(`/c/${WS_A}/biblioteca`);
  await page.getByLabel("Pesquisar por título ou etiqueta").fill(tag);
  await page.locator(`[data-asset="${a}"] button`).first().click();
  const sheet = page.getByRole("dialog");
  await sheet.getByLabel("Validade", { exact: true }).selectOption("1");
  await sheet.getByRole("button", { name: "Criar link" }).click();
  const link = await sheet.getByLabel("Link de partilha", { exact: true }).inputValue();
  expect(link).toMatch(/\/api\/media\/share\/[0-9a-f]{48}$/);
  const anon = await browser.newContext();
  const r = await anon.request.get(link, { maxRedirects: 0 });
  expect(r.status()).toBe(302);
  const signed = r.headers()["location"];
  expect(signed).toContain("/storage/v1/object/sign/media/");
  expect((await anon.request.get(signed)).status()).toBe(200);
  await sheet.locator("[data-share]").first().getByRole("button", { name: "Revogar" }).click();
  await expect(sheet.locator("[data-share]").first()).toContainText("revogado");
  expect((await anon.request.get(link, { maxRedirects: 0 })).status()).toBe(404);
  await anon.close();
  expect(errors).toEqual([]);
});

as("clientA")("lixo, recuperar e apagar definitivamente com APAGAR", async ({ page, errors }) => {
  const a = asset();
  const [, path] = version(a);
  await page.goto(`/c/${WS_A}/biblioteca`);
  await page.getByLabel("Pesquisar por título ou etiqueta").fill(tag);
  await page.locator(`[data-asset="${a}"] button`).first().click();
  await page.getByRole("dialog").getByRole("button", { name: "Mandar para o lixo" }).click();
  await page.getByRole("dialog", { name: "Mandar para o lixo" }).getByRole("button", { name: "Mandar para o lixo" }).click();
  await expect.poll(() => sql(`select lifecycle from media_assets where id = '${a}'`)[0]).toBe("no_lixo");
  await page.keyboard.press("Escape");
  await page.getByRole("tab", { name: /Lixo/ }).click();
  await page.locator(`[data-asset="${a}"] button`).first().click();
  await page.getByRole("dialog").getByRole("button", { name: "Recuperar" }).click();
  await expect.poll(() => sql(`select lifecycle from media_assets where id = '${a}'`)[0]).toBe("ativo");
  sql(`update media_assets set lifecycle = 'no_lixo', trashed_at = now(), purge_after = now() + interval '30 days' where id = '${a}'`);
  await page.reload();
  await page.getByRole("tab", { name: /Lixo/ }).click();
  await page.locator(`[data-asset="${a}"] button`).first().click();
  await page.getByRole("dialog").getByRole("button", { name: "Apagar definitivamente" }).click();
  const confirm = page.getByRole("dialog", { name: "Apagar definitivamente" });
  await expect(confirm.getByRole("button", { name: "Apagar definitivamente" })).toBeDisabled();
  await confirm.getByLabel("Confirmação").fill("APAGAR");
  await confirm.getByRole("button", { name: "Apagar definitivamente" }).click();
  await expect.poll(() => sql(`select lifecycle from media_assets where id = '${a}'`)[0]).toBe("eliminado");
  expect(sql(`select count(*) from storage.objects where bucket_id = 'media' and name = '${path}'`)[0]).toBe("0");
  expect(errors).toEqual([]);
});

as("clientA")("upload abandonado aparece nos órfãos e limpa-se", async ({ page, errors }) => {
  const h = await token(users.clientA);
  const r = await (await rpc(h, "media_upload_begin", { p_ws: WS_A, p_asset_id: null, p_fields: { title: `${tag} abandonado` },
    p_file: { name: `${tag}-x.png`, size: 10, mime: "image/png", sha256: "0".repeat(64) } })).json();
  await rpc(h, "media_upload_abandon", { p_ws: WS_A, p_version: r.version_id, p_reason: "E2E" });
  await page.goto(`/c/${WS_A}/biblioteca`);
  await page.getByRole("tab", { name: /Órfãos/ }).click();
  const row = page.locator(`[data-orphan="${r.version_id}"]`);
  await expect(row).toBeVisible();
  await row.getByRole("checkbox").check();
  await page.getByRole("button", { name: /^Limpar/ }).click();
  const confirm = page.getByRole("dialog", { name: "Limpar órfãos" });
  await confirm.getByLabel("Confirmação").fill("APAGAR");
  await confirm.getByRole("button", { name: "Apagar definitivamente" }).click();
  await expect.poll(() => sql(`select state from media_versions where id = '${r.version_id}'`)[0]).toBe("apagada");
  expect(errors).toEqual([]);
});
