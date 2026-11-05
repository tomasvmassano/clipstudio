import { test, type Page } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql } from "./env";
import { expect, settle } from "./helpers";

// W10-08 · FR-14-03 (sessões e dispositivos) e R-11/QA-03/FL-07 (sessão terminada e membro removido perdem o acesso já),
// com sessões reais do Supabase Auth local e JWTs ainda dentro do prazo.
const stamp = Date.now();
const IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

// A migração PENDING_w10_sessoes só é aplicada pelo supabase CLI depois de ganhar o nome com data; até lá isto não corre.
const ready = () => sql("select count(*) from pg_proc where proname = 'my_sessions'")[0] === "1";

async function newUser(email: string) {
  const key = process.env.E2E_SERVICE_KEY!;
  const r = await fetch(`${API_URL}/auth/v1/admin/users`, {
    method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
  });
  expect(r.ok).toBe(true);
  sql(`insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role)
       select '${WS_A}', id, 'client_staff', 'contributor' from auth.users where email = '${email}'`);
}

/** Uma sessão noutro "dispositivo": entrada por palavra-passe direto no Auth, com o user agent de um iPhone. */
async function otherDevice(email: string) {
  const r = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json", "User-Agent": IPHONE },
    body: JSON.stringify({ email, password: PASSWORD }),
  });
  expect(r.ok).toBe(true);
  return (await r.json()).access_token as string;
}
const teamCall = (jwt: string) => fetch(`${API_URL}/rest/v1/rpc/workspace_team`, {
  method: "POST", headers: { apikey: ANON_KEY, Authorization: `Bearer ${jwt}`, "Content-Type": "application/json" }, body: JSON.stringify({ p_ws: WS_A }),
});

async function login(page: Page, email: string) {
  await page.goto("/login");
  await page.locator("#email").fill(email);
  await page.locator("button[type=submit]").click();
  await page.locator("#password").fill(PASSWORD);
  await page.locator("button[type=submit]").click();
  await page.waitForURL((u) => u.pathname.startsWith(`/c/${WS_A}`));
}

test("sessões: vê os dispositivos, termina as outras e o JWT terminado deixa de servir já", async ({ page }) => {
  test.skip(!ready(), "migração PENDING_w10_sessoes ainda sem data (o supabase CLI não a aplica)");
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  const email = `sessoes-${stamp}@e2e.test`;
  await newUser(email);
  const phone = await otherDevice(email);
  expect((await teamCall(phone)).ok).toBe(true);

  await login(page, email);
  await page.goto(`/c/${WS_A}/perfil`);
  await settle(page);
  const rows = page.getByTestId("session-row");
  await expect(rows).toHaveCount(2);
  await expect(rows.first().getByText("Esta sessão", { exact: true })).toBeVisible();
  await expect(page.getByText("Safari em iOS")).toBeVisible();

  await page.getByRole("button", { name: "Terminar todas as outras" }).click();
  await page.getByRole("button", { name: "Sim, terminar" }).click();
  await expect(page.getByText("Terminada 1 sessão noutro dispositivo.")).toBeVisible();
  await expect(rows).toHaveCount(1);
  await expect(page.getByText("Sessões terminadas nos outros dispositivos")).toBeVisible();

  // o JWT do iPhone ainda não expirou, mas o servidor já o recusa (R-11)
  expect((await teamCall(phone)).ok).toBe(false);
  // esta sessão continua a funcionar
  await page.reload(); await settle(page);
  await expect(rows).toHaveCount(1);

  // terminar esta sessão: sai só daqui
  const phone2 = await otherDevice(email);
  await page.reload(); await settle(page);
  await expect(rows).toHaveCount(2);
  await page.getByRole("button", { name: "Terminar esta sessão" }).click();
  await page.getByRole("button", { name: "Sim, sair daqui" }).click();
  await page.waitForURL(/\/login/);
  expect((await teamCall(phone2)).ok).toBe(true);
  expect(sql(`select count(*) from auth.sessions where user_id = (select id from auth.users where email = '${email}')`)[0]).toBe("1");
  expect(errors).toEqual([]);
});

test("membro removido: sessões terminadas e o mesmo JWT recebe 42501 no pedido seguinte", async ({ page }) => {
  test.skip(!ready(), "migração PENDING_w10_sessoes ainda sem data (o supabase CLI não a aplica)");
  const email = `removido-${stamp}@e2e.test`;
  await newUser(email);
  const jwt = await otherDevice(email);
  await login(page, email);
  expect((await teamCall(jwt)).ok).toBe(true);
  sql(`update workspace_access set status = 'removed' where workspace_id = '${WS_A}' and user_id = (select id from auth.users where email = '${email}')`);
  const r = await teamCall(jwt);
  expect(r.ok).toBe(false);
  expect((await r.json()).code).toBe("42501");
  expect(sql(`select count(*) from auth.sessions where user_id = (select id from auth.users where email = '${email}')`)[0]).toBe("0");
  await page.goto(`/c/${WS_A}/guioes`);
  await expect(page.getByText(/Precisas de entrar|Esta sessão foi terminada/).or(page.locator("#email"))).toBeVisible();
});
