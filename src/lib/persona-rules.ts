/** Regras puras da lista de frases-persona (espelho de public._persona_problem, para avisar antes de gravar). */
type P = { id: string; text: string; involves?: { name?: string; consent_by?: string; consent_at?: string; consent_note?: string } | null };

export function personaProblem(list: P[]): string | null {
  if (list.length > 100) return "No máximo 100 frases.";
  const seen = new Set<string>(); const ids = new Set<string>();
  for (const [i, p] of list.entries()) {
    const n = i + 1; const t = p.text.trim();
    if (!/^[a-z0-9_-]{1,40}$/.test(p.id)) return `Frase ${n} sem identificador válido.`;
    if (ids.has(p.id)) return `Identificador repetido: ${p.id}.`;
    ids.add(p.id);
    if (t.length < 3 || t.length > 160) return `Frase ${n}: entre 3 e 160 caracteres.`;
    if (seen.has(t.toLowerCase())) return `Frase repetida: ${t}.`;
    seen.add(t.toLowerCase());
    const v = p.involves;
    if (v) {
      if ((v.name ?? "").trim().length < 2) return `Frase ${n}: diz quem é a outra pessoa.`;
      if ((v.consent_by ?? "").trim().length < 2 || !/^\d{4}-\d{2}-\d{2}$/.test(v.consent_at ?? ""))
        return `Frase ${n} envolve ${v.name}: regista o consentimento (quem o deu e em que dia).`;
      if ((v.consent_note ?? "").length > 300) return `Frase ${n}: nota do consentimento demasiado longa.`;
    }
  }
  return null;
}

/** Próximo identificador livre (p01, p02, …). */
export function newPersonaId(list: { id: string }[]): string {
  const used = new Set(list.map((p) => p.id));
  for (let i = 1; ; i++) { const id = `p${String(i).padStart(2, "0")}`; if (!used.has(id)) return id; }
}
