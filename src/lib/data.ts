import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { ContentHistory, ContentPatch, EditorialTarget, Guiao, Idea, Session } from "@/lib/types";

// ---------- datas (sempre em Asia/Dubai) ----------
export function todayDubai(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Dubai", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
export function addDays(iso: string, k: number): string {
  const d = new Date(iso + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + k);
  return d.toISOString().slice(0, 10);
}
export function niceDate(iso: string): string {
  return new Intl.DateTimeFormat("pt-PT", { weekday: "long", day: "numeric", month: "short", timeZone: "UTC" }).format(new Date(iso + "T12:00:00Z"));
}
export function dayLabel(iso: string): string {
  const t = todayDubai();
  if (iso === t) return "Hoje";
  if (iso === addDays(t, 1)) return "Amanhã";
  if (iso === addDays(t, -1)) return "Ontem";
  return iso;
}

// ---------- guiões ----------
/** Guiões do dia e dos `carryDays` anteriores. Login: tabela com RLS. Código: RPC legacy_guioes. */
export async function fetchGuioes(access: Access, date: string, carryDays = 3): Promise<Guiao[]> {
  const from = addDays(date, -carryDays);
  const sb = supabase();
  const { data, error } = access.token
    ? await sb.rpc("legacy_guioes", { p_token: access.token, p_from: from, p_to: date })
    : await sb.from("guioes").select("*").eq("client_id", access.ws).gte("date", from).lte("date", date)
        .order("date", { ascending: true }).order("n", { ascending: true });
  if (error) throw new Error(friendlyError(error.message));
  return (data ?? []) as Guiao[];
}

/** Rejeitados e arquivados não entram na fila de gravação (PRD §4). */
export const recordable = (g: Guiao) => g.editorial_status !== "rejected" && g.editorial_status !== "archived";

export function splitDay(all: Guiao[], date: string) {
  const day = all.filter((g) => g.date === date);
  const carry = all.filter((g) => g.date < date && recordable(g) && ["not_started", "scheduled", "recording"].includes(g.production_status));
  return { day, carry };
}

export function tpQueue(all: Guiao[], date: string): Guiao[] {
  const { day, carry } = splitDay(all, date);
  return [...carry, ...day.filter(recordable)];
}

async function rpc<T>(fn: string, args: Record<string, unknown>, prefix = ""): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(prefix + friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

/** Guarda a cópia de trabalho. `lock` = lock_version que o ecrã viu; se mudou entretanto o servidor recusa (PT409, HTTP 409). */
export const saveContent = (access: Access, id: string, patch: ContentPatch, lock?: number) =>
  rpc<Guiao>("content_save", { p_id: id, p_patch: patch, p_lock: lock ?? null, p_token: access.token }, "Não foi possível guardar: ");

export const transitionContent = (access: Access, id: string, to: EditorialTarget, reason?: string, lock?: number) =>
  rpc<Guiao>("content_transition", { p_id: id, p_to: to, p_reason: reason ?? null, p_lock: lock ?? null, p_token: access.token });

export const setProduction = (access: Access, id: string, to: "recorded" | "not_started") =>
  rpc<Guiao>("content_production", { p_id: id, p_to: to, p_token: access.token });

export const createContent = (access: Access, fields: ContentPatch & { date: string }) =>
  rpc<Guiao>("content_create", { p_ws: access.ws, p_fields: fields, p_token: access.token });

export const duplicateContent = (access: Access, id: string) => rpc<Guiao>("content_duplicate", { p_id: id, p_token: access.token });

export const fetchHistory = (access: Access, id: string) => rpc<ContentHistory>("content_history", { p_id: id, p_token: access.token });

export const restoreVersion = (access: Access, id: string, versionId: string, lock?: number) =>
  rpc<Guiao>("content_restore_version", { p_id: id, p_version: versionId, p_lock: lock ?? null, p_token: access.token });

/** Ao vivo só com login (postgres_changes respeita o RLS). No modo código a página recarrega de 20 em 20 s. */
export function subscribeGuioes(access: Access, onChange: () => void): () => void {
  if (access.token) {
    const t = setInterval(onChange, 20000);
    return () => clearInterval(t);
  }
  const ch = supabase()
    .channel("guioes-" + access.ws)
    .on("postgres_changes", { event: "*", schema: "public", table: "guioes", filter: `client_id=eq.${access.ws}` }, onChange)
    .subscribe();
  return () => {
    supabase().removeChannel(ch);
  };
}

// ---------- ideias ----------
export async function fetchIdeas(access: Access, limit = 100): Promise<Idea[]> {
  const sb = supabase();
  const { data, error } = access.token
    ? await sb.rpc("legacy_ideas", { p_token: access.token, p_limit: limit })
    : await sb.from("ideas").select("*").eq("client_id", access.ws).order("created_at", { ascending: false }).limit(limit);
  if (error) throw new Error(friendlyError(error.message));
  return (data ?? []) as Idea[];
}

// ---------- sessão (código de equipa) ----------
const KEY = "studio.session";
export function loadSession(): Session | null {
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    return null;
  }
}
export function saveSession(s: Session | null) {
  try {
    if (s) localStorage.setItem(KEY, JSON.stringify(s));
    else localStorage.removeItem(KEY);
  } catch {}
}
/** null = código inválido ou revogado; erro de rede ou pedido interrompido lança (não é motivo para terminar a sessão). */
export async function checkToken(token: string): Promise<Session | null> {
  const { data, error } = await supabase().rpc("studio_whoami", { p_token: token });
  if (error) throw new Error(error.message);
  if (!data || !data.length) return null;
  const r = data[0] as { client_id: string; role: string; label: string | null };
  return { token, client_id: r.client_id, role: r.role, label: r.label };
}

// ---------- texto ----------
export const words = (s: string | null | undefined) => (s ?? "").trim().split(/\s+/).filter(Boolean).length;
export function teleprompterText(queue: Guiao[]): string {
  return queue.map((g, i) => `${i + 1}\n\n${g.hooks.map((h) => h.text).join("\n\n")}\n\n—\n\n${g.corpo}${g.cta ? `\n\n${g.cta}` : ""}`).join("\n\n\n\n") + "\n";
}
