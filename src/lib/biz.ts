import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/*
 * Vista de negócio da agência (PRD §38, BIZ-01 a BIZ-06; ADR-0032).
 * O servidor constrói a resposta por pessoa: sem biz.finance não vem nenhum campo financeiro. Aqui só se desenha o que vem.
 */

export type Currency = "EUR" | "AED";
export type Severity = "critico" | "alto" | "aviso";

export type Attainment = {
  contract?: boolean; contracted: number | null; expected_to_date: number | null; deadline_days?: number;
  on_time: number; late_published?: number; overdue?: number; due_today?: number; late_client?: number; late_agency?: number;
  pct: number | null; pace: number | null; alert?: boolean | null; target: number; alert_below: number;
};
export type StalledStage = { stage: string; kind: string; samples: number; open: number; p50_h: number | null; p70_h: number | null; over_p70: number; over_p50: number };
export type Ops = {
  "ops.today"?: { date: string; planned: number; recorded: number; target: number | null };
  "ops.approvals"?: { pending: number; over_48h: number };
  "ops.stalled"?: { over_p70: number; over_p50: number; open: number; unmeasured: number; stages: StalledStage[] };
  "ops.attainment"?: Attainment;
  "ops.first_pass"?: { approved: number; first_pass: number; pct: number | null };
  "ops.approval_time"?: { n: number; median_h: number | null };
  "ops.performance"?: { n: number; median: number | null };
  "ops.reach"?: { n7: number; n30: number; median_7d: number | null; median_30d: number | null; ratio: number | null };
};
export type Fin = {
  contract: boolean; contract_status: string | null; amount: number | null; contract_currency: Currency | null; billing_period: string | null;
  "fin.mrr": number | null; mrr_original: number | null; "fin.cost": number | null; cost_ai: number | null; cost_direct: number | null; cost_shared: number | null;
  "fin.margin": number | null; videos: number; views: number; "fin.cost_per_video": number | null; "fin.cost_per_1k": number | null;
  "fin.payment": { status: PaymentStatus; due_on: string | null; overdue_days: number | null } | null;
  "fin.renewal": { on: string; days: number } | null; fx_missing: boolean;
};
export type BizClient = { id: string; name: string; handle: string | null; logo_path: string | null; brand_color: string | null; timezone: string; ops: Ops; fin?: Fin };
export type BizMetric = { key: string; level: "operacional" | "financeiro"; label: string; description: string; capability: string; available: boolean; unavailable_reason: string | null };
export type AttentionCard = {
  key: string; severity: Severity; level: "operacional" | "financeiro"; client_id: string; client_name: string;
  title: string; detail: string; action_label: string; action_href: string; trend?: { date: string; share: number | null }[];
};
export type BizOverview = {
  month: string; currency: Currency; finance: boolean; can_manage: boolean; count: number;
  metrics: BizMetric[]; clients: BizClient[]; missing: Record<string, number>;
  totals: Ops & {
    "fin.mrr"?: number; "fin.cost"?: number | null; "fin.margin"?: number | null; "fin.cost_per_video"?: number | null; "fin.cost_per_1k"?: number | null;
    at_risk?: number; concentration?: { client_id: string; client_name: string; trend: { date: string; share: number | null }[] }[];
  };
  attention: { cards: AttentionCard[]; more: number; unavailable: { key: string; label: string; reason: string }[] };
  fx?: { base: "EUR"; quote: "AED"; rate: number; as_of: string; source: string | null } | null;
  fx_missing?: boolean;
};

export type PaymentStatus = "em_dia" | "pendente" | "vencido";
export type BillingPeriod = "mensal" | "trimestral" | "anual";
export type Contract = {
  id: string; workspace_id: string; version: number; status: "ativo" | "terminado"; amount: number; currency: Currency; billing_period: BillingPeriod;
  scripts_per_month: number | null; videos_per_month: number | null; platforms: string[]; deadline_days: number;
  starts_on: string | null; renewal_on: string | null; effective_from: string; payment_status: PaymentStatus; payment_due_on: string | null;
  notes: string | null; created_at: string; created_label: string | null;
};
export type ContractsResp = {
  can_manage: boolean;
  fx: { rate: number; as_of: string; source: string | null; created_label: string | null } | null;
  fx_history: { rate: number; as_of: string; source: string | null; created_at: string; created_label: string | null }[];
  clients: { id: string; name: string; currency: string; versions: number; contract: Contract | null }[];
};
export type CostKind = "humano" | "ferramentas" | "outro";
export type Allocation = "direto" | "igual" | "por_videos";
export type Cost = {
  id: string; workspace_id: string | null; client_name: string | null; month: string; kind: CostKind; label: string; amount: number; currency: Currency;
  allocation: Allocation; created_at: string; created_label: string | null; voided_at: string | null; void_reason: string | null;
};
export type CostsResp = { month: string; can_manage: boolean; costs: Cost[] };

