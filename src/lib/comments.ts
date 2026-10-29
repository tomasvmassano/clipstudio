import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

/** Comentários contextuais de um guião (W2-06, FR-05-02). Não se apagam nem se reescrevem; resolvem-se. */
export type CommentBlock = "geral" | "corpo" | "cta" | "notas" | `hook_${number}`;
export type ContentComment = {
  id: string; parent_id: string | null; block: CommentBlock; quote: string | null; body: string;
  author: string; author_id: string | null; author_kind: "user" | "legacy_code"; at: string;
  version_no: number | null; on_current: boolean; resolved_at: string | null; resolved_by: string | null;
};
export type CommentThread = { comments: ContentComment[]; can: { comment: boolean; resolve: boolean }; me: string | null };

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchComments = (access: Access, id: string) => rpc<CommentThread>("content_comments", { p_id: id, p_token: access.token });
export const addComment = (access: Access, id: string, c: { block: CommentBlock; body: string; quote?: string | null; parent?: string | null }) =>
  rpc<ContentComment>("content_comment_add", { p_id: id, p_block: c.block, p_body: c.body, p_quote: c.quote ?? null, p_mentions: [], p_parent: c.parent ?? null, p_token: access.token });
export const resolveComment = (access: Access, commentId: string, resolved: boolean) =>
  rpc<ContentComment>("content_comment_resolve", { p_comment: commentId, p_resolved: resolved, p_token: access.token });

export const blockLabel = (b: string) =>
  b === "geral" ? "Geral" : b === "corpo" ? "Corpo" : b === "cta" ? "CTA" : b === "notas" ? "Notas" : b.startsWith("hook_") ? `Hook ${b.slice(5)}` : b;

/* ---------- Caixa de revisão (FR-05-01) ---------- */

export type ReviewFilters = { status?: string[]; assignee?: string; priority?: string; due?: string; q?: string };
export type ReviewItem = {
  guiao: Guiao; open_comments: number; all_comments: number; last_activity: string | null; version_no: number | null;
  task: { id: string; priority: string; due_at: string | null; assignee_id: string | null; assignee: string | null } | null;
};
export type ReviewInbox = { items: ReviewItem[]; counts: Record<string, number>; assignees: { id: string; label: string }[]; today: string };
export const fetchReviewInbox = (access: Access, f: ReviewFilters) => {
  const clean = Object.fromEntries(Object.entries(f).filter(([, v]) => v != null && v !== "" && !(Array.isArray(v) && v.length === 0)));
  return rpc<ReviewInbox>("review_inbox", { p_ws: access.ws, p_filters: clean, p_token: access.token });
};
