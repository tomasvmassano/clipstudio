import { WS_A } from "./env";
import { as, expect, expectNoCrash, settle } from "./helpers";

// QA-16, R-15: cada rota principal abre por URL direta e refresh, sem página de erro e sem erros na consola.
const CLIENT = ["", "/caixa", "/guioes", "/tarefas", "/calendario", "/teleprompter", "/fontes", "/referencias", "/desempenho",
  "/agentes", "/agentes/configuracao", "/equipa", "/permissoes", "/historico", "/definicoes", "/perfil"];
const AGENCY = ["/", "/clientes", "/caixa", "/equipa-agencia", "/perfil"];

for (const role of ["owner", "clientA"] as const) {
  const t = as(role);
  for (const sub of CLIENT) {
    t(`${role}: /c/${WS_A}${sub} abre sem erros`, async ({ page, errors }) => {
      await page.goto(`/c/${WS_A}${sub}`);
      await settle(page);
      await page.reload();
      await settle(page);
      await expectNoCrash(page);
      await expect(page.getByText("Não tens acesso a este cliente")).toHaveCount(0);
      expect(errors).toEqual([]);
    });
  }
}

const owner = as("owner");
for (const path of AGENCY) {
  owner(`owner: ${path} abre sem erros`, async ({ page, errors }) => {
    await page.goto(path);
    await settle(page);
    await page.reload();
    await settle(page);
    await expectNoCrash(page);
    expect(errors).toEqual([]);
  });
}