export class BizError extends Error {
  code?: string;
  constructor(message: string, code?: string) { super(message); this.code = code; }
}
async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  // as validações do servidor explicam o problema em "detail"
  if (error) throw new BizError(error.details || friendlyError(error.message), error.code);
  return data as T;
}
/** Sem permissão ou funcionalidade desligada: não adianta tentar de novo. */
export const isForbidden = (e: unknown) => e instanceof BizError && (e.code === "42501" || e.code === "55000");

export const fetchOverview = (month: string, currency: Currency) => rpc<BizOverview>("biz_overview", { p_month: month, p_currency: currency });
export const fetchContracts = () => rpc<ContractsResp>("biz_contracts", {});
export const fetchContractHistory = (ws: string) => rpc<Contract[]>("biz_contract_history", { p_ws: ws });
export const saveContract = (ws: string, fields: Partial<Record<keyof Contract, unknown>>, expected: number) =>
  rpc<ContractsResp>("biz_contract_save", { p_ws: ws, p_fields: fields, p_expected: expected });
export const saveFx = (rate: number, asOf: string, source: string) => rpc<ContractsResp>("biz_fx_save", { p_rate: rate, p_as_of: asOf, p_source: source });
export const fetchCosts = (month: string) => rpc<CostsResp>("biz_costs", { p_month: month });
export const saveCost = (fields: Record<string, unknown>, clientRef: string) => rpc<CostsResp>("biz_cost_save", { p_fields: fields, p_client_ref: clientRef });
export const voidCost = (id: string, reason: string) => rpc<CostsResp>("biz_cost_void", { p_id: id, p_reason: reason });

const PT = "pt-PT";
/** Mês atual (fuso de Dubai, o da agência) em AAAA-MM. */
export function currentMonth(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Dubai", year: "numeric", month: "2-digit" }).format(now).slice(0, 7);
}
export const monthLabel = (ym: string) => new Date(`${ym.slice(0, 7)}-15T12:00:00Z`).toLocaleDateString(PT, { month: "long", year: "numeric", timeZone: "UTC" });
export const fmtDate = (iso: string | null | undefined) => iso ? new Date(`${iso.slice(0, 10)}T12:00:00Z`).toLocaleDateString(PT, { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }) : "-";
/** null fica "-": nunca um 0 inventado. */
export const fmtNum = (v: number | null | undefined, digits = 0) => v == null ? "-" : new Intl.NumberFormat(PT, { maximumFractionDigits: digits }).format(Number(v));
export const fmtPct = (v: number | null | undefined) => v == null ? "-" : `${new Intl.NumberFormat(PT, { maximumFractionDigits: 1 }).format(Number(v))}%`;
export const fmtMoney = (v: number | null | undefined, cur: Currency | string) =>
  v == null ? "-" : new Intl.NumberFormat(PT, { style: "currency", currency: cur, maximumFractionDigits: 2 }).format(Number(v));
export const fmtHours = (h: number | null | undefined) => h == null ? "-" : h < 48 ? `${fmtNum(h, 1)} h` : `${fmtNum(h / 24, 1)} d`;

export const PAYMENT_LABEL: Record<PaymentStatus, string> = { em_dia: "Em dia", pendente: "Pendente", vencido: "Vencido" };
export const PERIOD_LABEL: Record<BillingPeriod, string> = { mensal: "Mensal", trimestral: "Trimestral", anual: "Anual" };
export const KIND_LABEL: Record<CostKind, string> = { humano: "Humano", ferramentas: "Ferramentas", outro: "Outro" };
export const ALLOCATION_LABEL: Record<Allocation, string> = { direto: "Direto ao cliente", igual: "Agência, partes iguais", por_videos: "Agência, por vídeos publicados" };
export const SEVERITY_LABEL: Record<Severity, string> = { critico: "Crítico", alto: "Alto", aviso: "Aviso" };
export const STAGE_LABEL: Record<string, string> = {
  draft: "Rascunho", in_review: "Em revisão", changes_requested: "Alterações pedidas", scheduled: "Agendado",
  recording: "A gravar", recorded: "Gravado", editing: "Em edição", ready: "Pronto",
};

/** Número com estado: atingimento abaixo do alerta é mau, acima da meta é bom. */
export function attainmentTone(a: Attainment | undefined): "bad" | "warn" | "good" | "none" {
  const v = a?.pace ?? a?.pct;
  if (v == null || !a) return "none";
  if (v < a.alert_below) return "bad";
  if (v < a.target) return "warn";
  return "good";
}
