import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/*
 * Início por cliente e painel da agência (PRD FR-01-01, FR-01-02, R-04; ADR-0017).
 * O servidor decide que widgets e números cada pessoa vê; aqui só se desenha o que vem.
 */

export type Kpi = { value: number | null; prev: number | null };
export type Widget = { key: string; kind: "kpi" | "chart" | "panel"; label: string; description: string; snapshot: boolean };
export type Period = { from: string; to: string; prev_from: string; prev_to: string };
export type DashboardResp = {
  period: Period; role: string; customized: boolean; can_configure: boolean;
  widgets: Widget[]; kpis: Record<string, Kpi | number> & { costs_unknown?: number; reels?: number };
  target_per_day: number | null;
};
export type AgencyClient = { id: string; name: string; handle: string | null; logo_path: string | null; brand_color: string | null; timezone: string; kpis: Record<string, Kpi | number> };
export type AgencyResp = { period: Period; clients: AgencyClient[]; totals: Record<string, Kpi>; missing: Record<string, number>; count: number };
export type LayoutsResp = {
  widgets: (Widget & { capabilities: string[] })[];
  roles: { role: string; widgets: string[]; customized: boolean; updated_at: string | null }[];
};

export const LAYOUT_ROLES = ["workspace_owner", "workspace_admin", "manager", "reviewer", "contributor", "viewer"] as const;

/** Períodos rápidos; "custom" usa as datas escolhidas. */
export const PERIODS = [
  { key: "7", label: "7 dias", days: 7 },
  { key: "30", label: "30 dias", days: 30 },
  { key: "90", label: "90 dias", days: 90 },
] as const;
export type PeriodKey = (typeof PERIODS)[number]["key"] | "custom";

/** Hoje no fuso do cliente, em AAAA-MM-DD. */
export function todayIn(tz: string, now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
export function addDays(iso: string, n: number): string {
  const d = new Date(`${iso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
export function rangeFor(key: PeriodKey, tz: string, custom?: { from: string; to: string }): { from: string; to: string } {
  if (key === "custom" && custom?.from && custom?.to && custom.from <= custom.to) return { from: custom.from, to: custom.to };
  const days = PERIODS.find((p) => p.key === key)?.days ?? 30;
  const to = todayIn(tz);
  return { from: addDays(to, -(days - 1)), to };
}

/** Período escolhido fica guardado neste browser (conveniência por pessoa; se falhar, volta aos 30 dias). */
const PERIOD_KEY = "clipstudio.dashboard.period";
export function loadPeriod(): { key: PeriodKey; from: string; to: string } {
  try {
    const v = JSON.parse(localStorage.getItem(PERIOD_KEY) ?? "null");
    if (v && ["7", "30", "90", "custom"].includes(v.key)) return { key: v.key, from: v.from ?? "", to: v.to ?? "" };
  } catch { /* sem storage */ }
  return { key: "30", from: "", to: "" };
}
export function savePeriod(p: { key: PeriodKey; from: string; to: string }) {
  try { localStorage.setItem(PERIOD_KEY, JSON.stringify(p)); } catch { /* sem storage */ }
}

export async function fetchDashboard(access: Access, from: string, to: string): Promise<DashboardResp> {
  const { data, error } = await supabase().rpc("dashboard_get", { p_ws: access.ws, p_from: from, p_to: to, p_token: access.token });
  if (error) throw new Error(friendlyError(error.message));
  return data as DashboardResp;
}
export async function fetchAgency(from: string, to: string): Promise<AgencyResp> {
  const { data, error } = await supabase().rpc("agency_dashboard", { p_from: from, p_to: to });
  if (error) throw new Error(friendlyError(error.message));
  return data as AgencyResp;
}
export async function fetchLayouts(ws: string): Promise<LayoutsResp> {
  const { data, error } = await supabase().rpc("dashboard_layouts_get", { p_ws: ws });
  if (error) throw new Error(friendlyError(error.message));
  return data as LayoutsResp;
}
export async function saveLayout(ws: string, role: string, widgets: string[]): Promise<LayoutsResp> {
  const { data, error } = await supabase().rpc("dashboard_layout_set", { p_ws: ws, p_role: role, p_widgets: widgets });
  if (error) throw new Error(friendlyError(error.message));
  return data as LayoutsResp;
}
export async function resetLayout(ws: string, role: string): Promise<LayoutsResp> {
  const { data, error } = await supabase().rpc("dashboard_layout_reset", { p_ws: ws, p_role: role });
  if (error) throw new Error(friendlyError(error.message));
  return data as LayoutsResp;
}

export const asKpi = (v: Kpi | number | undefined): Kpi | null => (v && typeof v === "object" ? v : null);

const PT = "pt-PT";
/** Valor de um KPI pronto a mostrar; null fica "—" (nunca 0 inventado). */
export function fmtKpi(key: string, v: number | null | undefined): string {
  if (v == null) return "—";
  if (key === "kpi.engagement") return `${new Intl.NumberFormat(PT, { maximumFractionDigits: 2 }).format(v)}%`;
  if (key === "kpi.costs") return new Intl.NumberFormat(PT, { style: "currency", currency: "EUR" }).format(v);
  if (key === "kpi.views") return new Intl.NumberFormat(PT, { notation: "compact", maximumFractionDigits: 1 }).format(v);
  return new Intl.NumberFormat(PT, { maximumFractionDigits: 0 }).format(v);
}

/** Variação em %; sem base comparável devolve undefined em vez de inventar. */
export function deltaPct(k: Kpi | null, snapshot = false): number | undefined {
  if (!k || snapshot || k.prev == null || k.value == null || Number(k.prev) === 0) return undefined;
  return ((Number(k.value) - Number(k.prev)) / Number(k.prev)) * 100;
}

export const fmtRange = (from: string, to: string) => {
  const f = (iso: string) => new Date(`${iso}T12:00:00Z`).toLocaleDateString(PT, { day: "numeric", month: "short", timeZone: "UTC" });
  return from === to ? f(from) : `${f(from)} a ${f(to)}`;
};

/** Custos: menos é melhor. */
export const LOWER_IS_BETTER = new Set(["kpi.costs", "kpi.pending_approval"]);
