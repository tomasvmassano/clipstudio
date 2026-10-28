import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/* Teleprompter: sessões de gravação, fila, takes e preferências (PRD M03, ADR-0006). */

export type BlockKey = `hook_${number}` | "body" | "cta";
export type TakeRow = {
  id: string; block_key: BlockKey; take_number: number; status: "ok" | "discarded"; selected: boolean; notes: string | null;
  version_id: string | null; session_id: string; created_label: string | null; created_at: string;
  /** só no cliente: take marcado sem ligação, ainda por enviar */
  pending?: boolean;
};
export type SessionContent = {
  id: string; n: number; date: string; tema: string | null; formato: string | null;
  hooks: { text: string; mecanismo?: string }[]; corpo: string; cta: string | null;
  editorial_status: string; production_status: string; current_version_id: string | null;
};
export type SessionItem = {
  content_id: string; position: number; skipped: boolean; skipped_blocks: BlockKey[]; carried: boolean;
  content: SessionContent; takes: TakeRow[];
};
export type RecordingSession = {
  id: string; workspace_id: string; date: string; opened_label: string | null; opened_at: string; closed_at: string | null;
  last_content_id: string | null; last_block: BlockKey | null; last_pct: number | null; last_at: string | null;
  require_approval: boolean; items: SessionItem[];
};

export type Block = { key: BlockKey; label: string; text: string };

/** Blocos de um guião pela ordem de gravação: Hook 1..N, Body, CTA (se existir). */
export function blocksOf(c: SessionContent): Block[] {
  const out: Block[] = [];
  (c.hooks ?? []).forEach((h, i) => { if (h?.text?.trim()) out.push({ key: `hook_${i + 1}`, label: `Hook ${i + 1}`, text: h.text }); });
  if (c.corpo?.trim()) out.push({ key: "body", label: "Body", text: c.corpo });
  if (c.cta?.trim()) out.push({ key: "cta", label: "CTA", text: c.cta });
  return out;
}
export const blockLabel = (k: string) => (k === "body" ? "Body" : k === "cta" ? "CTA" : k.startsWith("hook_") ? `Hook ${k.slice(5)}` : k);

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(friendlyError(error.message)) as Error & { code?: string; raw?: string };
    e.code = error.code; e.raw = error.message;
    throw e;
  }
  return data as T;
}

export const openSession = (access: Access, date: string) =>
  rpc<RecordingSession>("recording_session_open", { p_ws: access.ws, p_date: date, p_token: access.token });
export const setQueue = (access: Access, session: string, items: { content_id: string; skipped?: boolean; skipped_blocks?: string[] }[]) =>
  rpc<RecordingSession>("recording_queue_set", { p_session: session, p_items: items, p_token: access.token });
export const saveProgress = (access: Access, session: string, content: string, block: string | null, pct: number) =>
  rpc<null>("recording_progress", { p_session: session, p_content: content, p_block: block, p_pct: Math.min(1, Math.max(0, pct)), p_token: access.token });
export const closeSession = (access: Access, session: string) =>
  rpc<RecordingSession>("recording_session_close", { p_session: session, p_token: access.token });
export const createTake = (access: Access, t: PendingTake) =>
  rpc<TakeRow>("take_create", { p_session: t.session, p_content: t.content, p_block: t.block, p_client_ref: t.client_ref, p_notes: t.notes ?? null, p_token: access.token });
export const updateTake = (access: Access, id: string, patch: { selected?: boolean; status?: "ok" | "discarded"; notes?: string }) =>
  rpc<TakeRow>("take_update", { p_take: id, p_patch: patch, p_token: access.token });

// ---------- takes por enviar (offline / falha de rede) ----------
// Cada take tem um client_ref gerado no dispositivo: reenviar é seguro, o servidor devolve o mesmo take.
export type PendingTake = { session: string; content: string; block: BlockKey; client_ref: string; notes?: string | null; at: string; error?: string };

const outboxKey = (ws: string) => `tp.outbox.${ws}`;
export function readOutbox(ws: string): PendingTake[] {
  try { return JSON.parse(localStorage.getItem(outboxKey(ws)) ?? "[]") as PendingTake[]; } catch { return []; }
}
export function writeOutbox(ws: string, list: PendingTake[]) {
  try { localStorage.setItem(outboxKey(ws), JSON.stringify(list)); } catch {}
}
/** Erros que não se resolvem a repetir (permissão, validação): o take sai da fila de envio e o erro fica visível. */
export const permanentError = (code?: string) => !!code && ["42501", "22023", "P0002", "28000"].includes(code);

