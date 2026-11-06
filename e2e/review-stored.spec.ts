import { test, type Page } from "@playwright/test";
import { existsSync, readFileSync } from "node:fs";
import { ANON_KEY, API_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { NO_ACCESS, as, expect, expectNoCrash } from "./helpers";

// W5-12 (EDL-02, EDL-03; ADR-0052): os vídeos exportados (versão no R2) entram na Revisão → Vídeos com o player da app,
// as notas do QC técnico, comentários num momento do vídeo e "Aprovar e seguinte"; "Exportar todos" no pacote.
// Os vídeos exportados e o pacote são semeados por SQL (o worker e o R2 não existem na stack local).
test.describe.configure({ mode: "serial" });

const tag = `e2ers${Date.now() % 1_000_000}`;
const GID = `${WS_A}-2026-10-28-07`;
const REVIEWER = `revisor-${tag}@e2e.test`;
const FLAGS = ["media.library", "edit.studio", "media.r2"];
// clip WebM de 8 s (VP8, sem som) para o player; o R2 não existe localmente, por isso o link assinado é simulado no browser
const CLIP = `data:video/webm;base64,${readFileSync("e2e/fixtures/review-clip.webm").toString("base64")}`;
// o único erro de consola esperado: o 503 da versão leve sem R2 configurado (o ecrã mostra o erro e "Tentar de novo")
const R2_OFF = /O armazenamento de vídeo \(R2\) ainda não está configurado no servidor\./;
const only503 = (errors: string[]) => errors.filter((e) => !/Failed to load resource: the server responded with a status of 503/.test(e));

let ids: { h1: string; h2: string; v1: string; v2: string; job: string };
let savedFlags: string[] = [];

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

async function login(page: Page, email: string) {
  await page.goto("/login");
  await page.locator("#email").fill(email);
  await page.locator("button[type=submit]").click();
  await page.locator("#password").fill(PASSWORD);
  await page.locator("button[type=submit]").click();
  await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30_000 });
}

/** Uma versão de vídeo guardada no R2 e já verificada (como o worker a deixa): nasce pendente e passa a pronta. */
function storedVideo(asset: string, name: string, info: object | null, proxy: boolean) {
  const path = `${WS_A}/e2e/${tag}/${name}`;
  // em dois passos: numa CTE o update não veria a linha acabada de inserir
  const id = sql(`insert into media_versions (workspace_id, asset_id, version_no, source, state, storage_provider, storage_bucket, storage_path,
                                              original_name, size_bytes, mime, sha256)
                  values ('${WS_A}', '${asset}', 1, 'upload', 'pendente', 'r2', 'r2', '${path}', '${name}', 1234, 'video/mp4', repeat('a', 64))
                  returning id`)[0];
  sql(`update media_versions set state = 'pronta', checksum_verified = true, checksum_verified_at = now(), completed_at = now(),
         proxy_path = ${proxy ? `'${path}_proxy.mp4'` : "null"}, proxy_state = ${proxy ? "'pronta'" : "null"},
         media_info = ${info ? `'${JSON.stringify(info)}'::jsonb` : "null"}
       where id = '${id}'`);
  return id;
}
function asset(title: string, tags: string[], content: string | null) {
  return sql(`insert into media_assets (workspace_id, kind, title, tags, content_id, created_label)
              values ('${WS_A}', 'video', '${title}', array[${tags.map((t) => `'${t}'`).join(",")}], ${content ? `'${content}'` : "null"}, 'E2E')
              returning id`)[0];
}

