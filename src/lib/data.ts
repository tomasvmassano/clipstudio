import { supabase, DEFAULT_CLIENT } from "@/lib/supabase";
import type { Guiao, GuiaoPatch, Idea, Session } from "@/lib/types";

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
export async function fetchGuioes(date: string, clientId = DEFAULT_CLIENT, carryDays = 3): Promise<Guiao[]> {
  const { data, error } = await supabase()
    .from("guioes")
    .select("*")
    .eq("client_id", clientId)
    .gte("date", addDays(date, -carryDays))
    .lte("date", date)
    .order("date", { ascending: true })
    .order("n", { ascending: true });
  if (error) throw error;
  return (data ?? []) as Guiao[];
}

export function splitDay(all: Guiao[], date: string) {
  const day = all.filter((g) => g.date === date);
  const carry = all.filter((g) => g.date < date && g.status !== "rejeitado" && !g.gravado);
  return { day, carry };
}

export function tpQueue(all: Guiao[], date: string): Guiao[] {
  const { day, carry } = splitDay(all, date);
  return [...carry, ...day.filter((g) => g.status !== "rejeitado")];
}

export async function updateGuiao(id: string, patch: GuiaoPatch, token: string): Promise<Guiao> {
  const { data, error } = await supabase().rpc("guiao_update", { p_id: id, p_patch: patch, p_token: token });
  if (error) {
    if (error.message.includes("codigo_invalido")) throw new Error("Código de equipa inválido. Pede um novo ao Tomás.");
    throw new Error("Não foi possível guardar: " + error.message);
  }
  return data as Guiao;
}

export function subscribeGuioes(clientId: string, onChange: () => void): () => void {
  const ch = supabase()
    .channel("guioes-" + clientId)
    .on("postgres_changes", { event: "*", schema: "public", table: "guioes", filter: `client_id=eq.${clientId}` }, onChange)
    .subscribe();
  return () => {
    supabase().removeChannel(ch);
  };
}

// ---------- ideias ----------
export async function fetchIdeas(limit = 100): Promise<Idea[]> {
  const { data, error } = await supabase().from("ideas").select("*").order("created_at", { ascending: false }).limit(limit);
  if (error) throw error;
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
export async function checkToken(token: string): Promise<Session | null> {
  const { data, error } = await supabase().rpc("studio_whoami", { p_token: token });
  if (error || !data || !data.length) return null;
  const r = data[0] as { client_id: string; role: string; label: string | null };
  return { token, client_id: r.client_id, role: r.role, label: r.label };
}

// ---------- texto ----------
export const words = (s: string | null | undefined) => (s ?? "").trim().split(/\s+/).filter(Boolean).length;
export function teleprompterText(queue: Guiao[]): string {
  return queue.map((g, i) => `${i + 1}\n\n${g.hooks.map((h) => h.text).join("\n\n")}\n\n—\n\n${g.corpo}`).join("\n\n\n\n") + "\n";
}
