import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

/* Catálogo de estilos (VAR-02) e preset de edição do cliente (EDL-01). W5-02, ADR-0027. */

export type LayerKind = "video" | "image" | "attention_video" | "title" | "captions" | "band";
export type Layer = {
  kind: LayerKind; box: [number, number, number, number]; role?: string; color?: string; stroke?: string; weight?: string; max_words?: number; brush?: boolean; text?: string;
  // tipografia e aspeto usados pelo motor de render e pela pré-visualização (opcionais; o servidor ignora o que não valida)
  font?: string; size?: number; align?: "left" | "center"; lines?: number; highlight?: string; background?: string; radius?: number; shadow?: string;
};
export type StyleSpec = { canvas: { w: number; h: number }; layers: Layer[] };
export type StyleStatus = "rascunho" | "ativo" | "arquivado";
export type Platform = "instagram" | "tiktok" | "youtube";
export type Transformation = "baixa" | "media" | "alta";
export type EditStyle = {
  key: string; status: StyleStatus; version: number; name: string; spec: StyleSpec; transformation: Transformation | null;
  platforms: Platform[]; notes: string | null; updated_at: string; updated_label: string | null; problems: string[];
  /** De onde veio (W10-42): chave e versão do estilo da agência; null = criado neste cliente. */
  origin?: { key: string; version: number } | null;
};
export type OutputKind = "master" | "split_image_persona" | "split_attention" | "style";
export type PresetOutput = { kind: OutputKind; captions: "burned" | "none"; per_hook?: boolean; style?: string; style_version?: number };
export type EditPreset = { version: number; outputs: PresetOutput[]; created_at: string; created_label: string | null; stale: boolean };
export type EditCatalog = { can_manage: boolean; styles: EditStyle[]; preset: EditPreset | null };
export type StyleVersion = { version: number; name: string; spec: StyleSpec; transformation: Transformation | null; platforms: Platform[]; notes: string | null; created_at: string; created_label: string | null };

async function rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) {
    // as validações do servidor explicam o problema em "detail" (ex.: texto fora do retângulo seguro)
    const e = new Error(error.details || friendlyError(error.message)) as Error & { code?: string };
    e.code = error.code;
    throw e;
  }
  return data as T;
}

export const fetchCatalog = (a: Access) => rpc<EditCatalog>("edit_catalog", { p_ws: a.ws, p_token: a.token });
export const initCatalog = (a: Access) => rpc<EditCatalog>("edit_catalog_init", { p_ws: a.ws, p_token: a.token });
export const saveStyle = (a: Access, key: string, style: Partial<Pick<EditStyle, "name" | "spec" | "transformation" | "platforms" | "notes">>, expected: number) =>
  rpc<EditCatalog>("edit_style_save", { p_ws: a.ws, p_key: key, p_style: style, p_expected: expected, p_token: a.token });
export const setStyleStatus = (a: Access, key: string, status: StyleStatus) =>
  rpc<EditCatalog>("edit_style_set_status", { p_ws: a.ws, p_key: key, p_status: status, p_token: a.token });
export const styleHistory = (a: Access, key: string) => rpc<StyleVersion[]>("edit_style_history", { p_ws: a.ws, p_key: key, p_token: a.token });
export const savePreset = (a: Access, outputs: PresetOutput[], expected: number) =>
  rpc<EditCatalog>("edit_preset_save", { p_ws: a.ws, p_outputs: outputs.map((o) => ({ kind: o.kind, captions: o.captions, per_hook: o.per_hook, style: o.style })), p_expected: expected, p_token: a.token });

export const OUTPUT_LABEL: Record<Exclude<OutputKind, "style">, string> = {
  master: "Masters (um por hook, corpo montado uma vez)",
  split_image_persona: "Split screen: imagem + frase-persona",
  split_attention: "Split screen: vídeo de atenção + frase diferente",
};
export const STATUS_LABEL: Record<StyleStatus, string> = { rascunho: "Rascunho", ativo: "Ativo", arquivado: "Arquivado" };
export const TRANSFORMATION_LABEL: Record<Transformation, string> = { baixa: "Baixa", media: "Média", alta: "Alta" };
export const PLATFORM_LABEL: Record<Platform, string> = { instagram: "Instagram", tiktok: "TikTok", youtube: "YouTube" };
export const LAYER_LABEL: Record<LayerKind, string> = {
  video: "Vídeo", image: "Imagem", attention_video: "Vídeo de atenção", title: "Título", captions: "Legendas", band: "Faixa",
};

