import { execFileSync } from "node:child_process";

/** Ligação à stack Supabase local. Só aceita endereços locais: os E2E nunca tocam em produção. */
export const API_URL = process.env.E2E_SUPABASE_URL ?? "http://127.0.0.1:54321";
export const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_KEY ?? "";
export const DB_URL = process.env.E2E_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
for (const u of [API_URL, DB_URL]) {
  if (!/^(https?|postgresql):\/\/[^@]*@?(127\.0\.0\.1|localhost)[:/]/.test(u)) throw new Error(`E2E só correm contra uma stack local; recusado: ${u}`);
}

/** Corre SQL na base local (psql) e devolve a primeira coluna das linhas. */
export function sql(query: string): string[] {
  const out = execFileSync("psql", [DB_URL, "-XAtq", "-v", "ON_ERROR_STOP=1", "-c", query], { encoding: "utf8" });
  return out.split("\n").filter(Boolean);
}

/** Contas de teste: só existem na stack local, criadas pelo global-setup. */
export const PASSWORD = "e2e-palavra-passe-local";
export const users = {
  owner: "dono@e2e.test", // dono da agência: vê todos os clientes
  staff: "staff@e2e.test", // staff da agência com acesso só ao numeiro
  clientA: "cliente-a@e2e.test", // equipa do cliente numeiro
  clientB: "cliente-b@e2e.test", // equipa do cliente e2e-b
} as const;
export type Role = keyof typeof users;
export const WS_A = "numeiro";
export const WS_B = "e2e-b";
export const TEAM_CODE = "e2e-codigo-local-numeiro";
export const state = (r: Role) => `e2e/.auth/${r}.json`;