test.beforeAll(async () => {
  savedFlags = sql(`select key || '=' || stage from feature_flags where workspace_id = '${WS_A}' and key in (${FLAGS.map((f) => `'${f}'`).join(",")})`);
  sql(`delete from feature_flags where workspace_id in ('${WS_A}', '${WS_B}') and key in (${FLAGS.map((f) => `'${f}'`).join(",")});
       insert into feature_flags (key, organization_id, workspace_id, stage)
         select k, o.id, w, 'all' from organizations o, unnest(array[${FLAGS.map((f) => `'${f}'`).join(",")}]) k, unnest(array['${WS_A}', '${WS_B}']) w
          where o.slug = 'clipstudio'`);

  // revisor do cliente A (decide na revisão, não exporta)
  const key = process.env.E2E_SERVICE_KEY!;
  const r = await fetch(`${API_URL}/auth/v1/admin/users`, {
    method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email: REVIEWER, password: PASSWORD, email_confirm: true }),
  });
  expect(r.ok).toBe(true);
  sql(`insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role)
       select '${WS_A}', id, 'client_staff', 'reviewer' from auth.users where email = '${REVIEWER}'`);

  // dois vídeos exportados do guião 7 (hook 1 com 1 aviso do QC, hook 2 sem avisos)
  const qc = (ok: boolean) => ({ duration: 8, qc: { version: "qc-e2e", passed: ok, checks: [
    { key: "resolution", ok: true, label: "Formato" },
    { key: "loudness", ok, value: ok ? -14.2 : -20.1, expected: "-14 ± 2 LUFS", label: "Loudness" },
  ] } });
  const h1 = asset(`${tag} hook 1`, ["pacote", "hook_1", "s15"], GID);
  const h2 = asset(`${tag} hook 2`, ["pacote", "hook_2", "s15"], GID);
  const v1 = storedVideo(h1, "h1.mp4", qc(false), true);
  const v2 = storedVideo(h2, "h2.mp4", qc(true), true);
  sql(`update media_assets set current_version_id = '${v1}' where id = '${h1}'; update media_assets set current_version_id = '${v2}' where id = '${h2}'`);

  // gravações da sessão (câmaras do pacote) e o pacote acabado, com um documento de edição por vídeo
  const front = `${tag}_FX30.mp4`, side = `${tag}_FX3.mp4`;
  for (const n of [front, side]) {
    const a = asset(n, ["gravacao"], null);
    sql(`update media_assets set current_version_id = '${storedVideo(a, n, { duration: 600 }, true)}' where id = '${a}'`);
  }
  const doc = { schema: 1, style: "S15", segments: [{ id: "s01", in: 10, out: 14, section: "hook" }], captions: { words: [] }, cameras: [],
    hook: { text: "Tema" }, source: { cams: { front, side }, audio: "side" } };
  for (const a of [h1, h2]) {
    const d = sql(`insert into edit_documents (workspace_id, asset_id, content_id) values ('${WS_A}', '${a}', '${GID}') returning id`)[0];
    const v = sql(`insert into edit_versions (workspace_id, document_id, version_no, doc, source, created_label)
                   values ('${WS_A}', '${d}', 1, '${JSON.stringify(doc)}'::jsonb, 'ai', 'E2E') returning id`)[0];
    sql(`update edit_documents set current_version_id = '${v}' where id = '${d}'`);
  }
  const job = sql(`insert into media_jobs (workspace_id, kind, idempotency_key, status, input, created_label, finished_at)
                   values ('${WS_A}', 'package', 'package:${tag}', 'done',
                           jsonb_build_object('front', jsonb_build_object('name', '${front}'), 'side', jsonb_build_object('name', '${side}'),
                                              'guioes', jsonb_build_array(jsonb_build_object('id', '${GID}', 'n', 7, 'tema', 'Tema de teste 7'))),
                           'E2E', now()) returning id`)[0];
  sql(`insert into media_job_outputs (job_id, workspace_id, guiao_id, hook, asset_id) values
         ('${job}', '${WS_A}', '${GID}', 1, '${h1}'), ('${job}', '${WS_A}', '${GID}', 2, '${h2}')`);
  ids = { h1, h2, v1, v2, job };

  // W10-15: a migração das anotações ainda tem nome PENDING_ (ganha o carimbo ao ser aplicada), e o `supabase start` só aplica
  // ficheiros com carimbo. Enquanto for assim, aplica-a aqui (é aditiva e idempotente) e pede ao PostgREST para recarregar.
  const pending = "supabase/migrations/PENDING_w10_anotacoes.sql";
  if (existsSync(pending) && sql(`select count(*) from information_schema.columns where table_schema = 'public'
                                    and table_name = 'media_comments' and column_name = 'annotation'`)[0] === "0") {
    sql(readFileSync(pending, "utf8"));
    sql(`notify pgrst, 'reload schema'`);
  }
});

test.afterAll(() => {
  sql(`delete from feature_flags where workspace_id in ('${WS_A}', '${WS_B}') and key in (${FLAGS.map((f) => `'${f}'`).join(",")})`);
  for (const kv of savedFlags) {
    const [k, stage] = kv.split("=");
    sql(`insert into feature_flags (key, organization_id, workspace_id, stage) select '${k}', id, '${WS_A}', '${stage}' from organizations where slug = 'clipstudio'`);
  }
});

