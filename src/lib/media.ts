import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/** Revisão de vídeo por link da Google Drive (W5-04, FR-05-03, CHG-006). Só por RPC; o servidor decide quem pode o quê. */
export type MediaStatus = "in_review" | "approved" | "changes_requested" | "rejected";
export type Media = {
  id: string; content_id: string; variant: string; style: string | null; version: number; drive_file_id: string; file_name: string | null;
  duration_s: number | null; review_status: MediaStatus; created_at: string; created_by: string | null; decided_at: string | null;
  decided_by: string | null; latest: boolean; open_comments: number; all_comments: number;
};
export type MediaItem = { media: Media; guiao: { id: string; n: number; date: string; tema: string | null; hook: string | null } };
export type MediaList = { items: MediaItem[]; counts: Partial<Record<MediaStatus, number>>; can: { link: boolean; comment: boolean; decide: boolean } };
export type MediaComment = {
  id: string; parent_id: string | null; t_ms: number | null; body: string; author: string; author_id: string | null;
  author_kind: "user" | "legacy_code"; at: string; resolved_at: string | null; resolved_by: string | null;
};
export type MediaDetail = {
  media: Media; comments: MediaComment[]; versions: { id: string; version: number; review_status: MediaStatus; created_at: string }[];
  decisions: { from: string; to: MediaStatus; reason: string | null; by: string; at: string }[];
  can: { comment: boolean; decide: boolean }; me: string | null;
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchMediaList = (access: Access, f: { status?: MediaStatus[]; q?: string }) =>
  rpc<MediaList>("media_review_list", { p_ws: access.ws, p_filters: Object.fromEntries(Object.entries(f).filter(([, v]) => v != null && v !== "")), p_token: access.token });
export const fetchMedia = (access: Access, id: string) => rpc<MediaDetail>("media_detail", { p_media: id, p_token: access.token });
export const addMediaComment = (access: Access, id: string, body: string, tMs: number | null, parent?: string | null) =>
  rpc<MediaComment>("media_comment_add", { p_media: id, p_body: body, p_t_ms: tMs, p_parent: parent ?? null, p_token: access.token });
export const resolveMediaComment = (access: Access, commentId: string, resolved: boolean) =>
  rpc<MediaComment>("media_comment_resolve", { p_comment: commentId, p_resolved: resolved, p_token: access.token });
export const decideMedia = (access: Access, id: string, status: Exclude<MediaStatus, "in_review">, reason?: string) =>
  rpc<Media>("media_decide", { p_media: id, p_status: status, p_reason: reason ?? null, p_token: access.token });

export const MEDIA_STATUS: { v: MediaStatus; l: string }[] = [
  { v: "in_review", l: "Por rever" }, { v: "changes_requested", l: "Alterações pedidas" }, { v: "approved", l: "Aprovados" }, { v: "rejected", l: "Rejeitados" },
];
export const statusLabel = (s: MediaStatus) => MEDIA_STATUS.find((x) => x.v === s)?.l ?? s;
export const variantLabel = (v: string) => (v.startsWith("hook_") ? `Hook ${v.slice(5)}` : "Geral");
