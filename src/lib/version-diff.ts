// Diff por palavra entre versões de um guião (FR-02-06, FR-05-06). Puro: sem React, sem rede.
// Tokens: palavras (letras com acentos, números, apóstrofos e hífenes internos), pontuação um a um e espaços.

export type DiffOp = { op: "eq" | "add" | "del"; text: string };

const TOKEN = /[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*|\s+|[^\s\p{L}\p{N}]/gu;

/** Parte o texto em tokens; juntar todos devolve o texto original. */
export function tokenize(text: string): string[] {
  return text ? text.match(TOKEN) ?? [] : [];
}

/** Acima disto (células da tabela LCS) o diff mostra o troço do meio como substituído inteiro. */
export const MAX_CELLS = 4_000_000;

function push(out: DiffOp[], op: DiffOp["op"], text: string) {
  if (!text) return;
  const last = out[out.length - 1];
  if (last && last.op === op) last.text += text;
  else out.push({ op, text });
}

/** Diff por tokens (LCS), com prefixo e sufixo comuns cortados primeiro. Ops adjacentes iguais são juntas. */
export function diffWords(before: string, after: string): DiffOp[] {
  const a = tokenize(before ?? "");
  const b = tokenize(after ?? "");
  let start = 0;
  while (start < a.length && start < b.length && a[start] === b[start]) start++;
  let endA = a.length, endB = b.length;
  while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) { endA--; endB--; }

  const out: DiffOp[] = [];
  push(out, "eq", a.slice(0, start).join(""));
  const ma = a.slice(start, endA), mb = b.slice(start, endB);
  const n = ma.length, m = mb.length;
  if (n === 0 || m === 0 || (n + 1) * (m + 1) > MAX_CELLS) {
    push(out, "del", ma.join(""));
    push(out, "add", mb.join(""));
  } else {
    // dp[i][j] = LCS de ma[i..] e mb[j..]
    const w = m + 1;
    const dp = new Uint32Array((n + 1) * w);
    for (let i = n - 1; i >= 0; i--)
      for (let j = m - 1; j >= 0; j--)
        dp[i * w + j] = ma[i] === mb[j] ? dp[(i + 1) * w + j + 1] + 1 : Math.max(dp[(i + 1) * w + j], dp[i * w + j + 1]);
    let i = 0, j = 0;
    while (i < n && j < m) {
      if (ma[i] === mb[j]) { push(out, "eq", ma[i]); i++; j++; }
      else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) { push(out, "del", ma[i]); i++; }
      else { push(out, "add", mb[j]); j++; }
    }
    while (i < n) push(out, "del", ma[i++]);
    while (j < m) push(out, "add", mb[j++]);
  }
  push(out, "eq", a.slice(endA).join(""));
  return tidy(out);
}

/** Arruma o resultado: um espaço sozinho entre duas mudanças entra nelas, e cada troço de mudanças fica
 *  "removido" seguido de "acrescentado" ("−a b− +c d+" em vez de "−a− +c+ ␣ −b− +d+"). O texto de cada lado não muda. */
function tidy(ops: DiffOp[]): DiffOp[] {
  const mid: DiffOp[] = [];
  ops.forEach((o, k) => {
    if (o.op === "eq" && /^\s+$/.test(o.text) && ops[k - 1] && ops[k - 1].op !== "eq" && ops[k + 1] && ops[k + 1].op !== "eq") {
      mid.push({ op: "del", text: o.text }, { op: "add", text: o.text });
    } else mid.push(o);
  });
  const out: DiffOp[] = [];
  let del = "", add = "";
  const flush = () => { push(out, "del", del); push(out, "add", add); del = ""; add = ""; };
  for (const o of mid) {
    if (o.op === "eq") { flush(); push(out, "eq", o.text); }
    else if (o.op === "del") del += o.text;
    else add += o.text;
  }
  flush();
  return out;
}

export const changed = (ops: DiffOp[]) => ops.some((o) => o.op !== "eq");

/** O que se compara de cada versão. */
export type VersionText = { hooks: { text: string }[]; corpo: string; cta: string | null; formato: string | null; tema: string | null };

export type FieldDiff = { key: string; label: string; ops: DiffOp[]; changed: boolean; status: "same" | "changed" | "added" | "removed" };

const field = (key: string, label: string, a: string | null | undefined, b: string | null | undefined): FieldDiff => {
  const x = a ?? "", y = b ?? "";
  const ops = diffWords(x, y);
  const status = x === y ? "same" : !x ? "added" : !y ? "removed" : "changed";
  return { key, label, ops, changed: status !== "same", status };
};

/** Diff campo a campo: hooks por posição (Hook 1 com Hook 1), corpo, CTA, formato e tema. */
export function diffVersions(a: VersionText, b: VersionText, labels?: { formato?: (v: string | null) => string }): FieldDiff[] {
  const fmt = labels?.formato ?? ((v: string | null) => v ?? "");
  const n = Math.max(a.hooks.length, b.hooks.length);
  const hooks = Array.from({ length: n }, (_, i) => field(`hook${i + 1}`, `Hook ${i + 1}`, a.hooks[i]?.text, b.hooks[i]?.text));
  return [
    ...hooks,
    field("corpo", "Corpo", a.corpo, b.corpo),
    field("cta", "CTA", a.cta, b.cta),
    field("formato", "Formato", a.formato ? fmt(a.formato) : "", b.formato ? fmt(b.formato) : ""),
    field("tema", "Tema", a.tema, b.tema),
  ];
}

/** Contagem de palavras acrescentadas e removidas (para o resumo e para leitores de ecrã). */
export function diffStats(fields: FieldDiff[]): { added: number; removed: number; fields: number } {
  let added = 0, removed = 0;
  for (const f of fields) for (const o of f.ops) {
    const words = tokenize(o.text).filter((t) => /[\p{L}\p{N}]/u.test(t)).length;
    if (o.op === "add") added += words; else if (o.op === "del") removed += words;
  }
  return { added, removed, fields: fields.filter((f) => f.changed).length };
}

/** Versão que estava em vigor na última marcação de gravado (a mesma regra de _content_recorded_version, W9-02).
 *  Usado só quando o servidor ainda não devolve recorded_version_id. Transições vêm da mais recente para a mais antiga. */
export function recordedVersionNo(transitions: { kind: string; from: string | null; to: string; version_no: number | null }[]): number | null {
  const t = transitions.find((x) => x.kind === "production" && x.to === "recorded" && x.from !== "editing");
  return t?.version_no ?? null;
}