// ---------- preferências ----------
export type TpKeys = Partial<Record<TpAction, string[]>>;
export type TpAction = "play" | "faster" | "slower" | "next" | "prev" | "next_block" | "prev_block" | "take" | "mirror" | "font_up" | "font_down" | "fullscreen" | "exit";
export type TpPrefs = {
  speed: number; font: number; line_height: number; margin: number; mirror_h: boolean; mirror_v: boolean;
  contrast: "normal" | "alto" | "ambar"; keys: TpKeys; confirm_on_advance: boolean;
};
export const ACTION_LABEL: Record<TpAction, string> = {
  play: "Rolar / parar", faster: "Mais depressa", slower: "Mais devagar", next: "Guião seguinte", prev: "Guião anterior",
  next_block: "Bloco seguinte", prev_block: "Bloco anterior", take: "Marcar take", mirror: "Espelho horizontal",
  font_up: "Letra maior", font_down: "Letra mais pequena", fullscreen: "Ecrã inteiro", exit: "Sair",
};
// Comandos Bluetooth de teleprompter enviam setas, PageUp/PageDown, Espaço ou Enter.
export const DEFAULT_KEYS: Required<TpKeys> = {
  play: [" "], faster: ["ArrowUp"], slower: ["ArrowDown"], next: ["ArrowRight", "PageDown"], prev: ["ArrowLeft", "PageUp"],
  next_block: ["b"], prev_block: ["v"], take: ["t", "Enter"], mirror: ["m"], font_up: ["+", "="], font_down: ["-"], fullscreen: ["f"], exit: ["Escape"],
};
export const DEFAULT_PREFS: TpPrefs = {
  speed: 4, font: 56, line_height: 1.38, margin: 6, mirror_h: false, mirror_v: false, contrast: "normal", keys: {}, confirm_on_advance: true,
};
export const keyName = (k: string) => (k === " " ? "Espaço" : k === "Escape" ? "Esc" : k.startsWith("Arrow") ? { ArrowUp: "↑", ArrowDown: "↓", ArrowLeft: "←", ArrowRight: "→" }[k] ?? k : k);

export function clampPrefs(p: Partial<TpPrefs>): TpPrefs {
  const n = (v: unknown, lo: number, hi: number, d: number) => (typeof v === "number" && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d);
  return {
    speed: Math.round(n(p.speed, 1, 10, DEFAULT_PREFS.speed)),
    font: Math.round(n(p.font, 32, 96, DEFAULT_PREFS.font)),
    line_height: n(p.line_height, 1, 2.2, DEFAULT_PREFS.line_height),
    margin: Math.round(n(p.margin, 0, 25, DEFAULT_PREFS.margin)),
    mirror_h: typeof p.mirror_h === "boolean" ? p.mirror_h : DEFAULT_PREFS.mirror_h,
    mirror_v: typeof p.mirror_v === "boolean" ? p.mirror_v : DEFAULT_PREFS.mirror_v,
    contrast: p.contrast === "alto" || p.contrast === "ambar" ? p.contrast : "normal",
    keys: p.keys && typeof p.keys === "object" ? p.keys : {},
    confirm_on_advance: typeof p.confirm_on_advance === "boolean" ? p.confirm_on_advance : true,
  };
}

/** Identificador deste dispositivo (só para separar preferências do iPad das do computador). */
export function deviceId(): string {
  try {
    let id = localStorage.getItem("tp.device");
    if (!id || !/^[A-Za-z0-9_-]{8,64}$/.test(id)) {
      id = "d-" + crypto.randomUUID().replace(/-/g, "").slice(0, 20);
      localStorage.setItem("tp.device", id);
    }
    return id;
  } catch {
    return "d-sem-armazenamento";
  }
}
export function readLocalPrefs(): TpPrefs {
  try {
    const raw = localStorage.getItem("tp.prefs");
    if (raw) return clampPrefs(JSON.parse(raw) as Partial<TpPrefs>);
    // preferências da versão anterior do teleprompter
    const old = (k: string) => { const v = localStorage.getItem(k); return v == null ? undefined : JSON.parse(v); };
    return clampPrefs({ speed: old("tp.speed"), font: old("tp.font"), mirror_h: old("tp.mirror") });
  } catch {
    return DEFAULT_PREFS;
  }
}
export function writeLocalPrefs(p: TpPrefs) {
  try { localStorage.setItem("tp.prefs", JSON.stringify(p)); } catch {}
}
export const fetchServerPrefs = (device: string) => rpc<Partial<TpPrefs> | null>("tp_prefs_get", { p_device: device });
export const saveServerPrefs = (device: string, p: TpPrefs) => rpc<TpPrefs>("tp_prefs_set", { p_device: device, p_prefs: p });
