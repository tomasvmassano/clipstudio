import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Age, Dimension } from "@/lib/perf-format";

/* Centro de desempenho (PRD §40, R-16, R-18; ADR-0033). Tudo pelas RPCs perf_*: o servidor verifica analytics.read. */

export type PerfParams = {
  ages: Age[]; tolerance: number; min_base: number; min_sample: number; winner_age: Age;
  near_zero: number; drop_ratio: number; cut_below: number;
};
export type FamilyMetric = { key: string; label: string; available: boolean | "conta"; note?: string; reason?: string };
export type Family = { key: string; label: string; metrics: FamilyMetric[] };
export type PerfAccount = {
  id: string; platform: string; handle: string; label: string | null; active: boolean; tier: string | null; creator: string;
  n: number; n_30d: number; last_read_at: string | null; idx72_median_30d: number | null; idx72_n_30d: number;
  comments_pk: number | null; likes_pk: number | null; shares_pk: number | null; shares_available: boolean;
  health: {
    state: string; note: string | null; set_at: string | null; set_label: string | null; recent_n: number; prev_n: number;
    median_ratio: number | null; median_drop: boolean | null; near_zero_30d: number | null; near_zero_prev: number | null; near_zero_doubling: boolean | null;
  };
};
export type PerfCenter = {
  client: { id: string; name: string; timezone: string };
  params: PerfParams; can_manage: boolean; families: Family[]; source: string; first_reading_at: string | null;
  accounts: PerfAccount[];
  coverage: Record<Age, { snapshots: number; indexed: number }>;
  totals: { publications: number; sistema: number; externo: number; gravada: number; inferida: number; linked: number };
};
export type Snapshot = { views: number | null; idx: number | null; base_n: number | null; base_median: number | null };
export type Publication = {
  reel_id: string; lineage_id: number | null; account_id: string; platform: string; handle: string; tier: string | null; creator: string;
  url: string | null; title: string; published_at: string | null; duration_s: number | null;
  views: number | null; likes: number | null; comments: number | null; shares: number | null; last_read_at: string | null;
  origin: "sistema" | "externo"; origin_source: string; lineage_mode: "gravada" | "inferida"; inference_source: string | null; inference_confidence: number | null;
  content_id: string | null; version_no: number | null; hook_index: number | null; hook_text: string | null; hook_mechanism: string | null;
  formato: string | null; maquina: string | null; tema: string | null; edit_style_key: string | null; edit_style_version: number | null;
  persona_phrase: string | null; source_type: string | null; generation: number | null; local_hour: number | null;
  snapshots: Partial<Record<Age, Snapshot>>; idx72: number | null; comments_pk: number | null; likes_pk: number | null; shares_pk: number | null;
};
export type PerfFilters = { account?: string; platform?: string; origin?: "sistema" | "externo"; days?: number; sort?: "recentes" | "indice"; limit?: number; offset?: number };
export type PublicationPage = { total: number; limit: number; offset: number; items: Publication[] };
export type BreakdownGroup = {
  key: string; label: string | null; n: number; n_indexed: number; idx_median: number | null; idx_best: number | null; idx_worst: number | null;
  accounts: number; views_median: number | null; repeat_n: number; repeat_idx_median: number | null;
  items: { reel_id: string; platform: string; handle: string; hook_index: number | null; hook_text: string | null; title: string; url: string | null; idx: number | null; published_at: string | null }[] | null;
};
export type Breakdown = { dimension: Dimension; age: Age; unassigned: number; groups: BreakdownGroup[] };
export type Lever = { dimension: string; key: string; n: number; shown: boolean; idx_median: number | null };
export type WeekPick = Omit<Publication, "snapshots">;
export type Levers = {
  params: PerfParams; only_system: boolean; eligible: number; levers: Lever[];
  week: {
    from: string; to: string; n: number; top: WeekPick[]; bottom: WeekPick[];
    hooks_by_platform: Record<string, { hook_text: string; hook_mechanism: string | null; idx72: number; reel_id: string; handle: string }[]>;
    styles_to_cut: { key: string; n: number; idx_median: number }[];
  };
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const isForbidden = (e: unknown) => (e as { code?: string })?.code === "42501";

export const fetchPerfCenter = (a: Access) => rpc<PerfCenter>("perf_center", { p_ws: a.ws, p_token: a.token });
export const fetchPublications = (a: Access, f: PerfFilters) => rpc<PublicationPage>("perf_publications", { p_ws: a.ws, p_filters: f, p_token: a.token });
export const fetchBreakdown = (a: Access, dimension: Dimension, age: Age, f: PerfFilters) =>
  rpc<Breakdown>("perf_breakdown", { p_ws: a.ws, p_dimension: dimension, p_age: age, p_filters: f, p_token: a.token });
export const fetchLevers = (a: Access, onlySystem: boolean) => rpc<Levers>("perf_levers", { p_ws: a.ws, p_only_system: onlySystem, p_token: a.token });
export const setAccount = (a: Access, account: string, patch: Partial<{ tier: string | null; creator: string | null; health_state: string; health_note: string | null }>) =>
  rpc<PerfCenter>("perf_account_set", { p_ws: a.ws, p_account: account, p_patch: patch, p_token: a.token });
export const setOrigin = (a: Access, account: string, externalId: string, origin: "sistema" | "externo", reason: string) =>
  rpc<unknown>("perf_origin_set", { p_ws: a.ws, p_account: account, p_external_id: externalId, p_origin: origin, p_reason: reason, p_token: a.token });
