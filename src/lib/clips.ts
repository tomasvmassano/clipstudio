import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { ExportJob, PackageExportResult } from "@/lib/edit-media";
import type { ClipMeta } from "@/lib/clips-format";

/**
 * Cortes de vídeos longos (Clip Miner, CLIP-01..07, ADR-0060): pedir, ver o job real e os cortes, exportar todos.
 * Tudo por RPC; o servidor decide (clips.mine, edit.export, flags clips.miner, edit.studio e media.r2).
 */
export type ClipRow = {
  idx: number; asset_id: string; title: string; meta: ClipMeta; active: boolean; version_no: number | null; has_video: boolean;
  export: { status: ExportJob["status"]; progress: ExportJob["progress"] } | null;
};
export type ClipJob = Omit<ExportJob, "kind" | "result"> & {
  kind: "clips"; version_id: string | null; master_name: string | null; master_title: string | null; master_active: boolean; count: number; clips: ClipRow[];
  result: { clips?: unknown[]; flags?: string[]; blocked?: { start: string; end: string; reason: string }[]; rejected?: string[];
            sentences?: number; candidates?: number; model?: string; prompt_version?: string } | null;
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const requestClips = (a: Access, version: string, count: number) =>
  rpc<ClipJob>("clips_request", { p_ws: a.ws, p_version: version, p_count: count, p_token: a.token });
export const listClips = (a: Access) => rpc<ClipJob[]>("clips_list", { p_ws: a.ws, p_token: a.token });
export const exportClips = (a: Access, job: string) => rpc<PackageExportResult>("clips_export", { p_ws: a.ws, p_job: job, p_token: a.token });
