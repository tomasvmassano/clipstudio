import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { EditDoc } from "@/lib/edit-doc";

/** Editor de vídeo (EDL-07/09, ADR-0046): leitura e gravação de versões do documento de edição. O servidor decide tudo. */
export type EditVersionMeta = { id: string; version_no: number; base_version_id: string | null; source: "import" | "ai" | "user" | "agent"; note: string | null; created_label: string | null; created_at: string };
export type EditState = {
  asset: { id: string; title: string; content_id: string | null; tags: string[]; variant: string; style: string | null; drive_file_id: string | null; media_version_no: number | null };
  guiao: { id: string; n: number; date: string; tema: string | null } | null;
  document: { id: string; current_version_id: string; updated_at: string } | null;
  version: (EditVersionMeta & { doc: EditDoc }) | null;
  versions: EditVersionMeta[];
  can: { timeline: boolean; guided: boolean; export: boolean };
};

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchEdit = (access: Access, asset: string, version?: string | null) =>
  rpc<EditState>("edit_doc_get", { p_ws: access.ws, p_asset: asset, p_version: version ?? null, p_token: access.token });
export const saveEdit = (access: Access, asset: string, base: string | null, doc: EditDoc, note?: string) =>
  rpc<EditState>("edit_doc_save", { p_ws: access.ws, p_asset: asset, p_base_version: base, p_doc: doc, p_note: note ?? null, p_source: "user", p_token: access.token });

export const SOURCE_LABEL: Record<EditVersionMeta["source"], string> = { import: "primeira versão (IA)", ai: "IA", user: "editada", agent: "proposta do agente" };
