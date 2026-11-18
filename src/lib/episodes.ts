import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { EpisodeFile, EpisodeSummary } from "@/lib/episodes-format";

/**
 * Edição do episódio completo (POD-01..06, CHG-013, ADR-0087): pedir, ver o job real e descarregar o resultado.
 * Tudo por RPC; o servidor decide (edit.episode, media.download, flags edit.episode, edit.studio e media.r2).
 */
export type EpisodeJob = {
  id: string; status: "queued" | "running" | "done" | "failed" | "dead" | "cancelled";
  progress: { pct?: number; step?: string } | null; last_error: string | null; created_label: string | null; created_at: string;
  finished_at: string | null; title: string | null; cams: Record<string, string> | null; audio: string | null; wide: string | null;
  profile: boolean; summary: EpisodeSummary | null; titles: string[] | null; flags: string[] | null; language: string | null;
  files: EpisodeFile[]; master_asset_id: string | null;
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

export const requestEpisode = (a: Access, cams: Record<string, string>, audio: string | null, wide: string | null,
                               profile: Record<string, unknown> | null, language: "pt" | "en" | null) =>
  rpc<{ id: string; status: string }>("episode_request", { p_ws: a.ws, p_cams: cams, p_audio: audio || null, p_wide: wide || null,
    p_profile: profile, p_language: language, p_token: a.token });

export const listEpisodes = (a: Access) => rpc<EpisodeJob[]>("episode_list", { p_ws: a.ws, p_token: a.token });

/** Link curto (2 min) para descarregar um ficheiro do episódio; o servidor audita e verifica media.download. */
export async function episodeFileUrl(a: Access, job: string, name: EpisodeFile): Promise<string> {
  const r = await fetch(`/api/episodes/${job}/files/${encodeURIComponent(name)}?ws=${encodeURIComponent(a.ws)}`, { cache: "no-store" });
  const j = (await r.json().catch(() => ({}))) as { url?: string; error?: { message?: string; details?: string } };
  if (!r.ok || !j.url) throw new Error(j.error?.details || j.error?.message || "Não consegui criar o link. Tenta de novo.");
  return j.url;
}