async function openReview(page: Page) {
  await page.goto(`/c/${WS_A}/revisao?ver=videos`);
  await expect(page.getByRole("heading", { name: "Revisão de vídeos" })).toBeVisible();
  await page.getByLabel("Pesquisar vídeos").fill(tag);
  await expect(page.getByText("2 vídeos em 1 guião")).toBeVisible();
}

as("clientA")("vídeo exportado aparece na revisão com as notas do QC; sem R2 o player mostra o erro e Tentar de novo", async ({ page, errors }) => {
  await openReview(page);
  const card1 = page.getByRole("button", { name: /Hook 1 · S15/ });
  const card2 = page.getByRole("button", { name: /Hook 2 · S15/ });
  await expect(card1).toContainText("QC: 1 aviso");
  await expect(card1).toContainText("Por rever");
  await expect(card2).toContainText("QC sem avisos");
  await card1.click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: "Hook 1 · S15 · v1" })).toBeVisible();
  expect(new URL(page.url()).searchParams.get("asset")).toBe(ids.h1);
  // QC técnico: avisos primeiro, com o valor esperado; os checks bons num resumo
  const qc = sheet.getByRole("region", { name: "QC técnico" });
  await expect(qc).toContainText("QC técnico · 1 aviso");
  await expect(qc).toContainText("Loudness: -20.1 · esperado -14 ± 2 LUFS");
  await expect(qc).toContainText("OK: Formato.");
  // localmente não há R2: o link assinado da versão leve falha com uma mensagem clara e uma ação, nunca um spinner infinito
  await expect(sheet.getByText(R2_OFF)).toBeVisible();
  await expect(sheet.locator("video")).toHaveCount(0);
  const again = page.waitForResponse((r) => r.url().includes(`/api/media/versions/${ids.v1}/proxy`));
  await sheet.getByRole("button", { name: "Tentar de novo" }).click();
  expect((await again).status()).toBe(503);
  await expect(sheet.getByText(R2_OFF)).toBeVisible();
  await expect(sheet.locator('[data-slot="skeleton"]')).toHaveCount(0);
  await expectNoCrash(page);
  expect(only503(errors)).toEqual([]);
});

