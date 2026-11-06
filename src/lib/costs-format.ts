/*
 * Custos de IA (FR-10-01, ADR-0062): formatação, tendência e CSV sem dependências, para testar em node.
 * Os valores vêm do servidor em EUR; em AED só com a taxa da agência (BIZ-05) e sempre com a taxa e a data à vista.
 */

export type Money = "EUR" | "AED";
export type Fx = { quote: string; rate: number; as_of: string; source: string | null } | null;

/** Converte um valor em EUR para a moeda escolhida. null quando não há custo conhecido ou não há taxa para AED. */
export function convert(eur: number | null | undefined, cur: Money, fx: Fx): number | null {
  if (eur === null || eur === undefined) return null;
  if (cur === "EUR") return eur;
  return fx && fx.quote === "AED" && fx.rate > 0 ? Math.round(eur * fx.rate * 10000) / 10000 : null;
}

export function money(eur: number | null | undefined, cur: Money, fx: Fx, digits = 2): string {
  const v = convert(eur, cur, fx);
  if (eur === null || eur === undefined) return "sem custo conhecido";
  if (v === null) return "sem taxa EUR/AED";
  return new Intl.NumberFormat("pt-PT", { style: "currency", currency: cur, minimumFractionDigits: digits, maximumFractionDigits: digits }).format(v);
}

/** Tokens em formato curto PT-PT: 950, 1,2 mil, 3,4 M. */
export function tokens(n: number | null | undefined): string {
  if (n === null || n === undefined) return "-";
  const dec = (v: number) => String(Math.round(v * 10) / 10).replace(".", ",");
  if (n >= 1_000_000) return `${dec(n / 1_000_000)} M`;
  if (n >= 1_000) return `${dec(n / 1_000)} mil`;
  return String(n);
}

export function duration(s: number | null | undefined): string {
  if (s === null || s === undefined) return "-";
  if (s < 60) return `${s} s`;
  if (s < 3600) return `${Math.round(s / 60)} min`;
  const h = Math.floor(s / 3600); const m = Math.round((s % 3600) / 60);
  return m ? `${h} h ${m} min` : `${h} h`;
}

export type Trend = { kind: "none" | "new" | "up" | "down" | "flat"; pct: number | null; text: string };
/**
 * Tendência face ao período anterior. Sem atividade no anterior não há percentagem (nunca "+100%" inventado);
 * variação abaixo de 1% conta como estável.
 */
export function trend(cur: number, prev: number, prevCount: number): Trend {
  if (prevCount === 0) return cur > 0 ? { kind: "new", pct: null, text: "sem atividade no período anterior" } : { kind: "none", pct: null, text: "sem atividade nos dois períodos" };
  if (prev === 0) return cur === 0 ? { kind: "flat", pct: 0, text: "igual ao período anterior" } : { kind: "new", pct: null, text: "período anterior sem custo conhecido" };
  const pct = Math.round(((cur - prev) / prev) * 1000) / 10;
  if (Math.abs(pct) < 1) return { kind: "flat", pct, text: "estável face ao período anterior" };
  const p = `${String(Math.abs(pct)).replace(".", ",")}%`;
  return pct > 0 ? { kind: "up", pct, text: `+${p} face ao período anterior` } : { kind: "down", pct, text: `-${p} face ao período anterior` };
}

export type PeriodSel = { days: 7 | 30 | 90 } | { from: string; to: string };
/** Argumentos da RPC para o período escolhido. */
export function periodArgs(p: PeriodSel): { p_days: number | null; p_from: string | null; p_to: string | null } {
  return "days" in p ? { p_days: p.days, p_from: null, p_to: null } : { p_days: null, p_from: p.from, p_to: p.to };
}
/** Valida o período personalizado no browser (o servidor volta a validar). null = válido. */
export function customError(from: string, to: string): string | null {
  const re = /^\d{4}-\d{2}-\d{2}$/;
  if (!re.test(from) || !re.test(to)) return "Escolhe a data de início e a data de fim.";
  const a = Date.parse(`${from}T00:00:00Z`); const b = Date.parse(`${to}T00:00:00Z`);
  if (Number.isNaN(a) || Number.isNaN(b)) return "Data inválida.";
  if (a > b) return "A data de início tem de ser anterior ou igual à data de fim.";
  if ((b - a) / 86_400_000 + 1 > 366) return "O período pode ter no máximo 366 dias.";
  return null;
}

