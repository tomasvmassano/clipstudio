import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { IntegHealth } from "@/lib/integ-format";

/*
 * Centro de integrações (W8, ADR-0039; PRD FR-15-03, FR-17-16). Só estados reais lidos da base; nunca tokens nem
 * segredos. Tudo por RPCs: o servidor verifica capacidade (integrations.read/manage, integrations.agency.read) e a flag
 * integrations.center em cada chamada.
 */

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
export const isForbidden = (e: unknown) => (e as RpcError | null)?.code === "42501";
export const isFlagOff = (e: unknown) => (e as RpcError | null)?.code === "55000";

export type IntegAction = { key: "ligar" | "renovar" | "revogar" | "testar" | string; label: string; available: boolean; capability?: string; reason?: string };
export type SocialAccount = {
  account_id: string; handle: string; label: string | null; connection_state: string; stored_state: string; credential_stored: boolean;
  scopes: string[]; token_expires_at: string | null; connected_at: string | null; connected_label: string | null; updated_at: string | null;
  can_revoke: boolean; revoke_blocked: string | null;
};
export type PlatformLimit = {
  platform: string; max_posts: number; window_kind: "rolling_24h" | "calendar_day"; window_tz: string; scope: "conta" | "projeto";
  public_requires_audit: boolean; note: string | null; verified_on: string; updated_at?: string; updated_label?: string | null;
};
export type ScrapingAccount = { account_id: string; handle: string; platform: string; label: string | null; reels: number; last_sync_at: string | null; state: string };
export type WorkerJob = {
  kind: string; status: string; created_at: string; started_at: string | null; finished_at: string | null; heartbeat_at: string | null; last_error: string | null;
};
export type IntegCheck = { id: number; integration_key: string; outcome: string; state: string; detail: Record<string, unknown>; actor_label: string | null; checked_at: string; reused?: boolean };
export type IntegItem = {
  key: string; label: string; scope: "cliente" | "agencia"; kind: "social" | "scraping" | "worker" | "limits" | "external"; platform: string | null;
  provides: string; state_source: string; requirement_ids: string[]; planned_permissions: string[]; blocked_reason: string | null; missing: string | null;
  state: string; health: IntegHealth; last_sync_at: string | null; actions: IntegAction[]; last_check: IntegCheck | null;
  detail: {
    accounts?: SocialAccount[] | ScrapingAccount[]; limits?: PlatformLimit | PlatformLimit[] | null;
    last_sync_at?: string | null; references_last_sync_at?: string | null; stale_after_hours?: number; account_count?: number;
    worker_seen_at?: string | null; queued?: number; oldest_queued_at?: string | null; failed_7d?: number; queue_late?: boolean;
    last_job?: WorkerJob | null; stale_after_minutes?: number;
  };
};
export type IntegOverview = { workspace_id: string; timezone: string; can_manage: boolean; generated_at: string; items: IntegItem[] };

export type AgencyItem = Pick<IntegItem, "key" | "label" | "scope" | "kind" | "provides" | "state_source" | "requirement_ids" | "blocked_reason" | "missing" | "actions" | "state">;
export type AgencyClient = {
  id: string; name: string; timezone: string; enabled: boolean;
  social: { total: number; por_ligar: number; ligada: number; expirada: number; revogada: number };
  scraping: { state: string; last_sync_at: string | null };
  worker: { state: string; last_job: WorkerJob | null; queued: number };
};
export type AgencyWorker = { id: string; kinds: string[]; version: string | null; last_seen: string; active: boolean };
export type IntegAgency = { generated_at: string; workers: AgencyWorker[]; items: AgencyItem[]; limits: PlatformLimit[]; clients: AgencyClient[] };

export const fetchIntegrations = (a: Access) => rpc<IntegOverview>("integrations_overview", { p_ws: a.ws, p_token: a.token });
export const fetchAgencyIntegrations = () => rpc<IntegAgency>("integrations_agency", {});
export const testIntegration = (a: Access, key: string) => rpc<IntegCheck>("integrations_test", { p_ws: a.ws, p_key: key, p_token: a.token });
export const revokeSocialAccount = (a: Access, accountId: string, reason: string) =>
  rpc<{ account_id: string; connection_state: string; changed: boolean; secret_purged?: boolean; secret_purge_pending?: boolean }>(
    "integrations_social_revoke", { p_ws: a.ws, p_account_id: accountId, p_reason: reason, p_token: a.token });
