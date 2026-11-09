import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/**
 * Editor: imagem na pré-visualização e exportar (EDL-08, EDL-11, ADR-0047). As fontes (proxies das gravações no R2) e os
 * jobs de exportação vêm por RPC; os links assinados pela rota /api/media/versions/:id/proxy. O servidor decide tudo.
 */
export type CamSource = { state: "pronta" | "pendente" | "falhou" | "nao_aplica" | "em_falta"; version_id?: string; name?: string;
  media_info?: { duration?: number; width?: number; height?: number } | null;
  /** Som substituto ligado à gravação (W10-32, ADR-0080): o palco toca-o no lugar do som do vídeo. */
  audio_version_id?: string | null };
export type PreviewSources = { windows: [number, number][] | null; audio: string | null; cams: Record<string, CamSource>; names: Record<string, string> | null };
export type ExportJob = {
  id: string; kind: "export"; status: "queued" | "running" | "done" | "failed" | "dead" | "cancelled"; attempts: number; max_attempts: number;
  progress: { pct?: number; step?: string } | null; result: { version_id?: string; version_no?: number } | null; last_error: string | null;
  created_label: string | null; created_at: string; started_at: string | null; finished_at: string | null; edit_version_no: number | null;
  worker_seen: boolean;
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

export const fetchPreviewSources = (a: Access, asset: string, version?: string | null) =>
  rpc<PreviewSources>("edit_preview_sources", { p_ws: a.ws, p_asset: asset, p_version: version ?? null, p_token: a.token });

export async function proxyUrl(a: Access, versionId: string, soft = false): Promise<{ url: string; expires_at: string }> {
  const r = await fetch(`/api/media/versions/${versionId}/proxy?ws=${encodeURIComponent(a.ws)}${soft ? "&soft=1" : ""}`, { cache: "no-store" });
  const b = (await r.json().catch(() => ({}))) as { url?: string; expires_at?: string; error?: string };
  if (!r.ok || !b.url) throw new Error(b.error ?? `Não consegui abrir a versão leve (${r.status}).`);
  return { url: b.url, expires_at: b.expires_at ?? "" };
}

/** Link assinado curto (5 min) para ouvir um áudio da Biblioteca: o som substituto no palco. Quando expira, o palco pede outro. */
export async function audioUrl(a: Access, versionId: string): Promise<{ url: string; expires_at: string }> {
  const r = await fetch(`/api/media/versions/${versionId}/url?ws=${encodeURIComponent(a.ws)}&purpose=preview`, { cache: "no-store" });
  const b = (await r.json().catch(() => ({}))) as { url?: string; expires_at?: string; error?: string };
  if (!r.ok || !b.url) throw new Error(b.error ?? `Não consegui abrir o som substituto (${r.status}).`);
  return { url: b.url, expires_at: b.expires_at ?? "" };
}

export const requestExport = (a: Access, asset: string, version?: string | null) =>
  rpc<ExportJob>("edit_export_request", { p_ws: a.ws, p_asset: asset, p_version: version ?? null, p_token: a.token });
export const listExports = (a: Access, asset: string) => rpc<ExportJob[]>("edit_export_list", { p_ws: a.ws, p_asset: asset, p_token: a.token });
export const cancelExport = (a: Access, job: string) => rpc<ExportJob>("edit_export_cancel", { p_ws: a.ws, p_job: job, p_token: a.token });

export const EXPORT_STATUS: Record<ExportJob["status"], string> = {
  queued: "na fila", running: "a exportar", done: "pronto", failed: "falhou", dead: "falhou depois de várias tentativas", cancelled: "cancelado",
};

// ---------- pacote automático (EDL-01, ADR-0048) ----------
export type PackageJob = Omit<ExportJob, "kind" | "result"> & {
  kind: "package"; front_name: string | null; side_name: string | null; version_id: string | null;   // version_id = câmara do lado
  guioes: { id: string; n: number; tema: string | null; deleted?: boolean }[] | null;
  outputs: { guiao_id: string; hook: number; asset_id: string; title: string }[];
  result: { documents?: unknown[]; missing?: string[]; flags?: string[]; offset?: { front: number; side?: number; confidence: number }; windows?: unknown } | null;
};
export type EditDocRow = {
  asset_id: string; title: string; content_id: string | null; tags: string[]; version_no: number; source: "import" | "ai" | "user" | "agent";
  updated_at: string; created_label: string | null; has_video: boolean; confidence: { hook?: number | null; body?: number | null } | null;
  flags: string[] | null; guiao: { id: string; n: number; date: string; tema: string | null } | null;
  export: { status: ExportJob["status"]; progress: ExportJob["progress"] } | null;
};
export const requestPackage = (a: Access, front: string, side: string, guioes: string[], style: string, audio: "front" | "side" = "side") =>
  rpc<PackageJob>("edit_package_request", { p_ws: a.ws, p_front: front, p_side: side, p_guioes: guioes, p_style: style, p_token: a.token, p_audio: audio });
export const listPackages = (a: Access) => rpc<PackageJob[]>("edit_package_list", { p_ws: a.ws, p_token: a.token });
export const listEditDocs = (a: Access) => rpc<EditDocRow[]>("edit_doc_list", { p_ws: a.ws, p_token: a.token });

/** Exportar todos os vídeos de um pacote (EDL-02): um job por vídeo; os que falham (ex.: câmara em falta) vêm em `failed`. */
export type PackageExportResult = { queued: number; jobs: { asset_id: string; job_id: string; status: ExportJob["status"] }[];
  failed: { asset_id: string; title: string; error: string }[] };
export const exportPackage = (a: Access, job: string) => rpc<PackageExportResult>("edit_package_export", { p_ws: a.ws, p_job: job, p_token: a.token });
