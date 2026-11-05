import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

/*
 * Eliminar guiões arquivados (FR-02-01, R-09, ADR-0047). Só com sessão individual e scripts.purge; o servidor volta a verificar
 * tudo (arquivado, confirmação = ID do guião, sem tarefas abertas, publicações nem ativos). Recuperável durante 30 dias.
 */

export type DeletedScript = {
  id: string; n: number; date: string; tema: string | null; hook: string | null;
  deleted_at: string; deleted_by: string | null; reason: string | null; recoverable_until: string;
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    // as recusas deste fluxo trazem a causa em PT no detalhe (ex.: "Não se pode eliminar: 2 tarefa(s) aberta(s)…")
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const deleteContent = (access: Access, id: string, confirm: string, reason: string, lock?: number) =>
  rpc<{ id: string; deleted_at: string; recoverable_until: string }>("content_delete",
    { p_id: id, p_confirm: confirm, p_reason: reason.trim() || null, p_lock: lock ?? null, p_token: access.token });

export const fetchDeleted = (access: Access) => rpc<DeletedScript[]>("content_deleted_list", { p_ws: access.ws, p_token: access.token });

export const undeleteContent = (access: Access, id: string) => rpc<Guiao>("content_undelete", { p_id: id, p_token: access.token });

export { CONFIRM_WORD, confirmOk } from "@/lib/editorial-format";
