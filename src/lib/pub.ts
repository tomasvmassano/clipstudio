import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Elements, Platform, PolicyRequired, PubStatus } from "@/lib/pub-rules";

/* Calendário de publicações (PRD §42 PUB-02/04/06, TEAM-10, FR-21-01/02/04, VAR-01; ADR-0036). Nada aqui publica. */

export type Conflict = { code: string; severity: "bloqueia" | "aviso"; message: string };
export type Approval = { side: "agencia" | "cliente"; actor_label: string | null; actor_role: string; revision: number; decided_at: string;
  invalidated_at: string | null; invalidated_reason: string | null };
export type PubVariantRef = { id: string; label: string; elements: Elements; changes: number; counts_as_new: boolean;
  edit_style_key: string | null; edit_style_version: number | null };
export type Publication = {
  id: string; status: PubStatus; kind: "original" | "republicacao"; revision: number; approved_revision: number | null; approved_at: string | null;
  lock_version: number; correlation_id: string; lineage_id: number | null; parent_publication_id: string | null;
  content_id: string; content_n: number; content_date: string; content_tema: string | null; content_hook: string | null;
  content_version_id: string; version_no: number; version_approved: boolean; variant: PubVariantRef | null;
  account_id: string; account_handle: string; account_label: string | null; platform: Platform;
  scheduled_at: string; local_day: string; local_time: string; caption: string; hashtags: string[]; cancelled_reason: string | null;
  created_label: string | null; revision_label: string | null; updated_at: string;
  missing: string[]; approvals: Approval[]; conflicts: Conflict[]; can_approve: boolean; approve_blocked: string | null;
  /** FR-12-02: registo da publicação manual (só quando status = publicada). */
  published?: Published | null; can_record?: boolean; record_blocked?: string | null;
};
export type Published = {
  mode: "manual"; url: string; external_id: string; at: string; local_day: string; local_time: string;
  media_version_id: string; media_version_no: number | null; asset_id: string | null; asset_title: string | null;
  by_label: string | null; recorded_at: string; corrections: number;
  history: { action: "pub.published_recorded" | "pub.published_corrected"; at: string; by: string | null; reason: string | null; before_url: string | null; url: string | null }[];
};
export type RecordVideo = { version_id: string; version: number; asset_id: string; title: string; variant: string; style: string | null; status: string; eligible: boolean };
export type RecordOptions = {
  timezone: string; can_record: boolean; media_available: boolean;
  video: { version_id: string; version: number; asset_id: string; title: string; approved: boolean; current: boolean } | null;
  publications: Publication[]; videos: RecordVideo[];
};
export type RecordInput = { url: string; published_at: string; media_version_id: string; revision?: number };
export type PubAccount = { id: string; platform: Platform; handle: string; label: string | null; active: boolean; connection_state: string; token_expires_at: string | null };
export type PlatformLimit = {
  platform: Platform; max_posts: number; window_kind: "rolling_24h" | "calendar_day"; window_tz: string; scope: "conta" | "projeto";
  public_requires_audit: boolean; note: string | null; verified_on: string; republish_min_days: number | null; republish_max_share: number | null;
  republish_identical: boolean; updated_at: string; updated_label: string | null;
};
export type PubCalendar = {
  today: string; timezone: string; publications: Publication[]; accounts: PubAccount[]; limits: PlatformLimit[];
  policy: { required: PolicyRequired; forbid_self: boolean; updated_at: string | null; updated_label: string | null };
  me: { side: "agencia" | "cliente"; role: string } | null;
  can: { schedule: boolean; approve: boolean; republish_approve: boolean; policy: boolean; accounts: boolean; limits: boolean; record?: boolean };
  publish_available: false; publish_unavailable_reason: string;
};
export type ContentOption = { id: string; n: number; date: string; tema: string | null; hook: string | null; editorial_status: string; approved: boolean };
export type Variant = PubVariantRef & { platform: Platform | null; content_version_id: string; archived: boolean; created_at: string; created_label: string | null;
  siblings: { id: string; label: string; diff: number }[] };
