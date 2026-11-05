import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { PendingApproval } from "@/lib/editorial-format";
export { approvable, blockedReason, type PendingApproval, type PendingItem } from "@/lib/editorial-format";

/*
 * Guiões já gravados que ficaram por aprovar, de todos os dias (FR-02-05, FR-17-07; ADR-0051). A aprovação em lote usa
 * content_bulk com recorded_only: o servidor só aprova se o texto for exatamente o que foi gravado (AGENTS §2.6).
 */

export async function fetchPendingApproval(access: Access): Promise<PendingApproval> {
  const { data, error } = await supabase().rpc("content_pending_approval", { p_ws: access.ws, p_token: access.token });
  if (error) throw new Error(error.details || friendlyError(error.message));
  return data as PendingApproval;
}
