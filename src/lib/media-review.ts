import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/** Revisão de vídeo (W5-04, FR-05-03, CHG-006; W5-12, EDL-02) por cima da biblioteca de media: ativo ligado ao guião, versão
 *  atual num link da Google Drive ou num ficheiro guardado (export do editor, upload), variante e estilo nas etiquetas (hook_N, Sxx),
 *  notas do QC técnico (EDL-03) quando o worker as gravou. Só por RPC; o servidor decide quem pode o quê. */
export type ReviewStatus = "in_review" | "approved" | "changes_requested" | "rejected";
export type QcCheck = { key: string; ok: boolean; value?: unknown; expected?: unknown; detail?: string; label?: string };
export type QcReport = { version: string; passed: boolean | null; error?: string | null; checks: QcCheck[] };
export type QcSummary = { passed: boolean | null; version: string | null; error: string | null; failed: number };
export type Player = "drive" | "ficheiro";
export type ReviewItem = {
  asset_id: string; title: string; variant: string; style: string | null; version_id: string; version: number;
  drive_file_id: string | null; url: string | null; player: Player; proxy: boolean; duration: number | null; qc: QcSummary | null;
  status: ReviewStatus; decided_at: string | null; decided_by: string | null;
  open_comments: number; all_comments: number;
  guiao: { id: string; n: number; date: string; tema: string | null; hook: string | null } | null;
};
export type ReviewList = { items: ReviewItem[]; counts: Partial<Record<ReviewStatus, number>>; can: { comment: boolean; decide: boolean; link: boolean } };
export type ReviewComment = {
  id: string; parent_id: string | null; t_ms: number | null; body: string; author: string; author_id: string | null;
  at: string; resolved_at: string | null; resolved_by: string | null;
};
export type ReviewDetail = {
  item: ReviewItem;
  version: {
    id: string; version: number; drive_file_id: string | null; url: string | null; status: ReviewStatus; current: boolean;
    player: Player; proxy: boolean; duration: number | null; qc: QcReport | null; decided_by: string | null; decided_at: string | null;
  };
  versions: { id: string; version: number; status: ReviewStatus }[];
  comments: ReviewComment[];
  decisions: { from: string; to: ReviewStatus; reason: string | null; by: string; at: string }[];
  can: { comment: boolean; decide: boolean }; me: string | null;
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchReviewList = (access: Access, f: { status?: ReviewStatus[]; q?: string }) =>
  rpc<ReviewList>("media_review_list", { p_ws: access.ws, p_filters: Object.fromEntries(Object.entries(f).filter(([, v]) => v != null && v !== "")), p_token: access.token });
export const fetchReview = (access: Access, assetId: string, versionId?: string | null) =>
  rpc<ReviewDetail>("media_review_detail", { p_ws: access.ws, p_asset: assetId, p_version: versionId ?? null, p_token: access.token });
export const addReviewComment = (access: Access, versionId: string, body: string, tMs: number | null, parent?: string | null) =>
  rpc<ReviewComment>("media_review_comment", { p_ws: access.ws, p_version: versionId, p_body: body, p_t_ms: tMs, p_parent: parent ?? null, p_token: access.token });
export const resolveReviewComment = (access: Access, commentId: string, resolved: boolean) =>
  rpc<ReviewComment>("media_review_comment_resolve", { p_ws: access.ws, p_comment: commentId, p_resolved: resolved, p_token: access.token });
export const decideReview = (access: Access, versionId: string, status: Exclude<ReviewStatus, "in_review">, reason?: string) =>
  rpc<ReviewItem>("media_review_decide", { p_ws: access.ws, p_version: versionId, p_status: status, p_reason: reason ?? null, p_token: access.token });

export const REVIEW_STATUS: { v: ReviewStatus; l: string }[] = [
  { v: "in_review", l: "Por rever" }, { v: "changes_requested", l: "Alterações pedidas" }, { v: "approved", l: "Aprovados" }, { v: "rejected", l: "Rejeitados" },
];
export const statusLabel = (s: ReviewStatus) => REVIEW_STATUS.find((x) => x.v === s)?.l ?? s;
export const variantLabel = (v: string) => (v.startsWith("hook_") ? `Hook ${v.slice(5)}` : "Geral");

export { nextInQueue, qcValue } from "@/lib/review-queue";