export type ContentDetail = {
  versions: { id: string; version_no: number; created_at: string; approved: boolean; current: boolean }[];
  approved_version_id: string | null; variants: Variant[]; styles: { key: string; version: number; name: string }[];
};
export type PubInput = Partial<{
  content_id: string; content_version_id: string; variant_id: string | null; account_id: string; scheduled_at: string;
  caption: string; hashtags: string[]; kind: "original" | "republicacao"; parent_publication_id: string;
}>;

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    // as validações do servidor explicam o problema em "detail" (conflitos, limites, política)
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const fetchPubCalendar = (a: Access, from: string, to: string) =>
  rpc<PubCalendar>("pub_calendar", { p_ws: a.ws, p_from: from, p_to: to, p_token: a.token });
export const fetchContentOptions = (a: Access) => rpc<ContentOption[]>("pub_content_options", { p_ws: a.ws, p_content_id: null, p_token: a.token });
export const fetchContentDetail = (a: Access, id: string) => rpc<ContentDetail>("pub_content_options", { p_ws: a.ws, p_content_id: id, p_token: a.token });
export const savePublication = (a: Access, id: string | null, input: PubInput, lock?: number) =>
  rpc<Publication>("pub_save", { p_ws: a.ws, p_id: id, p_input: input, p_lock: lock ?? null, p_token: a.token });
export const cancelPublication = (a: Access, id: string, reason: string) =>
  rpc<Publication>("pub_cancel", { p_ws: a.ws, p_id: id, p_reason: reason, p_token: a.token });
export const approvePublication = (a: Access, id: string, revision: number) =>
  rpc<Publication>("pub_approve", { p_ws: a.ws, p_id: id, p_revision: revision, p_token: a.token });
export const approveBatch = (a: Access, items: { id: string; revision: number }[]) =>
  rpc<{ id: string; ok: boolean; status?: string; code?: string; error?: string; detail?: string }[]>("pub_approve_batch", { p_ws: a.ws, p_items: items, p_token: a.token });
export const saveVariant = (a: Access, input: { content_id: string; content_version_id: string; label: string; platform: Platform | null;
  edit_style_key: string | null; edit_style_version: number | null; elements: Elements; supersedes_id?: string | null }) =>
  rpc<ContentDetail>("pub_variant_save", { p_ws: a.ws, p_input: input, p_token: a.token });
export const archiveVariant = (a: Access, id: string) => rpc<ContentDetail>("pub_variant_archive", { p_ws: a.ws, p_id: id, p_token: a.token });
export const savePolicy = (a: Access, policy: { required: PolicyRequired; forbid_self: boolean }) =>
  rpc<{ required: PolicyRequired; forbid_self: boolean; reopened: number }>("pub_policy_save", { p_ws: a.ws, p_policy: policy, p_token: a.token });
export const saveLimit = (a: Access, platform: Platform, patch: Partial<PlatformLimit>) =>
  rpc<PlatformLimit[]>("pub_limit_save", { p_ws: a.ws, p_platform: platform, p_patch: patch, p_token: a.token });
export const addAccount = (a: Access, platform: Platform, handle: string, label: string) =>
  rpc<PubAccount>("pub_account_add", { p_ws: a.ws, p_platform: platform, p_handle: handle, p_label: label || null, p_token: a.token });

/** FR-12-02: o que entra no registo (por publicação, no calendário; ou por vídeo, na revisão). */
export const fetchRecordOptions = (a: Access, by: { publication?: string; version?: string }) =>
  rpc<RecordOptions>("pub_record_options", { p_ws: a.ws, p_id: by.publication ?? null, p_version: by.version ?? null, p_token: a.token });
/** Regista que foi publicado à mão (ou corrige o registo, com motivo). Nada é publicado pela app. */
export const recordPublished = (a: Access, id: string, input: RecordInput, reason?: string | null) =>
  rpc<Publication & { replayed: boolean; corrected: boolean }>("pub_record_published", { p_ws: a.ws, p_id: id, p_input: input, p_reason: reason ?? null, p_token: a.token });
