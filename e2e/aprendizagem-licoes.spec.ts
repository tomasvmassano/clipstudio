import { existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { test } from "@playwright/test";
import { ANON_KEY, API_URL, DB_URL, PASSWORD, WS_A, WS_B, sql, users } from "./env";
import { as, expect, expectNoCrash } from "./helpers";
import { flagsOnForA, restoreFlags } from "./flags";

// W10-19 (LRN-01, LRN-02, LRN-03, LRN-04): motivo de um toque ao aprovar um guião do motor editado (obrigatório acima de
// 30%), lição proposta pelo Editor de lições (gravada aqui pelas funções do worker) e aprovada na página Lições, com
// versão nova. O cliente B não lê nem aprova nada de A; a equipa do cliente não vê a secção da agência.
test.describe.configure({ mode: "serial" });

const PENDING = "supabase/migrations/20261106132216_w10_aprendizagem.sql";
const tag = `e2elrn${Date.now() % 1_000_000}`;
// guiões do motor num dia longe dos outros testes (a base local é partilhada)
const DAY = sql(`select to_char((now() at time zone 'Asia/Dubai')::date + 500 + (${Date.now() % 97}), 'YYYY-MM-DD')`)[0];
const G1 = `${WS_A}-${DAY}-01`;
const G2 = `${WS_A}-${DAY}-02`;
let lessonId = "";

async function token(email: string) {
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email, password: PASSWORD }),
  });
  return { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
}
const rpc = async (h: Record<string, string>, fn: string, args: Record<string, unknown>) =>
  fetch(`${API_URL}/rest/v1/rpc/${fn}`, { method: "POST", headers: h, body: JSON.stringify(args) });

test.beforeAll(async () => {
  // A stack local só aplica migrações com carimbo; a desta PR ainda é PENDING_ (idempotente).
  if (existsSync(PENDING)) execFileSync("psql", [DB_URL, "-XqA", "-v", "ON_ERROR_STOP=1", "-f", PENDING]);
  flagsOnForA(["learn.edits", "learn.lessons"]);
  // inseridos sem RPC: a versão 1 fica como escrita pelo motor
  sql(`insert into guioes (id, client_id, date, n, formato, tema, hooks, corpo, cta, editorial_status) values
    ('${G1}', '${WS_A}', '${DAY}', 1, 'lista', 'Tema ${tag}', '[{"text":"Hook do motor ${tag}","mecanismo":"pergunta"}]',
     'Esta frase do motor tem muitas palavras que vão desaparecer quase todas na edição humana de hoje.', null, 'in_review'),
    ('${G2}', '${WS_A}', '${DAY}', 2, 'lista', 'Tema ${tag}', '[{"text":"Outro hook ${tag}","mecanismo":"numero"}]', 'Corpo que fica igual.', null, 'in_review')
    on conflict (id) do nothing`);
  const h = await token(users.clientA);
  expect((await rpc(h, "content_save", { p_id: G1, p_patch: { corpo: `Texto novo escrito pela equipa ${tag}.` } })).ok).toBe(true);
});

test.afterAll(() => restoreFlags());

as("clientA")("aprovar um guião do motor editado pede o motivo e guarda o par", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/guioes?date=${DAY}`);
  const card = page.locator(`[data-guiao="${G1}"]`);
  await card.getByRole("button", { name: "Aprovar", exact: true }).click();
  const form = card.getByTestId("approve-learn");
  await expect(form).toBeVisible();
  await expect(form.getByText(/Acima de 30% o motivo é obrigatório/)).toBeVisible();
  await expect(form.getByRole("button", { name: "Aprovar", exact: true })).toBeDisabled();
  await form.getByRole("button", { name: "Não soa ao cliente" }).click();
  await expect(form.getByRole("button", { name: "Não soa ao cliente" })).toHaveAttribute("aria-pressed", "true");
  await form.getByRole("button", { name: "Aprovar", exact: true }).click();
  await expect(form).toHaveCount(0);
  await expect.poll(() => sql(`select editorial_status from guioes where id = '${G1}'`)[0]).toBe("approved");
  expect(sql(`select kind || ':' || array_to_string(codes, ',') from lrn_edit_signals where content_id = '${G1}'`)).toEqual(["approved:nao_soa_cliente"]);

  // sem edição: aprova logo e fica como sinal positivo
  await page.locator(`[data-guiao="${G2}"]`).getByRole("button", { name: "Aprovar", exact: true }).click();
  await expect.poll(() => sql(`select kind from lrn_edit_signals where content_id = '${G2}'`)[0]).toBe("approved_unedited");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

test("o Editor de lições propõe com evidência só deste cliente", async () => {
  const h = await token(users.clientA);
  const run = await rpc(h, "lrn_lessons_run", { p_ws: WS_A });
  expect(run.ok).toBe(true);
  const job = (await run.json()).id as string;
  // o worker (aqui simulado pela base) apanha a execução e grava uma lição com os sinais citados
  sql(`update agent_jobs set status = 'running', locked_by = 'e2e-lrn', locked_until = now() + interval '10 minutes',
         params = params || jsonb_build_object('until', now() + interval '1 minute') where id = '${job}'`);
  lessonId = sql(`select (worker_lesson_save('${job}', 'e2e-lrn', 1, jsonb_build_object('category', 'tom', 'text', 'Escreve como o cliente fala ${tag}.',
    'signal_ids', (select jsonb_agg(id) from lrn_edit_signals where content_id in ('${G1}', '${G2}')))))->>'lesson_id'`)[0];
  sql(`update agent_jobs set status = 'succeeded', finished_at = now() where id = '${job}'`);
  expect(lessonId).toMatch(/^[0-9a-f-]{36}$/);

  // cliente B: não lê nem aprova
  const hb = await token(users.clientB);
  expect((await rpc(hb, "lrn_lessons_list", { p_ws: WS_A })).status).toBe(403);
  expect((await rpc(hb, "lrn_lesson_decide", { p_id: lessonId, p_action: "approve" })).status).toBe(403);
  const own = await rpc(hb, "lrn_lessons_list", { p_ws: WS_B });
  if (own.ok) expect(JSON.stringify(await own.json())).not.toContain(tag);
});

as("clientA")("Lições: aprovar com texto editado cria a versão em vigor", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/aprendizagem/licoes`);
  await expect(page.getByRole("heading", { name: "Lições", level: 1 })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Agência" })).toHaveCount(0);   // equipa do cliente não vê a agência
  const card = page.locator(`[data-lesson="${lessonId}"]`);
  await expect(card).toContainText(tag);
  await expect(card).toContainText(/edições? como evidência/);
  await card.getByRole("button", { name: "Editar" }).click();
  await card.getByLabel("Texto da lição").fill(`Frases curtas e faladas ${tag}.`);
  await card.getByRole("button", { name: "Aprovar com este texto" }).click();
  await expect(page.locator(`[data-lesson="${lessonId}"]`)).toHaveCount(0);
  const active = page.locator("section", { has: page.getByRole("heading", { name: /Em vigor/ }) });
  await expect(active).toContainText(`Frases curtas e faladas ${tag}.`);
  expect(sql(`select status || ':' || (text <> proposed_text) from lrn_lessons where id = '${lessonId}'`)[0]).toBe("approved:true");
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});

as("owner")("dono da agência vê a secção da agência na mesma página", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/aprendizagem/licoes`);
  await expect(page.getByRole("heading", { name: /Agência/ })).toBeVisible();
  await expectNoCrash(page);
  expect(errors).toEqual([]);
});