export type CostRow = { key: string; name: string; calls: number; calls_unknown: number; cost: number; prev_cost: number; prev_calls: number; tokens_in: number; tokens_out: number };
export type WsRow = { id: string; name: string; currency: string; cost: number; prev_cost: number; jobs: number; prev_jobs: number; jobs_unknown: number; tokens_in: number; tokens_out: number; calls_cost: number };
export type RunRow = {
  id: string; workspace_id: string; workspace_name: string; kind: string; status: string; cost_eur: number | null; cost_known: boolean;
  tokens_in: number | null; tokens_out: number | null; attempts: number; started_at: string | null; finished_at: string; duration_s: number | null; calls_cost: number | null;
};
export type CostTable = "workspaces" | "agents" | "models" | "runs";

export const KIND_LABEL: Record<string, string> = { daily_pipeline: "Guiões do dia", scouts: "Pesquisa", analysis: "Análise" };
export const STATUS_LABEL: Record<string, string> = { succeeded: "Concluída", failed: "Falhou", dead: "Desistiu", cancelled: "Cancelada", queued: "Na fila", running: "A correr" };

const fxCols = (fx: Fx, cur: Money) => cur === "AED" && fx ? ["custo_aed", "taxa_eur_aed", "data_taxa"] : [];
const fxVals = (eur: number | null, fx: Fx, cur: Money) => (cur === "AED" && fx ? [convert(eur, "AED", fx), fx.rate, fx.as_of] : []);

/** Cabeçalho e linhas do CSV da tabela visível. O EUR sai sempre (é o valor de origem); o AED só com a taxa ao lado. */
export function csvFor(table: CostTable, d: { workspaces: WsRow[]; agents: CostRow[]; models: CostRow[]; runs: RunRow[] }, cur: Money, fx: Fx): { header: string[]; rows: unknown[][] } {
  if (table === "workspaces") {
    return {
      header: ["cliente", "custo_eur", ...fxCols(fx, cur), "custo_anterior_eur", "execucoes", "execucoes_sem_custo", "tokens_entrada", "tokens_saida", "soma_chamadas_eur", "estimado"],
      rows: d.workspaces.map((w) => [w.name, w.cost, ...fxVals(w.cost, fx, cur), w.prev_cost, w.jobs, w.jobs_unknown, w.tokens_in, w.tokens_out, w.calls_cost, "sim"]),
    };
  }
  if (table === "agents" || table === "models") {
    const rows = table === "agents" ? d.agents : d.models;
    return {
      header: [table === "agents" ? "agente" : "modelo", "chave", "custo_eur", ...fxCols(fx, cur), "custo_anterior_eur", "chamadas", "chamadas_sem_custo", "tokens_entrada", "tokens_saida", "estimado"],
      rows: rows.map((r) => [r.name, r.key, r.cost, ...fxVals(r.cost, fx, cur), r.prev_cost, r.calls, r.calls_unknown, r.tokens_in, r.tokens_out, "sim"]),
    };
  }
  return {
    header: ["execucao", "cliente", "tipo", "estado", "custo_eur", ...fxCols(fx, cur), "tokens_entrada", "tokens_saida", "tentativas", "inicio", "fim", "duracao_s", "soma_chamadas_eur", "estimado"],
    rows: d.runs.map((r) => [r.id, r.workspace_name, KIND_LABEL[r.kind] ?? r.kind, STATUS_LABEL[r.status] ?? r.status, r.cost_eur, ...fxVals(r.cost_eur, fx, cur),
      r.tokens_in, r.tokens_out, r.attempts, r.started_at, r.finished_at, r.duration_s, r.calls_cost, r.cost_known ? "sim" : "sem custo conhecido"]),
  };
}
