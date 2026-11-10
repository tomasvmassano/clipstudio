import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { AiAlternatives, AltSection, EditDoc, PoolSeg, Seg, TextLook } from "@/lib/edit-doc";

/** Editor de vídeo (EDL-07/09, ADR-0046): leitura e gravação de versões do documento de edição. O servidor decide tudo. */
export type EditVersionMeta = { id: string; version_no: number; base_version_id: string | null; source: "import" | "ai" | "user" | "agent"; note: string | null; created_label: string | null; created_at: string };
export type EditState = {
  asset: { id: string; title: string; content_id: string | null; tags: string[]; variant: string; style: string | null; drive_file_id: string | null; media_version_no: number | null };
  guiao: { id: string; n: number; date: string; tema: string | null; hooks?: string[] } | null;
  document: { id: string; current_version_id: string; updated_at: string } | null;
  version: (EditVersionMeta & { doc: EditDoc }) | null;
  versions: EditVersionMeta[];
  /** A última versão escrita pela IA (import/ai): a "escolha da IA" no modo guiado (EDL-10). */
  ai_choice?: { version_no: number; hook: string | null; music: EditDoc["audio"]["music"]; segments: Seg[] } | null;
  /** Cortes de versões anteriores que não estão nesta (para repor no modo guiado). */
  cut_pool?: PoolSeg[];
  /** Alternativas da IA guardadas pelo pacote (doc.ai.alternatives da última versão ai/import; EDL-10). null = não há. */
  ai_alternatives?: AiAlternatives | null;
  can: { timeline: boolean; guided: boolean; export: boolean; styles?: boolean };
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

/* Estilos guardados no editor (EDL-13, ADR-0048): aspeto das legendas e do hook, música e layout, por cliente e versionados. */
export type SavedLook = { captions?: TextLook | null; hook?: TextLook | null; music: EditDoc["audio"]["music"]; layout: string | null };
export type SavedStyle = { key: string; status: "rascunho" | "ativo" | "arquivado"; version: number; name: string; look: SavedLook; updated_at: string; updated_label: string | null };
export type SavedStyles = { can_manage: boolean; styles: SavedStyle[] };

async function rpcD<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(error.details || friendlyError(error.message));   // as validações explicam em "detail"
  return data as T;
}
export const fetchSavedStyles = (a: Access) => rpcD<SavedStyles>("edit_saved_styles", { p_ws: a.ws, p_token: a.token });
/** Grava o aspeto da versão gravada `version` do vídeo como estilo: novo (key null, com nome) ou versão nova de um existente. */
export const saveStyleFromDoc = (a: Access, asset: string, version: string, key: string | null, name: string | null, expected: number | null) =>
  rpcD<SavedStyles>("edit_style_from_doc", { p_ws: a.ws, p_asset: asset, p_version: version, p_key: key, p_name: name, p_expected: expected, p_token: a.token });
/** Aplica um estilo guardado ao vídeo: versão nova do documento a partir da atual. */
export const applyStyle = (a: Access, asset: string, base: string, key: string) =>
  rpcD<EditState>("edit_style_apply", { p_ws: a.ws, p_asset: asset, p_base_version: base, p_key: key, p_token: a.token });

/** Erro de uma RPC do editor com o SQLSTATE (40001 = conflito de versão, 42501 = sem permissão), para a UI escolher a recuperação. */
export class EditRpcError extends Error {
  constructor(message: string, readonly code: string | null) { super(message); this.name = "EditRpcError"; }
}
/** Usa uma alternativa da IA (EDL-10): o servidor monta a versão nova a partir das alternativas guardadas neste documento. */
export async function applyAlternative(a: Access, asset: string, base: string, section: AltSection, option: string): Promise<EditState> {
  const { data, error } = await supabase().rpc("edit_alternative_apply",
    { p_ws: a.ws, p_asset: asset, p_base_version: base, p_section: section, p_option_id: option, p_token: a.token });
  if (error) throw new EditRpcError(error.details || friendlyError(error.message), error.code ?? null);
  return data as EditState;
}

export const SOURCE_LABEL: Record<EditVersionMeta["source"], string> = { import: "primeira versão (IA)", ai: "IA", user: "editada", agent: "proposta do agente" };

/* Vídeos por guião e corpo partilhado (EDL-14, EDL-15; CHG-011, ADR-0081). */
export type BoardVariant = {
  asset_id: string; title: string; status: string; variant: string; style: string | null; version_id: string; version_no: number;
  updated_at: string; updated_label: string | null; hook_text: string | null; /** As primeiras palavras ditas nos cortes de hook (W10-34). */ hook_spoken?: string | null; duration: number; body_sig: string; first_in: number | null;
  source: { cams: Record<string, string> | null; windows: [number, number][] | null; offsets: Record<string, number> | null; audio: string | null };
  export: { status: string; finished_at: string | null; edit_version_id: string | null; current: boolean } | null;
};
export type BoardGuiao = { content_id: string; guiao: { id: string; n: number; date: string; tema: string | null } | null; variants: BoardVariant[] };
/** Vídeos com documento de edição agrupados por guião (os mais recentes primeiro); content limita a um guião. */
export const fetchBoard = (a: Access, content?: string | null, limit = 40) =>
  rpcD<BoardGuiao[]>("edit_board", { p_ws: a.ws, p_content: content ?? null, p_limit: limit, p_token: a.token });

/** Rótulo curto de uma variante ("hook_2" → "Hook 2"), como variantLabel na revisão. */
export const variantShort = (v: string) => (v?.startsWith("hook_") ? `Hook ${v.slice(5)}` : "Geral");
