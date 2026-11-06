import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/**
 * Pacote por guião (STU-03, ADR-0070): ligar as gravações curtas de um guião (frente + lado) e pedir o pacote só desse guião,
 * à mão ou automático quando chegam as duas. Tudo por RPC; o servidor decide (flag edit.package_script, edit.timeline,
 * media.upload para ligar, styles.manage para as definições, edit.export para exportar automático).
 */
export * from "@/lib/package-script-format";
import type { Camera, ClipLink, ScriptJob, ScriptRow } from "@/lib/package-script-format";

export type ScriptSettings = {
  auto_package: boolean; auto_export: boolean; style: string; enabled_label: string | null; updated_label: string | null;
  updated_at: string | null; delegate_ok: boolean | null;
};
export type ScriptList = {
  settings: ScriptSettings;
  can: { request: boolean; export: boolean; link: boolean; settings: boolean };
  scripts: ScriptRow[];
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

export const listScriptPackages = (a: Access) => rpc<ScriptList>("edit_package_script_list", { p_ws: a.ws, p_token: a.token });
export const requestScriptPackage = (a: Access, guiao: string, style?: string | null) =>
  rpc<ScriptJob & { guiao_id: string }>("edit_package_script_request", { p_ws: a.ws, p_guiao: guiao, p_style: style ?? null, p_token: a.token });
export const saveScriptSettings = (a: Access, s: { auto_package: boolean; auto_export: boolean; style: string }) =>
  rpc<ScriptSettings>("package_script_settings_set", { p_ws: a.ws, p_auto_package: s.auto_package, p_auto_export: s.auto_export, p_style: s.style, p_token: a.token });
export const linkClip = (a: Access, asset: string, guiao: string, camera: Camera, source: "upload" | "biblioteca" = "biblioteca") =>
  rpc<ClipLink>("media_clip_link", { p_ws: a.ws, p_asset: asset, p_guiao: guiao, p_camera: camera, p_session: null, p_source: source, p_token: a.token });
export const unlinkClip = (a: Access, asset: string) => rpc<{ unlinked: boolean }>("media_clip_unlink", { p_ws: a.ws, p_asset: asset, p_token: a.token });
export const getClip = (a: Access, asset: string) => rpc<ClipLink | null>("media_clip_get", { p_ws: a.ws, p_asset: asset, p_token: a.token });

