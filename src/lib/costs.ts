import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";
import { periodArgs, type CostRow, type CostTable, type Fx, type PeriodSel, type RunRow, type WsRow } from "@/lib/costs-format";

/*
 * Consumo de IA por agente, modelo, execução e cliente (FR-10-01, ADR-0060). Só por RPC: o servidor verifica a sessão,
 * costs.read (cliente) ou costs.read_agency + costs.read por cliente (agência), a flag, e costs.export para exportar.
 */

export type AiUsage = {
  scope: "workspace" | "agency"; currency: "EUR"; timezone: string; from: string; to: string; days: number; prev_from: string; prev_to: string;
  can_export: boolean;
  basis: {
    kind: "estimated"; confirmed_available: boolean; note: string;
    prices: { model: string; label: string; eur_per_mtok_in: number | null; eur_per_mtok_out: number | null; fx_usd_per_eur: number | null; source: string | null; updated_at: string | null }[];
    tools: { key: string; label: string; eur_per_use: number; source: string; updated_at: string }[];
  };
  fx: Fx;
  totals: {
    cost: number; prev_cost: number; jobs: number; prev_jobs: number; jobs_unknown: number; jobs_failed: number;
    tokens_in: number; tokens_out: number; calls_cost: number; calls: number; calls_unknown: number;
  };
  workspaces: WsRow[]; agents: CostRow[]; models: CostRow[]; runs: RunRow[];
};

type RpcError = Error & { code?: string };
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as RpcError;
    e.code = error.code;
    throw e;
  }
  return data as T;
}

/** ws nulo = vista da agência. */
export const fetchAiUsage = (ws: string | null, token: string | null, p: PeriodSel) =>
  rpc<AiUsage>("costs_ai_usage", { p_ws: ws, ...periodArgs(p), p_token: token });
export const exportAiUsage = (table: CostTable, ws: string | null, token: string | null, p: PeriodSel) =>
  rpc<AiUsage>("costs_ai_usage_export", { p_table: table, p_ws: ws, ...periodArgs(p), p_token: token });
