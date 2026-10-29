import { test } from "@playwright/test";
import { WS_A, WS_B, sql, users } from "./env";
import { as, expect } from "./helpers";

// W7 (ADR-0035): pesquisa global com controlo de acesso e Ctrl/Cmd+K (FR-16-01, FR-16-02, FR-16-05, QA-12), ações rápidas
// (FR-01-05) e operações em lote nos guiões (FR-17-07). O termo exclusivo de B vem do global-setup ("Corpo secreto do cliente B").
test.describe.configure({ mode: "serial" });

const FLAGS = ["busca.global", "guioes.bulk"];
const tag = `e2e${Date.now() % 1_000_000}`;
const B_TERM = "secreto do cliente";
const uid = (email: string) => sql(`select id from auth.users where email = '${email}'`)[0];
const future = sql(`select ((now() at time zone 'Asia/Dubai')::date + 40)::text`)[0];

function setFlags(stage: "all" | null) {
  for (const k of FLAGS) {
    sql(`delete from feature_flags where key = '${k}' and workspace_id in ('${WS_A}', '${WS_B}')`);
    if (stage) sql(`insert into feature_flags (key, organization_id, workspace_id, stage)
                    select '${k}', id, w, '${stage}' from organizations, unnest(array['${WS_A}', '${WS_B}']) w where slug = 'clipstudio'`);
  }
}
const palette = (page: import("@playwright/test").Page) => page.getByRole("dialog");
async function openPalette(page: import("@playwright/test").Page) {
  await page.getByRole("button", { name: /^Pesquisar/ }).waitFor();
  await page.keyboard.press("ControlOrMeta+k");
  await expect(palette(page).getByRole("combobox", { name: "Pesquisar" })).toBeVisible();
}

test.afterAll(() => setFlags(null));

as("clientA")("com a flag desligada não há paleta nem atalho", async ({ page, errors }) => {
  setFlags(null);
  await page.goto(`/c/${WS_A}/guioes`);
  await expect(page.getByRole("heading", { name: "Guiões" })).toBeVisible();
  await expect(page.getByRole("button", { name: /^Pesquisar/ })).toHaveCount(0);
  await page.keyboard.press("ControlOrMeta+k");
  await expect(page.getByRole("combobox", { name: "Pesquisar" })).toHaveCount(0);
  await expect(page.getByRole("button", { name: "Selecionar", exact: true })).toHaveCount(0);
  expect(errors).toEqual([]);
});

as("clientA")("QA-12: A pesquisa um termo exclusivo de B e não vê nada", async ({ page, errors }) => {
  setFlags("all");
  await page.goto(`/c/${WS_A}`);
  await openPalette(page);
  await palette(page).getByRole("combobox", { name: "Pesquisar" }).fill(B_TERM);
  await expect(palette(page).getByText(`Nada encontrado para «${B_TERM}».`)).toBeVisible();
  await expect(palette(page).getByRole("option")).toHaveCount(0);
  expect(errors).toEqual([]);
});

as("clientB")("B encontra o seu guião e Enter abre-o no cliente certo", async ({ page, errors }) => {
  await page.goto(`/c/${WS_B}`);
  await openPalette(page);
  await palette(page).getByRole("combobox", { name: "Pesquisar" }).fill(B_TERM);
  await expect(palette(page).getByRole("option").first()).toBeVisible();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(new RegExp(`/c/${WS_B}/guioes\\?date=\\d{4}-\\d{2}-\\d{2}&open=${WS_B}-segredo`));
  expect(errors).toEqual([]);
});

as("staff")("staff só com A não encontra B; o dono encontra", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}`);
  await openPalette(page);
  await palette(page).getByRole("combobox", { name: "Pesquisar" }).fill(B_TERM);
  await expect(palette(page).getByText(`Nada encontrado para «${B_TERM}».`)).toBeVisible();
  expect(errors).toEqual([]);
});

as("owner")("dono da agência pesquisa no espaço da agência em todos os clientes", async ({ page, errors }) => {
  await page.goto("/");
  await openPalette(page);
  await palette(page).getByRole("combobox", { name: "Pesquisar" }).fill(B_TERM);
  const opt = palette(page).getByRole("option").first();
  await expect(opt).toContainText("Cliente B (E2E)");
  expect(errors).toEqual([]);
});

as("clientA")("ação rápida: nova tarefa pela paleta, gravada e aberta", async ({ page, errors }) => {
  const title = `Tarefa ${tag} rápida`;
  await page.goto(`/c/${WS_A}`);
  await openPalette(page);
  await palette(page).getByRole("combobox", { name: "Pesquisar" }).fill(title);
  await palette(page).getByRole("option", { name: /Nova tarefa/ }).click();
  await expect(palette(page).getByLabel("Título da tarefa")).toHaveValue(title);
  await palette(page).getByRole("button", { name: "Criar" }).click();
  await expect(page).toHaveURL(new RegExp(`/c/${WS_A}/tarefas\\?task=[0-9a-f-]{36}`));
  expect(sql(`select count(*) from tasks where workspace_id = '${WS_A}' and title = '${title}'`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

as("clientA")("lote: acrescentar etiqueta a 2 guiões com pré-visualização, confirmação e auditoria", async ({ page, errors }) => {
  sql(`insert into guioes (id, client_id, date, n, tema, hooks, corpo, editorial_status) values
       ('${WS_A}-${tag}-1', '${WS_A}', '${future}', 91, 'Lote ${tag} um', '[]', 'Corpo.', 'in_review'),
       ('${WS_A}-${tag}-2', '${WS_A}', '${future}', 92, 'Lote ${tag} dois', '[]', 'Corpo.', 'in_review') on conflict do nothing`);
  await page.goto(`/c/${WS_A}/guioes?date=${future}`);
  await page.getByRole("button", { name: "Selecionar", exact: true }).click();
  await page.getByRole("checkbox", { name: `Selecionar guião 91: Lote ${tag} um` }).check();
  await page.getByRole("checkbox", { name: `Selecionar guião 92: Lote ${tag} dois` }).check();
  const bar = page.getByRole("region", { name: "Ações em lote" });
  await expect(bar.getByText("2 selecionados")).toBeVisible();
  await bar.getByRole("button", { name: "Etiquetas" }).click();
  const dlg = page.getByRole("dialog");
  await dlg.getByLabel(/Etiquetas \(separadas/).fill(tag);
  await dlg.getByRole("button", { name: "Ver impacto" }).click();
  await expect(dlg.getByText("Pré-visualização: ainda nada foi gravado.")).toBeVisible();
  expect(sql(`select count(*) from guioes where id like '${WS_A}-${tag}-%' and '${tag}' = any (tags)`)[0]).toBe("0");
  await dlg.getByRole("button", { name: "Confirmar em 2" }).click();
  await expect(dlg.getByText(/2.*mudaram/)).toBeVisible();
  await dlg.getByRole("button", { name: "Fechar" }).last().click();
  expect(sql(`select count(*) from guioes where id like '${WS_A}-${tag}-%' and '${tag}' = any (tags)`)[0]).toBe("2");
  expect(sql(`select count(*) from audit_events where action = 'script.bulk' and actor_user_id = '${uid(users.clientA)}' and after->'args'->'tags' ? '${tag}'`)[0]).toBe("1");
  expect(errors).toEqual([]);
});