as("clientA")("player da app: Agora preenche o momento, o tempo do comentário salta no vídeo, Aprovar e seguinte", async ({ page, errors }) => {
  // o servidor autoriza (media_proxy_access) e devolve o link assinado; aqui só o link é simulado, com um clip real
  let asked = 0;
  await page.route("**/api/media/versions/*/proxy?*", async (route) => {
    const res = await route.fetch();
    asked++;
    expect(res.status()).toBe(503); // passou a autorização: 503 é só o R2 em falta (sem permissão seria 403)
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ url: CLIP, mime: "video/webm", expires_at: new Date(Date.now() + 3600e3).toISOString() }) });
  });
  await openReview(page);
  await page.getByRole("button", { name: /Hook 1 · S15/ }).click();
  const sheet = page.getByRole("dialog");
  const video = sheet.locator("video");
  await expect(video).toHaveAttribute("src", /^data:video\/webm/);
  await expect(video).toHaveAttribute("aria-label", `${tag} hook 1`);
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState)).toBeGreaterThanOrEqual(1);
  expect(asked).toBe(1);
  await expect(sheet.getByText("0:08")).toBeVisible(); // duração do media_info

  // a pessoa leva o vídeo até 0:03 e carrega em "Agora"
  await video.evaluate((v: HTMLVideoElement) => { v.currentTime = 3.4; });
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.currentTime)).toBeGreaterThan(3);
  await sheet.getByRole("button", { name: "Agora" }).click();
  await expect(sheet.getByLabel("Momento")).toHaveValue("0:03");
  expect(await video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
  const body = `Aos 3 s o som baixa ${tag}`;
  await sheet.getByRole("textbox", { name: "Comentário", exact: true }).fill(body);
  await sheet.getByRole("button", { name: "Comentar", exact: true }).click();
  const comment = sheet.getByRole("region", { name: "Comentários" }).locator("div.rounded-md", { hasText: body });
  await expect(comment).toBeVisible();
  await expect(sheet.getByLabel("Momento")).toHaveValue("");
  expect(sql(`select t_ms from media_comments where version_id = '${ids.v1}' and body = '${body}'`)).toEqual(["3000"]);

  // clicar no tempo do comentário leva o vídeo a esse momento
  await video.evaluate((v: HTMLVideoElement) => { v.pause(); v.currentTime = 0; });
  await comment.getByRole("button", { name: "0:03" }).click();
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.currentTime)).toBeGreaterThanOrEqual(3);

  // aprovar abre o próximo vídeo por rever da fila (hook 2)
  await sheet.getByRole("button", { name: "Aprovar e seguinte" }).click();
  await expect(sheet.getByRole("heading", { name: "Hook 2 · S15 · v1" })).toBeVisible();
  await expect.poll(() => new URL(page.url()).searchParams.get("asset")).toBe(ids.h2);
  expect(sql(`select status from media_reviews where version_id = '${ids.v1}'`)).toEqual(["approved"]);
  expect(sql(`select count(*) from media_decisions where version_id = '${ids.v1}' and to_status = 'approved'`)).toEqual(["1"]);
  await expect(sheet.getByRole("region", { name: "QC técnico" })).toContainText("QC técnico · sem avisos");
  // o último da fila: já não há "seguinte"
  await expect(sheet.getByRole("button", { name: "Aprovar", exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByText("1 vídeo em 1 guião")).toBeVisible(); // o aprovado sai do filtro "por rever"
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientA")("desenhar no fotograma: caneta, retângulo, desfazer; o desenho vai com o comentário e aparece no momento e na linha do tempo", async ({ page, errors }) => {
  // o PostgREST pode demorar a ver p_annotation depois de recarregar o esquema (só na primeira corrida)
  const h = await token(users.clientA);
  await expect.poll(async () => (await (await rpc(h, "media_review_comment", { p_ws: WS_A, p_version: ids.v2, p_body: "x", p_t_ms: 1,
    p_annotation: { v: 1, shapes: [] } })).json()).code, { timeout: 20_000 }).toBe("22023");
  await page.route("**/api/media/versions/*/proxy?*", (route) =>
    route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ url: CLIP, mime: "video/webm", expires_at: new Date(Date.now() + 3600e3).toISOString() }) }));
  await page.goto(`/c/${WS_A}/revisao?ver=videos&asset=${ids.h2}`);
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: "Hook 2 · S15 · v1" })).toBeVisible();
  const video = sheet.locator("video");
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.readyState)).toBeGreaterThanOrEqual(1);
  await video.evaluate((v: HTMLVideoElement) => { v.currentTime = 2.2; });
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.currentTime)).toBeGreaterThan(2);

  // pausar e desenhar: retângulo, traço de caneta e uma seta que se desfaz
  await sheet.getByRole("button", { name: "Desenhar no fotograma" }).click();
  expect(await video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
  const surface = sheet.getByTestId("draw-surface");
  await expect(surface).toBeFocused();
  const tools = sheet.getByRole("toolbar", { name: "Ferramentas de desenho" });
  const b = (await surface.boundingBox())!;
  const drag = async (pts: [number, number][]) => {
    await page.mouse.move(b.x + b.width * pts[0][0], b.y + b.height * pts[0][1]);
    await page.mouse.down();
    for (const p of pts.slice(1)) await page.mouse.move(b.x + b.width * p[0], b.y + b.height * p[1], { steps: 4 });
    await page.mouse.up();
  };
  await tools.getByRole("button", { name: "Retângulo" }).click();
  await drag([[0.2, 0.2], [0.6, 0.5]]);
  await tools.getByRole("button", { name: "Caneta" }).click();
  await tools.getByRole("radio", { name: "Amarelo" }).click();
  await drag([[0.1, 0.8], [0.3, 0.7], [0.5, 0.85], [0.7, 0.75]]);
  await tools.getByRole("button", { name: "Seta" }).click();
  await drag([[0.8, 0.1], [0.5, 0.3]]);
  await expect(tools).toContainText("3 formas");
  await tools.getByRole("button", { name: "Desfazer" }).click();
  await expect(tools).toContainText("2 formas");
  await surface.focus();
  await page.keyboard.press("Control+z");
  await expect(tools).toContainText("1 forma");
  await drag([[0.1, 0.8], [0.3, 0.7], [0.5, 0.85]]); // a seta continua escolhida
  await tools.getByRole("button", { name: "Concluir" }).click();
  await expect(sheet.getByTestId("draw-surface")).toHaveCount(0);
  await expect(sheet.getByLabel("Momento")).toHaveValue("0:02");
  await expect(sheet.getByLabel("Momento")).toBeDisabled();
  await expect(sheet.getByText(/Desenho com 2 formas aos 0:02/)).toBeVisible();

  const body = `Este canto tem de sair ${tag}`;
  await sheet.getByRole("textbox", { name: "Comentário", exact: true }).fill(body);
  await sheet.getByRole("button", { name: "Comentar", exact: true }).click();
  const comment = sheet.getByTestId("review-comment").filter({ hasText: body });
  await expect(comment).toContainText("com desenho");
  await expect(sheet.getByLabel("Momento")).toHaveValue("");
  const saved = JSON.parse(sql(`select json_build_object('t', t_ms, 'a', annotation) from media_comments where version_id = '${ids.v2}' and body = '${body}'`)[0]);
  expect(saved.t).toBe(2200);
  expect(saved.a.shapes.map((x: { type: string }) => x.type)).toEqual(["rect", "arrow"]);
  expect(saved.a.shapes[0].points.flat().every((n: number) => n >= 0 && n <= 1)).toBe(true);
  expect(saved.a.shapes[0].points[0][0]).toBeCloseTo(0.2, 1);
  expect(saved.a.shapes[0].color).toBe("#ff3b30");

  // no momento (±0,5 s) o desenho aparece por cima do fotograma; longe dele desaparece
  const layer = sheet.getByTestId("annotation-layer");
  await expect(layer).toHaveAttribute("aria-label", new RegExp(`aos 0:02: ${body}`));
  await expect(layer.locator("rect, path, g")).toHaveCount(2);
  const vb = (await video.boundingBox())!; const lb = (await layer.boundingBox())!;
  expect(lb.x).toBeGreaterThanOrEqual(vb.x - 1); expect(lb.x + lb.width).toBeLessThanOrEqual(vb.x + vb.width + 1);
  await video.evaluate((v: HTMLVideoElement) => { v.currentTime = 6; });
  await expect(layer).toHaveCount(0);

  // marca na linha do tempo (QA-07): leva ao momento, pausa e mostra o desenho
  const marker = sheet.getByRole("button", { name: new RegExp(`Ir a 0:02: ${body}.*com desenho`) });
  await marker.click();
  await expect.poll(() => video.evaluate((v: HTMLVideoElement) => v.currentTime)).toBeCloseTo(2.2, 1);
  expect(await video.evaluate((v: HTMLVideoElement) => v.paused)).toBe(true);
  await expect(layer).toBeVisible();
  await expect(comment).toHaveClass(/border-amber-400/);

  // noutro tamanho de ecrã (iPad ao alto) o desenho escala com o vídeo
  await page.setViewportSize({ width: 820, height: 1180 });
  await expect.poll(async () => { const v = (await video.boundingBox())!; const l = (await layer.boundingBox())!; return l.x >= v.x - 1 && l.x + l.width <= v.x + v.width + 1; }).toBe(true);

  // a API valida: tipo proibido e desenho num vídeo da Drive são recusados (22023), sem gravar nada
  const bad = await rpc(h, "media_review_comment", { p_ws: WS_A, p_version: ids.v2, p_body: `mau ${tag}`, p_t_ms: 1000,
    p_annotation: { v: 1, shapes: [{ type: "text", color: "#ffffff", width: 0.004, points: [[0.1, 0.1], [0.2, 0.2]] }] } });
  expect(bad.status).toBe(400);
  expect((await bad.json()).code).toBe("22023");
  // a assinatura antiga (sem p_annotation) continua a funcionar
  const old = await rpc(h, "media_review_comment", { p_ws: WS_A, p_version: ids.v2, p_body: `sem desenho ${tag}`, p_t_ms: 4000, p_parent: null, p_token: null });
  expect(old.status).toBe(200);
  expect(sql(`select count(*) from media_comments where version_id = '${ids.v2}' and body = 'mau ${tag}'`)).toEqual(["0"]);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("revisor vê o pacote mas não exporta (UI e API 42501)", async ({ browser }) => {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
  page.on("console", (m) => { if (m.type() === "error") errors.push(`console: ${m.text()}`); });
  await login(page, REVIEWER);
  await page.goto(`/c/${WS_A}/edicao-automatica`);
  await expect(page.getByRole("heading", { name: "Edição automática" })).toBeVisible();
  const row = page.locator("div.rounded-md", { hasText: `${tag}_FX30.mp4 + ${tag}_FX3.mp4` });
  await expect(row).toContainText("Exportar precisa da permissão de exportar vídeos.");
  await expect(row.getByRole("button", { name: /Exportar todos/ })).toHaveCount(0);
  await expect(row.getByRole("link", { name: "Rever os exportados" })).toHaveAttribute("href", `/c/${WS_A}/revisao?ver=videos`);
  await expectNoCrash(page);
  expect(errors).toEqual([]);
  await ctx.close();

  const r = await rpc(await token(REVIEWER), "edit_package_export", { p_ws: WS_A, p_job: ids.job });
  expect(r.status).toBe(403);
  expect((await r.json()).code).toBe("42501");
  expect(sql(`select count(*) from media_jobs where kind = 'export' and asset_id in ('${ids.h1}', '${ids.h2}')`)).toEqual(["0"]);
});

as("clientA")("admin exporta o pacote inteiro: um export por vídeo, e repetir não duplica", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/edicao-automatica`);
  const row = page.locator("div.rounded-md", { hasText: `${tag}_FX30.mp4 + ${tag}_FX3.mp4` });
  await row.getByRole("button", { name: "Exportar todos (2)" }).click();
  await expect(row.getByRole("status")).toContainText("2 vídeos na fila para exportar.");
  await expect(row.getByRole("status")).not.toContainText("Não deu para");
  expect(sql(`select count(*) from media_jobs where kind = 'export' and asset_id in ('${ids.h1}', '${ids.h2}')`)).toEqual(["2"]);
  await row.getByRole("button", { name: "Exportar todos (2)" }).click();
  await expect(row.getByRole("status")).toContainText("2 vídeos na fila para exportar.");
  expect(sql(`select count(*) from media_jobs where kind = 'export' and asset_id in ('${ids.h1}', '${ids.h2}')`)).toEqual(["2"]);
  expect(sql(`select count(*) from audit_events where action = 'edit.package_export' and entity_id = '${ids.job}'`)[0]).not.toBe("0");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("clientB")("outro cliente: a revisão de A é proibida pela rota, pela API e pelo link da versão leve", async ({ page }) => {
  await page.goto(`/c/${WS_A}/revisao?ver=videos&asset=${ids.h1}`);
  await expect(page.getByText(NO_ACCESS)).toBeVisible();
  await expect(page.getByText(tag)).toHaveCount(0);
  const proxy = await page.request.get(`/api/media/versions/${ids.v1}/proxy?ws=${WS_A}`);
  expect(proxy.status()).toBe(403);
  const own = await page.request.get(`/api/media/versions/${ids.v1}/proxy?ws=${WS_B}`);
  expect([403, 404]).toContain(own.status());

  const h = await token(users.clientB);
  for (const [fn, args] of [
    ["media_review_list", { p_ws: WS_A, p_filters: {} }],
    ["media_review_detail", { p_ws: WS_A, p_asset: ids.h1 }],
    ["media_review_comment", { p_ws: WS_A, p_version: ids.v2, p_body: "intruso", p_t_ms: 1000 }],
    ["media_review_comment", { p_ws: WS_A, p_version: ids.v2, p_body: "intruso", p_t_ms: 1000,
      p_annotation: { v: 1, shapes: [{ type: "rect", color: "#ffffff", width: 0.004, points: [[0.1, 0.1], [0.2, 0.2]] }] } }],
    ["media_review_decide", { p_ws: WS_A, p_version: ids.v2, p_status: "approved" }],
    ["edit_package_export", { p_ws: WS_A, p_job: ids.job }],
  ] as const) {
    const r = await rpc(h, fn, args);
    expect(r.status, fn).toBe(403);
    expect((await r.json()).code, fn).toBe("42501");
  }
  // trocar o cliente pelo seu não chega ao vídeo de A
  const swap = await rpc(h, "media_review_detail", { p_ws: WS_B, p_asset: ids.h1 });
  expect((await swap.json()).code).toBe("P0002");
  expect(sql(`select count(*) from media_comments where version_id = '${ids.v2}' and body = 'intruso'`)).toEqual(["0"]);
});
