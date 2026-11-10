/*
 * Estilos que se podem escolher no editor, na Edição automática e nos pacotes (W10-41): os estilos ATIVOS do catálogo do cliente
 * (VAR-02, a página "Estilos de edição") que o motor já desenha. Antes eram uma lista escrita no código e não batiam com o catálogo.
 * Puro e testado (sem imports de valores, para correr no node); o hook que lê o catálogo está em style-options-client.ts.
 */

export type StyleOption = { id: string; label: string; note?: string };
type CatStyle = { key: string; name: string; status: string };
/** Os estilos que o motor desenha (CAP_STYLES em caption-plan.ts, espelho de STYLES em render_doc.py). */
export type EngineStyles = Record<string, { label: string }>;

/**
 * Opções a mostrar. catalog null = não deu para ler o catálogo: mostra os estilos do motor e diz porquê.
 * O estilo atual aparece sempre (marcado) para nunca mudar sozinho um vídeo que já o usa.
 */
export function styleOptions(engine: EngineStyles, catalog: CatStyle[] | null, current?: string | null): StyleOption[] {
  const can = (k: string) => Object.hasOwn(engine, k);
  const fallback = (k: string) => (can(k) ? engine[k].label : k);
  let out: StyleOption[];
  if (!catalog) out = Object.keys(engine).map((k) => ({ id: k, label: fallback(k), note: "catálogo indisponível" }));
  else out = catalog.filter((s) => s.status === "ativo" && can(s.key))
    .sort((a, b) => a.key.localeCompare(b.key))
    .map((s) => ({ id: s.key, label: `${s.key} · ${s.name}` }));
  if (current && !out.some((o) => o.id === current)) {
    const c = catalog?.find((s) => s.key === current);
    const why = !can(current) ? "sem render" : c ? (c.status === "arquivado" ? "arquivado" : "não ativo") : "fora do catálogo";
    out = [{ id: current, label: c ? `${c.key} · ${c.name}` : fallback(current), note: why }, ...out];
  }
  return out;
}

/** Texto da opção no <select>. */
export const optionText = (o: StyleOption) => (o.note ? `${o.label} (${o.note})` : o.label);
