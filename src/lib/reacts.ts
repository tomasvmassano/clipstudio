import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { ReactAi } from "@/lib/reacts-format";

/* Radar de reacts (W10-25, PRD §47). Tudo passa por RPCs com permissão e flag verificadas no servidor. */

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details && error.code !== "42501" ? error.details : friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export type ReactTab = "open" | "saved" | "recorded" | "rejected" | "expired";
export type ReactItem = {
  id: number; platform: "instagram" | "tiktok"; ref_key: string; url: string; author: string | null; caption: string | null;
  posted_at: string | null; duration_s: number | null; thumb_url: string | null; has_video: boolean;
  metrics: { views?: number; likes?: number; comments?: number; ck?: number; author_median_ck?: number; polemic_index?: number; collected_at?: string };
  video_type: string | null; transcript: string | null; ai: ReactAi | null; score: number | null; risk_level: string | null;
  expires_at: string; expired: boolean; status: "open" | "saved" | "recorded" | "rejected";
  reject_reason: string | null; rating: number | null; decision_note: string | null; decided_at: string | null; decided_label: string | null;
  content_id: string | null; created_at: string; source: { id: string; handle: string; status: string } | null;
};
export type ReactList = {
  items: ReactItem[]; counts: Record<ReactTab, number>; last_run: string | null;
  can: { decide: boolean; record: boolean; sources: boolean };
};
export type ReactSource = {
  id: string; platform: "instagram" | "tiktok"; handle: string; status: "proposed" | "active" | "paused" | "rejected"; origin: string;
  origin_detail: string | null; score: number | null; stats: Record<string, unknown>; created_kind: "user" | "agent"; created_at: string;
  decided_at: string | null; decided_label: string | null; decision_note: string | null; candidates: number;
};

export const fetchReacts = (a: Access, tab: ReactTab) => rpc<ReactList>("reacts_list", { p_ws: a.ws, p_tab: tab, p_token: a.token });
export const decideReact = (a: Access, id: number, action: "save" | "reject" | "reopen" | "rate", o: { reason?: string; rating?: number; note?: string } = {}) =>
  rpc<ReactItem>("react_decide", { p_id: id, p_action: action, p_reason: o.reason ?? null, p_rating: o.rating ?? null, p_note: o.note ?? null, p_token: a.token });
export const recordReact = (a: Access, id: number) =>
  rpc<{ content_id: string; created: boolean; item: ReactItem }>("react_record", { p_id: id, p_token: a.token });
export const fetchReactSources = (a: Access) => rpc<{ items: ReactSource[]; can: { manage: boolean } }>("react_sources_list", { p_ws: a.ws, p_token: a.token });
export const decideReactSource = (a: Access, id: string, action: "accept" | "reject" | "pause" | "resume", note?: string) =>
  rpc<ReactSource>("react_source_decide", { p_id: id, p_action: action, p_note: note ?? null, p_token: a.token });
export const addReactSource = (a: Access, platform: "instagram" | "tiktok", handle: string) =>
  rpc<ReactSource>("react_source_add", { p_ws: a.ws, p_platform: platform, p_handle: handle, p_token: a.token });

/** URL da rota que serve o vídeo (ver dentro da app) ou o descarrega (dl). A rota volta a verificar a permissão. */
export const reactVideoUrl = (ws: string, id: number, dl = false) => `/api/reacts/${id}/video?ws=${encodeURIComponent(ws)}${dl ? "&dl=1" : ""}`;
