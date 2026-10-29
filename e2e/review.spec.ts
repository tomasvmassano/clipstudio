import { WS_A, WS_B, sql, users } from "./env";
import { as, expect, settle } from "./helpers";

// FR-05-01, FR-05-02, FR-02-02: caixa de revisão com filtros e comentários presos a uma frase.
const GID = "numeiro-2026-10-28-12";

as("clientA")("caixa de revisão filtra por responsável e prioridade", async ({ page, errors }) => {
  // tarefas são append-only: cria só uma vez por base
  sql(`insert into tasks (workspace_id, title, kind, priority, assignee_id, due_at, content_id, created_kind)
       select '${WS_A}', 'E2E rever guião 12', 'review', 'urgent', id, now() - interval '1 day', '${GID}', 'system' from auth.users
        where email = '${users.clientA}' and not exists (select 1 from tasks where title = 'E2E rever guião 12')`);
  await page.goto(`/c/${WS_A}/revisao`);
  await expect(page.getByRole("heading", { name: "Revisão" })).toBeVisible();
  await expect(page.getByText(/\d+ guiões/)).toBeVisible();
  await page.locator('select[aria-label="Responsável"]').selectOption("me");
  await expect(page.getByText("1 guião", { exact: true })).toBeVisible();
  await expect(page.locator("[data-slot=badge]", { hasText: "Urgente" })).toBeVisible();
  await expect(page.getByText(/atrasado/)).toBeVisible();
  await page.locator('select[aria-label="Prioridade"]').selectOption("low");
  await expect(page.getByText("Nada à espera de revisão com estes filtros.")).toBeVisible();
  await page.getByRole("button", { name: "Limpar filtros" }).click();
  await expect(page.getByText(/\d+ guiões/)).toBeVisible();
  expect(errors).toEqual([]);
});

as("clientA")("comentar uma frase do corpo, responder e resolver", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/revisao`);
  await page.getByPlaceholder("Pesquisar tema, hooks ou corpo").fill("guião 12.");
  await expect(page.getByText("1 guião", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: /^Comentários/ }).click();
  const sheet = page.getByRole("dialog");
  await expect(sheet.getByRole("heading", { name: /Revisão do guião/ })).toBeVisible();
  await sheet.getByRole("button", { name: "Corpo de teste do guião 12." }).click();
  await expect(sheet.getByText("A comentar:")).toContainText("Corpo");
  const body = `Troca por uma cena concreta ${Date.now()}`;
  await sheet.getByLabel("Comentário").fill(body);
  await sheet.getByRole("button", { name: "Comentar", exact: true }).click();
  const c = sheet.locator("div.rounded-md", { hasText: body });
  await expect(c).toBeVisible();
  await expect(c.getByText("“Corpo de teste do guião 12.”")).toBeVisible();
  await c.getByRole("button", { name: "Responder" }).click();
  await sheet.getByLabel("Resposta").fill("Concordo.");
  await sheet.getByRole("button", { name: "Responder", exact: true }).last().click();
  await expect(c.getByText("Concordo.")).toBeVisible();
  await c.getByRole("button", { name: "Resolver" }).click();
  await expect(sheet.getByText(body)).toHaveCount(0);   // resolvidos escondidos por omissão
  await sheet.getByRole("button", { name: /Mostrar \d+ resolvido/ }).click();
  await expect(sheet.getByText(body)).toBeVisible();
  await page.keyboard.press("Escape");
  const [n] = sql(`select count(*) from content_comments where content_id = '${GID}' and body = '${body}' and resolved_at is not null`);
  expect(n).toBe("1");
  expect(errors).toEqual([]);
});

as("clientB")("o cliente B não vê a revisão nem os comentários do A", async ({ page }) => {
  await page.goto(`/c/${WS_A}/revisao`);
  await expect(page.getByText("Não tens acesso a este cliente, ou ele não existe.")).toBeVisible();
  await page.goto(`/c/${WS_B}/revisao`);
  await settle(page);
  await expect(page.getByText("Corpo de teste do guião")).toHaveCount(0);
});