/** Retângulo seguro comum em 1080×1920 (EDL-03): o texto fica aqui dentro em todas as plataformas. */
export const SAFE = { x0: 60, x1: 960, y0: 210, y1: 1600 } as const;

/** Mesma regra do servidor, para avisar enquanto se escreve (o servidor continua a decidir). */
export function specProblems(spec: unknown, requireLayers: boolean): string[] {
  const p: string[] = [];
  if (!spec || typeof spec !== "object") return ["A especificação tem de ser um objeto."];
  const s = spec as Partial<StyleSpec>;
  if (s.canvas?.w !== 1080 || s.canvas?.h !== 1920) p.push("O formato tem de ser 1080×1920.");
  if (!Array.isArray(s.layers)) return [...p, "Falta a lista de camadas."];
  if (s.layers.length > 20) p.push("No máximo 20 camadas.");
  if (requireLayers && s.layers.length === 0) p.push("Um estilo ativo precisa de pelo menos uma camada.");
  s.layers.forEach((l, idx) => {
    const i = idx + 1;
    if (!l || !(l.kind in LAYER_LABEL)) { p.push(`Camada ${i}: tipo desconhecido.`); return; }
    const b = l.box;
    if (!Array.isArray(b) || b.length !== 4 || b.some((v) => typeof v !== "number")) { p.push(`Camada ${i}: a caixa tem de ser [x, y, largura, altura].`); return; }
    const [x, y, w, h] = b;
    if (w <= 0 || h <= 0 || x < 0 || y < 0 || x + w > 1080 || y + h > 1920) p.push(`Camada ${i}: sai do ecrã 1080×1920.`);
    if ((l.kind === "title" || l.kind === "captions" || (l.kind === "band" && "text" in l)) && (x < SAFE.x0 || x + w > SAFE.x1 || y < SAFE.y0 || y + h > SAFE.y1))
      p.push(`Camada ${i} (${l.kind}): o texto tem de ficar no retângulo seguro (x 60-960, y 210-1600).`);
    for (const c of [l.color, l.stroke]) if (c !== undefined && !/^#[0-9A-Fa-f]{6}$/.test(c)) p.push(`Camada ${i}: cor inválida (${c}).`);
    if (l.max_words !== undefined && (typeof l.max_words !== "number" || l.max_words < 1 || l.max_words > 30)) p.push(`Camada ${i}: máximo de palavras entre 1 e 30.`);
  });
  return p;
}

/* Biblioteca de estilos da agência (REF-07) e importar para um cliente (REF-08). W10-42, ADR-0084. Só staff da agência. */
export type StyleImport = { ws: string; name: string; key: string; version: number; status: StyleStatus };
export type AgencyStyle = Omit<EditStyle, "origin"> & { look: unknown; source_url: string | null; imports: StyleImport[] };
export type AgencyLibrary = { can_import: boolean; styles: AgencyStyle[]; clients: { ws: string; name: string }[] };
export type AgencyStyleInput = Partial<Pick<AgencyStyle, "name" | "spec" | "transformation" | "platforms" | "notes" | "source_url">>;
export const fetchAgencyLibrary = () => rpc<AgencyLibrary>("agency_style_library", {});
export const saveAgencyStyle = (key: string, style: AgencyStyleInput, expected: number) =>
  rpc<AgencyLibrary>("agency_style_save", { p_key: key, p_style: style, p_expected: expected });
export const setAgencyStyleStatus = (key: string, status: StyleStatus) => rpc<AgencyLibrary>("agency_style_set_status", { p_key: key, p_status: status });
export const agencyStyleHistory = (key: string) => rpc<(StyleVersion & { source_url: string | null })[]>("agency_style_history", { p_key: key });
export const importAgencyStyle = (key: string, ws: string, as?: string) =>
  rpc<AgencyLibrary>("agency_style_import", { p_key: key, p_ws: ws, p_as: as ?? null });

/** Próxima chave livre na biblioteca (S18, S19…) para um estilo novo. */
export function nextStyleKey(keys: string[]): string {
  const n = keys.map((k) => /^S(\d+)$/.exec(k)?.[1]).filter(Boolean).map(Number);
  return `S${String((n.length ? Math.max(...n) : 0) + 1).padStart(2, "0")}`;
}
