import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/* Catálogo, configuração versionada e execuções dos agentes (PRD M06; ADR-0010). */

export type Validation = { ok: boolean; errors: string[]; warnings: string[] };
export type Format = { share: number; min: number; max: number; maquina?: string; palavras: [number, number]; descricao?: string };
export type AgentConfig = {
  language: string; voice: string; lexicon?: string[]; guardrails: string[]; formats: Record<string, Format>;
  pipeline: { scripts_per_day: number; hooks_per_slot: number; max_revisions?: number; critic_threshold: number; hook_threshold?: number; hook_min?: number; concurrency: number; idea_share?: number };
  models?: Record<string, string>; schedule?: { enabled: boolean; time: string }; budget_eur_day?: number | null;
  enabled_agents?: string[]; news_beats?: string[]; reading_list?: string[];
};
export type ConfigVersion = {
  id: string; version_no: number; status: "draft" | "active" | "retired"; notes: string | null; validation: Validation;
  created_label: string | null; created_at: string; activated_at: string | null; config?: AgentConfig;
};
export type AgentRow = { key: string; name: string; stage: string; description: string; model: string; tools: string[]; reads: string[]; writes: string[]; enabled: boolean };
export type Job = {
  id: string; kind: "daily_pipeline" | "scouts" | "analysis"; status: "queued" | "running" | "succeeded" | "failed" | "cancelled" | "dead";
  idempotency_key: string; attempts: number; max_attempts: number; scheduled_for: string; next_attempt_at: string; started_at: string | null;
  finished_at: string | null; heartbeat_at: string | null; progress: Record<string, unknown> | null; last_error: string | null;
  cancel_requested: boolean; run_id: string | null; requested_label: string | null; config_version: number;
  cost_eur: number | null; tokens_in: number | null; tokens_out: number | null; result: Record<string, unknown> | null;
};
export type Overview = {
  agents: AgentRow[];
  active: { id: string; version_no: number; activated_at: string; activated_label: string | null; schedule: { enabled: boolean; time: string } | null; budget_eur_day: number | null; scripts_per_day: number } | null;
  versions: ConfigVersion[] | null; jobs: Job[]; spend_today: number | null;
  worker: { id: string; last_seen: string; version: string | null } | null;
  can: { run: boolean; configure: boolean; costs: boolean };
};

export const STAGE_LABEL: Record<string, string> = { research: "Pesquisa", strategy: "Estratégia", creative: "Criação", quality: "Qualidade", learning: "Aprendizagem" };
export const JOB_KIND: Record<Job["kind"], string> = { daily_pipeline: "Guiões do dia", scouts: "Pesquisa (scouts)", analysis: "Análise de referências" };
export const JOB_STATUS: Record<Job["status"], string> = {
  queued: "Em fila", running: "A correr", succeeded: "Concluída", failed: "Falhou", cancelled: "Cancelada", dead: "Falhou de vez",
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}
export const fetchOverview = (access: Access) => rpc<Overview>("agents_overview", { p_ws: access.ws, p_token: access.token });
export const fetchConfig = (access: Access, version?: string) =>
  rpc<{ version: (ConfigVersion & { config: AgentConfig }) | null; models: { key: string; label: string }[]; agents: { key: string; name: string; default_model: string }[] }>(
    "agent_config_get", { p_ws: access.ws, p_version: version ?? null });
export const saveConfig = (access: Access, config: AgentConfig, notes: string) => rpc<ConfigVersion>("agent_config_save", { p_ws: access.ws, p_config: config, p_notes: notes || null });
export const activateConfig = (id: string) => rpc<ConfigVersion>("agent_config_activate", { p_version: id });
export const enqueueJob = (access: Access, kind: Job["kind"]) => rpc<Job>("agent_job_enqueue", { p_ws: access.ws, p_kind: kind, p_key: null, p_token: access.token });
export const cancelJob = (access: Access, id: string) => rpc<Job>("agent_job_cancel", { p_job: id, p_token: access.token });
export const retryJob = (access: Access, id: string) => rpc<Job>("agent_job_retry", { p_job: id, p_token: access.token });
