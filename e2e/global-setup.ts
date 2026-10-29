import { chromium, type FullConfig } from "@playwright/test";
import { API_URL, PASSWORD, TEAM_CODE, WS_A, WS_B, sql, state, users, type Role } from "./env";

/** Prepara a stack local: contas, acessos, um segundo cliente e o código de equipa; depois guarda a sessão de cada conta. */
export default async function globalSetup(config: FullConfig) {
  const key = process.env.E2E_SERVICE_KEY;
  if (!key) throw new Error("Falta E2E_SERVICE_KEY (chave secreta da stack local: npx supabase status -o env).");

  for (const email of Object.values(users)) {
    const r = await fetch(`${API_URL}/auth/v1/admin/users`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password: PASSWORD, email_confirm: true }),
    });
    if (!r.ok && r.status !== 422) throw new Error(`criar ${email}: ${r.status} ${await r.text()}`);
  }
  const id = (e: string) => `(select id from auth.users where email = '${e}')`;
  sql(`
    insert into clients (id, name, handle, organization_id)
      select '${WS_B}', 'Cliente B (E2E)', 'clienteb', id from organizations where slug = 'clipstudio' on conflict (id) do nothing;
    insert into guioes (id, client_id, date, n, hooks, corpo) values
      ('${WS_B}-segredo', '${WS_B}', (now() at time zone 'Asia/Dubai')::date, 1, '[{"text":"Hook secreto de B","mecanismo":""}]', 'Corpo secreto do cliente B')
      on conflict do nothing;
    insert into agency_memberships (organization_id, user_id, agency_role)
      select o.id, u.id, r from organizations o, (values (${id(users.owner)}, 'agency_owner'), (${id(users.staff)}, 'agency_member')) u(id, r)
      where o.slug = 'clipstudio' on conflict do nothing;
    insert into workspace_access (workspace_id, user_id, affiliation_type, workspace_role) values
      ('${WS_A}', ${id(users.staff)}, 'agency_staff', 'manager'),
      ('${WS_A}', ${id(users.clientA)}, 'client_staff', 'workspace_admin'),
      ('${WS_B}', ${id(users.clientB)}, 'client_staff', 'workspace_admin')
      on conflict do nothing;
    update studio_tokens set token = '${TEAM_CODE}' where client_id = '${WS_A}';
  `);

  const base = config.projects[0].use.baseURL!;
  const browser = await chromium.launch();
  for (const role of Object.keys(users) as Role[]) {
    const page = await browser.newPage();
    await page.goto(`${base}/login`);
    await page.locator("#email").fill(users[role]);
    await page.locator("button[type=submit]").click();
    await page.locator("#password").fill(PASSWORD);
    await page.locator("button[type=submit]").click();
    await page.waitForURL((u) => !u.pathname.startsWith("/login"), { timeout: 30_000 });
    await page.context().storageState({ path: state(role) });
    await page.close();
  }
  await browser.close();
}
