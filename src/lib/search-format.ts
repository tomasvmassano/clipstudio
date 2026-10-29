/* Pesquisa global e exportação em lote (ADR-0035): tipos, destinos e CSV sem dependências, para testar em node. */

export type SearchKind = "script" | "source" | "reference" | "task" | "project" | "person" | "style" | "tag";
export type SearchItem = {
  kind: SearchKind; id: string; ws?: string; ws_name?: string; title: string; status?: string; date?: string; n?: number;
  tags?: string[]; source_kind?: string; creator?: string | null; due_at?: string | null; project_kind?: string; email?: string;
  role?: string; job_title?: string | null; affiliation?: string; version?: number; count?: number;
};

/** Para onde leva cada resultado (página do cliente certo, com o objeto aberto quando a página o suporta). */
export function searchHref(it: SearchItem): string | null {
  if (!it.ws) return null;
  const p = (sub: string) => `/c/${encodeURIComponent(it.ws!)}${sub}`;
  const q = (s: string) => encodeURIComponent(s);
  switch (it.kind) {
    case "script": return p(`/guioes?date=${it.date ?? ""}&open=${q(it.id)}`);
    case "source": return p(`/fontes?q=${q(it.title)}`);
    case "reference": return p(`/referencias?q=${q(it.title)}`);
    case "task": return p(`/tarefas?task=${q(it.id)}`);
    case "project": return p(`/guioes?campanha=${q(it.id)}`);
    case "person": return p("/equipa");
    case "style": return p("/edicao");
    default: return null;
  }
}

export type ExportRow = {
  id: string; date: string; n: number; tema: string | null; formato: string | null; editorial_status: string; production_status: string;
  campanha: string | null; responsavel: string | null; tags: string[]; platforms: string[]; hooks: string[]; corpo: string; cta: string | null;
};

/** CSV (RFC 4180, separador ";" para abrir bem no Excel PT) com BOM UTF-8. */
export function toCsv(rows: ExportRow[]): string {
  const head = ["id", "data", "n", "tema", "formato", "estado editorial", "estado de produção", "campanha", "responsável", "etiquetas", "plataformas", "hook 1", "hook 2", "hook 3", "corpo", "cta"];
  const cell = (v: unknown) => {
    const s = v == null ? "" : String(v);
    // evita que uma célula comece por = + - @ e seja lida como fórmula
    const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s;
    return /[";\n\r]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
  };
  const lines = rows.map((r) => [r.id, r.date, r.n, r.tema, r.formato, r.editorial_status, r.production_status, r.campanha, r.responsavel,
    r.tags.join(", "), r.platforms.join(", "), r.hooks[0], r.hooks[1], r.hooks[2], r.corpo, r.cta].map(cell).join(";"));
  return "\uFEFF" + [head.join(";"), ...lines].join("\r\n") + "\r\n";
}
