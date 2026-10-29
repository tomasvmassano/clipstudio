import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { ExportRow, SearchItem } from "@/lib/search-format";
export { searchHref, toCsv, type ExportRow, type SearchItem, type SearchKind } from "@/lib/search-format";

/*
 * Pesquisa global, paleta de comandos e operações em lote nos guiões (FR-16-01, FR-16-02, FR-01-05, FR-17-07; ADR-0035).
 * O servidor decide sempre o que cada pessoa pode ver e fazer: aqui só se mostra o que vem das RPCs.
 */

export type SearchGroup = { kind: string; label: string; more: boolean; items: SearchItem[] };
export type SearchResult = { q: string; mode: "suggestions" | "tag" | "text" | "short"; workspaces: number; groups: SearchGroup[] };
export type QuickActions = { source: boolean; script: boolean; project: boolean; task: boolean };
export type SearchScope = { enabled: { id: string; name: string }[]; actions: QuickActions | null };

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const fetchSearchScope = (ws: string | null, token: string | null) => rpc<SearchScope>("search_scope", { p_ws: ws, p_token: token });
export const searchGlobal = (q: string, ws: string | null, token: string | null, limit = 5) =>
  rpc<SearchResult>("search_global", { p_q: q, p_ws: ws, p_limit: limit, p_token: token });


// ---------- operações em lote ----------
export type BulkAction = "owner" | "project" | "tags" | "approve" | "reschedule";
export type BulkSnapshot = { owner_id: string | null; owner: string | null; project_id: string | null; project: string | null; tags: string[]; editorial_status: string; date: string; n: number };
export type BulkItem = { id: string; ok: boolean; changed: boolean; before: BulkSnapshot | null; after?: BulkSnapshot; code?: string; error?: string; detail?: string | null };
export type BulkResult = { replayed: boolean; preview: boolean; key: string | null; results: BulkItem[]; summary: { total: number; ok: number; changed: number; failed: number } };

export const bulkRun = (a: Access, ids: string[], action: BulkAction, args: Record<string, unknown>, key: string | null, preview: boolean) =>
  rpc<BulkResult>("content_bulk", { p_ws: a.ws, p_ids: ids, p_action: action, p_args: args, p_key: key, p_preview: preview, p_token: a.token });

export const bulkExport = (a: Access, ids: string[]) => rpc<{ rows: ExportRow[]; missing: number }>("content_bulk_export", { p_ws: a.ws, p_ids: ids, p_token: a.token });

