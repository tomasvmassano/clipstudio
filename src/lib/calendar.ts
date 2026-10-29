import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import { addDays } from "@/lib/data";

/* Calendário e produção (PRD M11; ADR-0008). */

export type ProductionStatus = "not_started" | "scheduled" | "recording" | "recorded" | "editing" | "ready" | "published" | "cancelled";
export const PRODUCTION_LABEL: Record<ProductionStatus, string> = {
  not_started: "Por gravar", scheduled: "Agendado", recording: "A gravar", recorded: "Gravado", editing: "Em edição", ready: "Pronto",
  published: "Publicado", cancelled: "Cancelado",
};
export type CalContent = {
  id: string; n: number; date: string; tema: string | null; formato: string | null; hook: string | null;
  editorial_status: string; production_status: ProductionStatus; lock_version: number; late: boolean; open_tasks: number;
};
export type CalTask = {
  id: string; title: string; kind: string; status: string; priority: string; due_at: string; assignee_email: string | null;
  content_id: string | null; lock_version: number; overdue: boolean;
};
export type CalSession = { id: string; date: string; closed: boolean; takes: number };
export type CalendarData = {
  today: string; contents: CalContent[]; tasks: CalTask[]; sessions: CalSession[];
  can: { schedule: boolean; production: boolean; record: boolean; tasks: boolean };
};

/** Transições de produção que a app oferece (o servidor valida outra vez). */
export function nextProduction(s: ProductionStatus, can: CalendarData["can"]): { to: ProductionStatus; label: string }[] {
  const out: { to: ProductionStatus; label: string }[] = [];
  if (can.schedule && s === "not_started") out.push({ to: "scheduled", label: "Agendar gravação" });
  if (can.schedule && s === "scheduled") out.push({ to: "not_started", label: "Tirar da agenda" });
  if (can.record && (s === "not_started" || s === "scheduled")) out.push({ to: "recorded", label: "Marcar gravado" });
  if (can.record && s === "recorded") out.push({ to: "not_started", label: "Desfazer gravado" });
  if (can.production && (s === "recorded" || s === "ready")) out.push({ to: "editing", label: s === "ready" ? "Voltar a edição" : "Passar a edição" });
  if (can.production && s === "editing") out.push({ to: "ready", label: "Marcar pronto" }, { to: "recorded", label: "Voltar a gravado" });
  if (can.schedule && s !== "cancelled" && s !== "published") out.push({ to: "cancelled", label: "Cancelar" });
  if (can.schedule && s === "cancelled") out.push({ to: "not_started", label: "Reativar" });
  return out;
}

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}
export const fetchCalendar = (access: Access, from: string, to: string) =>
  rpc<CalendarData>("calendar_range", { p_ws: access.ws, p_from: from, p_to: to, p_token: access.token });
export const reschedule = (access: Access, id: string, date: string, lock?: number) =>
  rpc<CalContent>("content_reschedule", { p_id: id, p_date: date, p_lock: lock ?? null, p_token: access.token });
export const setProductionStatus = (access: Access, id: string, to: ProductionStatus) =>
  rpc<unknown>("content_production", { p_id: id, p_to: to, p_token: access.token });

export type CalView = "month" | "week" | "day";
/** segunda-feira da semana de `iso` */
export function weekStart(iso: string) {
  const d = new Date(iso + "T12:00:00Z");
  return addDays(iso, -((d.getUTCDay() + 6) % 7));
}
export function rangeFor(view: CalView, anchor: string): { from: string; to: string; days: string[] } {
  let from = anchor, to = anchor;
  if (view === "week") { from = weekStart(anchor); to = addDays(from, 6); }
  if (view === "month") {
    const first = anchor.slice(0, 8) + "01";
    const d = new Date(first + "T12:00:00Z"); d.setUTCMonth(d.getUTCMonth() + 1); d.setUTCDate(0);
    const last = d.toISOString().slice(0, 10);
    from = weekStart(first); to = addDays(weekStart(last), 6);
  }
  const days: string[] = [];
  for (let x = from; x <= to; x = addDays(x, 1)) days.push(x);
  return { from, to, days };
}
export function shift(view: CalView, anchor: string, k: number) {
  if (view === "day") return addDays(anchor, k);
  if (view === "week") return addDays(anchor, 7 * k);
  const d = new Date(anchor.slice(0, 8) + "01T12:00:00Z"); d.setUTCMonth(d.getUTCMonth() + k);
  return d.toISOString().slice(0, 10);
}
/** dia (YYYY-MM-DD) de um instante no fuso do workspace */
export function dayInTz(iso: string, tz: string) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
}
export const monthTitle = (iso: string) =>
  new Intl.DateTimeFormat("pt-PT", { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(iso + "T12:00:00Z"));
export const dayTitle = (iso: string) =>
  new Intl.DateTimeFormat("pt-PT", { weekday: "short", day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(iso + "T12:00:00Z"));
