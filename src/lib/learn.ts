import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

/*
 * Aprendizagem e qualidade (W7, ADR-0037): motivos de rejeição e retrabalho (FR-17-10), experiências (FR-17-11),
 * repetir vencedor (FR-17-12), recomendações (SCALE-06), cargos no convite (BIZ-08), exportar os meus dados (FR-14-05)
 * e custo por guião e publicação (FR-10-05). Tudo por RPCs: o servidor verifica capacidade e flag em cada chamada.
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

// ---------- FR-17-10 motivos e retrabalho ----------
export type ReworkStage = "guiao" | "video";
export type ReworkReason = {
  id: string; code: string; label: string; description: string | null; applies_to: ReworkStage[]; active: boolean; sort: number; uses: number;
};
export type ReworkReasonList = { enabled: boolean; can_manage: boolean; reasons: ReworkReason[] };
export type ReworkByReason = { code: string; label: string; changes: number; rejected: number; hours_lost: number };
export type ReworkMonth = {
  month: string; stage: ReworkStage; decisions: number; changes: number; rejected: number; contents: number; contents_rework: number;
  rework_rate: number | null; cycles_closed: number; cycles_open: number; hours_lost: number; hours_median: number | null; by_reason: ReworkByReason[];
};
export type ReworkDashboard = {
  timezone: string; months: number; since: string;
  stages: { key: ReworkStage; label: string; available: boolean; reason?: string }[];
  reasons: ReworkReason[]; by_month: ReworkMonth[]; by_reason: ReworkByReason[];
  totals: { decisions: number; changes: number; rejected: number; uncategorized: number; rework_rate: number | null; hours_lost: number; cycles_open: number };
};

export const fetchReworkReasons = (a: Access) => rpc<ReworkReasonList>("rework_reasons_list", { p_ws: a.ws, p_token: a.token });
export const seedReworkReasons = (a: Access) => rpc<ReworkReasonList>("rework_reasons_seed", { p_ws: a.ws, p_token: a.token });
export const saveReworkReason = (a: Access, id: string | null, fields: Partial<Pick<ReworkReason, "code" | "label" | "description" | "applies_to" | "active" | "sort">>) =>
  rpc<ReworkReasonList>("rework_reason_save", { p_ws: a.ws, p_id: id, p_fields: fields, p_token: a.token });
export const fetchReworkDashboard = (a: Access, months: number) => rpc<ReworkDashboard>("rework_dashboard", { p_ws: a.ws, p_months: months, p_token: a.token });
export const transitionReasoned = (a: Access, id: string, to: "changes_requested" | "rejected", reason: string, code: string, lock?: number) =>
  rpc<Guiao>("content_transition_reasoned", { p_id: id, p_to: to, p_reason: reason, p_reason_code: code, p_lock: lock ?? null, p_token: a.token });

// ---------- FR-17-11 experiências, FR-17-12 vencedores, SCALE-06 recomendações ----------
export type ExpDimension = "hook_mechanism" | "hook_index" | "formato" | "edit_style_key";
export const DIMENSION_LABEL: Record<ExpDimension, string> = {
  hook_mechanism: "Mecanismo do hook", hook_index: "Hook 1, 2 ou 3 sobre o mesmo corpo", formato: "Formato", edit_style_key: "Estilo de edição",
};
export type ExpStatus = "rascunho" | "a_decorrer" | "concluida" | "cancelada";
export const EXP_STATUS_LABEL: Record<ExpStatus, string> = { rascunho: "Rascunho", a_decorrer: "A decorrer", concluida: "Concluída", cancelada: "Cancelada" };
export type ExpOutcome = "confirmada" | "refutada" | "inconclusiva";
export const OUTCOME_LABEL: Record<ExpOutcome, string> = { confirmada: "Confirmada", refutada: "Refutada", inconclusiva: "Inconclusiva" };
export type Variant = { key: string; value: string; label: string };
export type VariantResult = Variant & {
  n_pubs: number; n: number; median: number | null; best: number | null; worst: number | null; accounts: number; inferred: number; sufficient: boolean;
  items: { reel_id: string; handle: string; platform: string; url: string | null; title: string; idx: number | null; published_at: string; content_id: string | null }[];
};
export type ExpResults = {
  variants: VariantResult[]; by_account: { account_id: string; handle: string; platform: string; per: Record<string, { n: number; median: number | null }> }[];
  matched: number; unmatched: number; computed_at: string; sufficient: boolean; leader: string | null; ratio: number | null;
  criterion_met: boolean | null; warnings: string[]; inferred_share: number | null; note: string;
};
export type Experiment = {
  id: string; title: string; hypothesis: string; dimension: ExpDimension; variants: Variant[]; accounts: string[];
  window_start: string; window_end: string; age: "24h" | "72h" | "7d"; min_per_variant: number; decision_ratio: number; decision_note: string | null;
  include_external: boolean; status: ExpStatus; outcome: ExpOutcome | null; conclusion: string | null; lever: string | null;
  concluded_at: string | null; concluded_label: string | null; created_at: string; created_label: string | null; updated_at: string;
  results: ExpResults | null; preview?: ExpResults;
};
export type ExpFields = Partial<Pick<Experiment, "title" | "hypothesis" | "dimension" | "variants" | "accounts" | "window_start" | "window_end" | "age"
  | "min_per_variant" | "decision_ratio" | "decision_note" | "include_external">>;
export type LearnParams = { winner_idx: number; winner_age: string; winner_days: number; lever_up: number; lever_down: number; min_base: number; min_sample: number };
export type ExperimentList = {
  can_manage: boolean; params: LearnParams; accounts: { id: string; platform: string; handle: string }[]; experiments: Experiment[];
};
export type Winner = {
  reel_id: string; account_id: string; handle: string; platform: string; url: string | null; title: string; published_at: string;
  origin: "sistema" | "externo"; lineage_mode: "gravada" | "inferida"; idx: number; content_id: string | null; hook_text: string | null; formato: string | null;
  repeats: { content_id: string; kind: "continuacao" | "variacao"; created_at: string; status: string }[];
};
export type Recommendation = {
  kind: "experiencia" | "alavanca"; direction: "repetir" | "evitar" | "rever"; title: string; detail: string | null; experiment_id?: string;
  evidence: Record<string, unknown>; limitations: string[];
};

export const fetchExperiments = (a: Access) => rpc<ExperimentList>("learn_experiments_list", { p_ws: a.ws, p_token: a.token });
export const fetchExperiment = (a: Access, id: string) => rpc<Experiment>("learn_experiment_get", { p_ws: a.ws, p_id: id, p_token: a.token });
export const saveExperiment = (a: Access, id: string | null, fields: ExpFields) =>
  rpc<Experiment>("learn_experiment_save", { p_ws: a.ws, p_id: id, p_fields: fields, p_token: a.token });
export const actExperiment = (a: Access, id: string, action: "start" | "conclude" | "cancel", fields: { outcome?: ExpOutcome; conclusion?: string; lever?: string } = {}) =>
  rpc<Experiment>("learn_experiment_act", { p_ws: a.ws, p_id: id, p_action: action, p_fields: fields, p_token: a.token });
export const fetchWinners = (a: Access) => rpc<{ params: LearnParams; can_create: boolean; items: Winner[] }>("learn_winners", { p_ws: a.ws, p_token: a.token });
export const repeatWinner = (a: Access, reel: string, kind: "continuacao" | "variacao", note: string, clientRef: string) =>
  rpc<{ content_id: string; date?: string; created: boolean }>("learn_repeat_winner",
    { p_ws: a.ws, p_reel_id: reel, p_kind: kind, p_note: note || null, p_client_ref: clientRef, p_token: a.token });
export const fetchRecommendations = (a: Access) =>
  rpc<{ params: LearnParams; items: Recommendation[]; limitations: string[] }>("learn_recommendations", { p_ws: a.ws, p_token: a.token });

// ---------- BIZ-08 cargos no convite ----------
export type JobTemplate = {
  key: string; label: string; role: string; modules: string; note?: string; grants: string[]; role_capabilities: string[];
  grant_options: { key: string; label: string; in_role: boolean; grantable: boolean }[];
};
export const fetchJobTemplates = (ws: string) => rpc<{ can_grant: boolean; templates: JobTemplate[] }>("job_title_templates", { p_ws: ws });
export const inviteWithTitle = (ws: string, email: string, role: string, affiliation: "agency_staff" | "client_staff", title: string, grants: string[]) =>
  rpc<string>("invite_member_with_title", { p_ws: ws, p_email: email.trim(), p_role: role, p_affiliation: affiliation, p_job_title: title, p_grants: grants });

// ---------- FR-14-05 os meus dados ----------
export type PrivacyRequest = {
  id: string; kind: "eliminacao"; status: "pendente" | "tratado" | "recusado" | "cancelado"; reason: string | null; resolution: string | null;
  created_at: string; resolved_at: string | null; email?: string; user_id?: string; workspaces?: string[];
};
export const fetchMyDataStatus = () => rpc<{ available: boolean; requests: PrivacyRequest[] }>("my_data_status", {});
export const exportMyData = () => rpc<Record<string, unknown>>("my_data_export", {});
export const requestDeletion = (reason: string) => rpc<PrivacyRequest>("my_data_deletion_request", { p_reason: reason || null });
export const fetchPrivacyRequests = () => rpc<{ items: PrivacyRequest[] }>("privacy_requests_admin", {});
export const resolvePrivacyRequest = (id: string, status: "tratado" | "recusado", resolution: string) =>
  rpc<{ items: PrivacyRequest[] }>("privacy_request_resolve", { p_id: id, p_status: status, p_resolution: resolution });

// ---------- FR-10-05 custos ----------
export type CostMonth = {
  month: string; ai_total: number; jobs_unknown: number; unattributed: number; attributed: number; scripts: number;
  cost_per_script: number | null; publications: number; cost_per_publication: number | null;
};
export type CostScript = {
  content_id: string; n: number; date: string; tema: string | null; editorial_status: string; cost_eur: number | null; cost_known: boolean;
  method: "partes_iguais" | "por_posicao" | "desconhecido"; jobs: number; publications: number; cost_per_publication: number | null;
};
export type CostReport = { currency: "EUR"; months: number; allocation: string; video: { available: boolean; reason: string }; by_month: CostMonth[]; scripts: CostScript[] };
export const fetchCosts = (a: Access, months: number) => rpc<CostReport>("content_costs", { p_ws: a.ws, p_months: months, p_token: a.token });
export const exportCosts = (a: Access, months: number) => rpc<CostReport>("content_costs_export", { p_ws: a.ws, p_months: months, p_token: a.token });

export { toCsv, eur, pct, hours, monthLabel } from "@/lib/learn-format";

export function download(name: string, body: string, type: string) {
  const url = URL.createObjectURL(new Blob([type.startsWith("text/csv") ? "\ufeff" + body : body], { type }));
  const el = document.createElement("a");
  el.href = url; el.download = name;
  document.body.appendChild(el); el.click(); el.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
