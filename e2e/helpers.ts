import { test as base, expect, type Page } from "@playwright/test";
import { state, type Role } from "./env";

export const NO_ACCESS = "Não tens acesso a este cliente, ou ele não existe.";

/** Página com sessão de uma conta e recolha de erros de JS e da consola (R-15: zero erros nas rotas principais). */
export function as(role: Role) {
  const t = base.extend<{ errors: string[] }>({
    storageState: state(role),
    errors: async ({ page }, provide) => {
      const errors: string[] = [];
      page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
      page.on("console", (m) => { if (m.type() === "error") errors.push(`console: ${m.text()}`); });
      await provide(errors);
    },
  });
  return t;
}

export const sidebar = (p: Page) => p.locator('[data-sidebar="sidebar"]').first();

/** Espera a página assentar: sem pedidos pendentes durante um instante. */
export async function settle(p: Page) {
  await p.waitForLoadState("networkidle").catch(() => {});
}

/** Nunca a página genérica de erro do browser/Next (R-15). */
export async function expectNoCrash(p: Page) {
  await expect(p.getByText("This page couldn't load")).toHaveCount(0);
  await expect(p.getByText("Application error")).toHaveCount(0);
}

export { expect };
