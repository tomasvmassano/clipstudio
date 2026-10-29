import { test } from "@playwright/test";
import { ANON_KEY, API_URL, PASSWORD, WS_A, sql, users } from "./env";
import { as, expect } from "./helpers";

// ING-03 (W5-01): o teleprompter regista quando cada bloco foi lido; a sessão mostra os tempos por guião.
as("clientA")("rolar e parar no teleprompter deixa os tempos na sessão", async ({ page, errors }) => {
  await page.goto(`/c/${WS_A}/teleprompter`);
  await page.getByRole("button", { name: /^Começar no guião|^Retomar no guião/ }).first().click();
  await page.getByRole("button", { name: "Rolar" }).click();
  await page.waitForTimeout(2500);
  await page.getByRole("button", { name: "Parar" }).click();
  await page.getByRole("button", { name: "Voltar à fila" }).click();
  const ask = page.getByRole("dialog", { name: "Confirmar gravação" });
  if (await ask.isVisible().catch(() => false)) await ask.getByRole("button", { name: "Ainda não" }).click();
  await page.getByRole("button", { name: "Tempos da sessão" }).click();
  const list = page.getByRole("list", { name: "Tempos por guião" });
  await expect(list).toBeVisible();
  await expect(list.locator("li").first()).toContainText(/a ler/);
  await expect(list.locator("li").first()).toContainText(/Hook 1 \d{2}:\d{2}:\d{2} · \d/);
  // ficou no servidor, com o ref do dispositivo (reenviar não duplica)
  const n = Number(sql(`select count(*) from recording_marks m join recording_sessions s on s.id = m.session_id where s.workspace_id = '${WS_A}' and m.kind = 'play'`)[0]);
  expect(n).toBeGreaterThan(0);
  expect(errors).toEqual([]);
});

test("outro cliente não lê nem escreve os tempos do numeiro (403)", async () => {
  const [sid] = sql(`select id from recording_sessions where workspace_id = '${WS_A}' order by opened_at desc limit 1`);
  expect(sid).toBeTruthy();
  const t = await fetch(`${API_URL}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: { apikey: ANON_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ email: users.clientB, password: PASSWORD }),
  });
  const h = { apikey: ANON_KEY, Authorization: `Bearer ${(await t.json()).access_token}`, "Content-Type": "application/json" };
  const read = await fetch(`${API_URL}/rest/v1/rpc/recording_timeline`, { method: "POST", headers: h, body: JSON.stringify({ p_session: sid }) });
  expect(read.status).toBe(403);
  const write = await fetch(`${API_URL}/rest/v1/rpc/recording_marks_add`, {
    method: "POST", headers: h,
    body: JSON.stringify({ p_session: sid, p_marks: [{ ref: crypto.randomUUID(), kind: "pause", at: new Date().toISOString() }] }),
  });
  expect(write.status).toBe(403);
  const direct = await fetch(`${API_URL}/rest/v1/recording_marks?select=id&limit=1`, { headers: h });
  expect([401, 403]).toContain(direct.status);
});
