import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Publication } from "@/lib/pub";

/*
 * Portal do cliente (SCALE-08, ADR-0041). Leituras por portal_home / portal_block; as ações usam as RPCs de sempre
 * (content_transition, content_transition_reasoned, pub_approve, talent_request_create), que voltam a decidir tudo.
 * Cada bloco pode vir indisponível com o motivo; nenhum traz dinheiro, outros clientes, flags ou permissões.
 */

export type Off = { available: false; code: "sem_capacidade" | "desligado" | "erro"; reason: string; sqlstate?: string };
export type Block<T> = Off | ({ available: true } & T);

export type PortalScript = {
  id: string; n: number; date: string; tema: string | null; formato: string | null; hooks: string[]; corpo: string | null; cta: string | null;
  lock_version: number; version_id: string | null; version_no: number | null; waiting_since: string; waiting_local: string; over_48h: boolean;
};
export type ScriptsBlock = { can_reject: boolean; reasons_by_category: boolean; total: number; over_48h: number; items: PortalScript[] };
export type PublicationsBlock = {
  can_approve: boolean; individual: boolean; policy: { required: string; forbid_self: boolean }; total: number; items: Publication[];
  publish_available: false; publish_unavailable_reason: string;
};
export type DeliveriesBlock = {
  month: string; today: string; timezone: string;
  contract: { videos_per_month: number | null; scripts_per_month: number | null; platforms: string[]; deadline_days: number } | null;
  contract_reason: string | null;
  videos: { contracted: number | null; published: number; on_time: number; late: number; overdue: number; due_today: number;
    expected_to_date: number | null; pct: number | null; pace: number | null; target: number; deadline_days: number };
  scripts: { contracted: number | null; approved: number; planned: number; waiting_approval: number };
  assumption: string;
};
export type ReportAccount = {
  id: string; platform: string; handle: string; label: string | null; active: boolean; n_30d: number; last_read_at: string | null;
  idx72_median_30d: number | null; idx72_n_30d: number; median_ratio: number | null; median_drop: boolean | null;
};
export type ReportsBlock = {
  source: string; first_reading_at: string | null; totals: { publications: number; linked: number }; accounts: ReportAccount[];
  week: { from: string; to: string; n: number; top: { reel_id: string; platform: string; handle: string; hook_text: string | null; idx72: number; published_at: string }[] };
  min_sample: number;
};
export type PortalRequest = {
  id: number; titulo: string; texto: string | null; status: string; status_reason: string | null; created_at: string; created_local: string; mine: boolean;
  scripts: { id: string; n: number; date: string; editorial_status: string }[];
};
export type RequestsBlock = { can_create: boolean; window_days: number; total: number; open: number; items: PortalRequest[] };

export type BlockKey = "scripts" | "publications" | "deliveries" | "reports" | "requests";
export type PortalHome = {
  client: { id: string; name: string; timezone: string };
  viewer: { side: "cliente" | "agencia" | "codigo"; as_client: boolean; individual: boolean };
  generated_at: string;
  blocks: { scripts: Block<ScriptsBlock>; publications: Block<PublicationsBlock>; deliveries: Block<DeliveriesBlock>; reports: Block<ReportsBlock>; requests: Block<RequestsBlock> };
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

export const fetchPortal = (a: Access) => rpc<PortalHome>("portal_home", { p_ws: a.ws, p_token: a.token });
export const fetchPortalBlock = <K extends BlockKey>(a: Access, block: K) =>
  rpc<PortalHome["blocks"][K]>("portal_block", { p_ws: a.ws, p_block: block, p_token: a.token });
export const createRequest = (a: Access, text: string) => rpc<{ id: number }>("talent_request_create", { p_ws: a.ws, p_text: text, p_token: a.token });
