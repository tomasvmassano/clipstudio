/** Verificador antes da revisão humana (VAR-04): tipos e regras puras de apresentação. O motor classifica; quem revê decide. */

export type VerifierFlag = "ok" | "atencao" | "rever" | "juridico" | "bloqueado";
export type ClaimKind = "persona" | "opiniao" | "facto" | "terceiro" | "validade";

export type VerifierClaim = {
  tipo: ClaimKind; trecho: string; marca: VerifierFlag; motivo?: string;
  fonte?: string; fonte_data?: string; expira?: string; pessoa?: string; autor?: string; frase_aprovada?: string;
};
export type VerifierHook = {
  i: number; texto: string; marca: VerifierFlag; afirmacoes: VerifierClaim[];
  lingua?: { lingua: string; ok: boolean; problemas: string[] };
};
export type VerifierResult = {
  versao: string; modelo?: string; prompts_version?: string; persona_version?: number | null; lista_persona?: boolean;
  llm?: "ok" | "mock" | "falhou"; llm_erro?: string | null; erro?: string; marca: VerifierFlag; hooks: VerifierHook[];
  lingua_texto?: { ok: boolean; problemas: string[] };
};
export type Verification = {
  id: string; marca: VerifierFlag; version_id: string | null; verifier_version: string; model: string | null;
  prompts_version: string | null; persona_version: number | null; created_at: string; result: VerifierResult;
};

export const FLAG_ORDER: VerifierFlag[] = ["ok", "atencao", "rever", "juridico", "bloqueado"];
export const FLAG_LABEL: Record<VerifierFlag, string> = {
  ok: "ok", atencao: "atenção", rever: "rever", juridico: "revisão jurídica", bloqueado: "fora da regra",
};
export const KIND_LABEL: Record<ClaimKind, string> = {
  persona: "Persona", opiniao: "Opinião", facto: "Facto", terceiro: "Terceiro identificado", validade: "Com validade",
};

const isFlag = (v: unknown): v is VerifierFlag => typeof v === "string" && (FLAG_ORDER as string[]).includes(v);
export const worst = (flags: VerifierFlag[]): VerifierFlag =>
  flags.reduce<VerifierFlag>((a, b) => (FLAG_ORDER.indexOf(b) > FLAG_ORDER.indexOf(a) ? b : a), "ok");

const norm = (t: string) => t.normalize("NFKD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, " ").trim();

/** Resultado do verificador para o texto atual de um hook. `stale` quando o hook mudou depois da verificação. */
export function checkForHook(r: VerifierResult | null | undefined, text: string): { hook: VerifierHook | null; stale: boolean } {
  if (!r || !Array.isArray(r.hooks)) return { hook: null, stale: false };
  const h = r.hooks.find((x) => norm(x.texto ?? "") === norm(text));
  return h ? { hook: h, stale: false } : { hook: null, stale: r.hooks.length > 0 };
}

/** Linha de resumo: quantos hooks por marca grave. Nunca diz "verificado". */
export function summary(r: VerifierResult | null | undefined): string {
  if (!r) return "Sem verificação.";
  if (r.erro) return "A verificação falhou neste guião: rever à mão.";
  const n = (f: VerifierFlag) => r.hooks.filter((h) => h.marca === f).length;
  const parts = ([["bloqueado", "fora da regra"], ["juridico", "com revisão jurídica"], ["rever", "para rever"], ["atencao", "com atenção"]] as const)
    .map(([f, l]) => (n(f) ? `${n(f)} ${l}` : "")).filter(Boolean);
  const head = parts.length ? `Hooks: ${parts.join(", ")}.` : "Nenhum hook marcado.";
  const partial = r.llm === "falhou" ? " Só regras (o modelo falhou)." : "";
  return `${head}${partial} Quem revê decide; nenhum facto fica dado como verificado.`;
}

/** Valida a forma vinda do servidor; o que não reconhecer fica de fora em vez de partir o ecrã. */
export function parseVerification(v: unknown): Verification | null {
  if (!v || typeof v !== "object") return null;
  const o = v as Verification;
  if (!isFlag(o.marca) || !o.result || typeof o.result !== "object") return null;
  const hooks = (Array.isArray(o.result.hooks) ? o.result.hooks : []).filter((h) => h && isFlag(h.marca)).map((h) => ({
    ...h, afirmacoes: (Array.isArray(h.afirmacoes) ? h.afirmacoes : []).filter((a) => a && isFlag(a.marca) && a.tipo in KIND_LABEL),
  }));
  return { ...o, result: { ...o.result, hooks } };
}
