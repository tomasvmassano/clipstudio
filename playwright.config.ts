import { defineConfig, devices } from "@playwright/test";

// E2E contra uma stack Supabase local (supabase start) e a app em modo produção (next start).
// Nunca contra produção: e2e/env.ts recusa um URL do Supabase que não seja local.
const PORT = 3123;
export default defineConfig({
  testDir: "e2e",
  globalSetup: "./e2e/global-setup.ts",
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  reporter: process.env.CI ? [["github"], ["list"], ["html", { open: "never" }]] : [["list"]],
  use: { baseURL: `http://localhost:${PORT}`, trace: "retain-on-failure", screenshot: "only-on-failure", locale: "pt-PT", timezoneId: "Asia/Dubai" },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"], viewport: { width: 1440, height: 900 } } }],
  webServer: { command: `npm run start -- -p ${PORT}`, url: `http://localhost:${PORT}/login`, reuseExistingServer: !process.env.CI, timeout: 120_000 },
});
