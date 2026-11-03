import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

/**
 * Navegar como papel ou pessoa (BIZ-07, CAP-05, ADR-0045). O servidor decide: durante a pré-visualização só lê o
 * que o alvo lê e recusa qualquer escrita. A app usa `capabilities` só para mostrar menus e botões como o alvo os vê.
 */
export { isActive, untilLabel } from "@/lib/preview-format";
export type { Preview } from "@/lib/preview-format";
import type { Preview } from "@/lib/preview-format";

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const startPreview = (ws: string, target: { user?: string; role?: string }) =>
  rpc<Preview>("access_preview_start", { p_ws: ws, p_user: target.user ?? null, p_role: target.role ?? null });
export const stopPreview = (ws: string) => rpc<null>("access_preview_stop", { p_ws: ws });
export const myPreviews = () => rpc<Preview[]>("access_preview_mine", {});

