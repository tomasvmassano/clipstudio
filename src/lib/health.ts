import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";
import type { HealthSource } from "@/lib/health-format";

/*
 * Saúde do sistema (W10-01, PRD FR-17-15, ADR-0058). Uma RPC só de leitura: o servidor verifica ops.health e filtra os
 * clientes (dono: todos; admin: os atribuídos; agentes com agents.read e media com media.read nesse cliente).
 */

type RpcError = Error & { code?: string };
export const isForbidden = (e: unknown) => (e as RpcError | null)?.code === "42501";

export type HealthWorker = { id: string; kinds: string[]; version: string | null; last_seen: string; recent: boolean };
export type HealthQueue = {
  source: HealthSource; queued: number; ready: number; oldest_ready_at: string | null; running: number; stalled: number;
  uncovered: number; uncovered_kinds: string[];
};
export type HealthRunning = {
  source: HealthSource; id: string; kind: string; workspace_id: string; workspace: string; attempts: number; max_attempts: number;
  started_at: string | null; heartbeat_at: string | null; locked_until: string | null; locked_by: string | null; run_id: string | null;
  asset_id: string | null; cancel_requested: boolean; lease_expired: boolean;
};
export type HealthFailure = {
  source: HealthSource; id: string; kind: string; status: "failed" | "dead"; workspace_id: string; workspace: string;
  attempts: number; max_attempts: number; finished_at: string; run_id: string | null; asset_id: string | null; last_error: string | null;
};
export type FailureCounts = { failed_24h: number; dead_24h: number; failed_7d: number; dead_7d: number };
export type WsCounts = {
  queued: number; ready: number; oldest_ready_at: string | null; running: number; stalled: number; failed_24h: number; failed_7d: number; dead_7d: number;
};
export type HealthWorkspace = { id: string; name: string; timezone: string; agent: WsCounts | null; media: WsCounts | null };
export type HealthAlert = {
  id: number; kind: "worker_down" | "job_dead"; source: HealthSource; workspace_id: string; workspace: string; job_id: string | null;
  detail: Record<string, unknown>; notified: number; created_at: string;
};
export type Health = {
  generated_at: string;
  thresholds: { worker_stale_minutes: number; window_days: number };
  tick: { scheduled: boolean; last_run_at: string | null; last_result: { worker_down?: number; job_dead?: number } | null };
  workers: HealthWorker[]; queues: HealthQueue[]; running: HealthRunning[];
  failure_counts: Record<HealthSource, FailureCounts>; failures: HealthFailure[];
  workspaces: HealthWorkspace[]; alerts: HealthAlert[];
};

export async function fetchHealth(): Promise<Health> {
  const { data, error } = await supabase().rpc("ops_health");
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as RpcError;
    e.code = error.code;
    throw e;
  }
  return data as Health;
}
