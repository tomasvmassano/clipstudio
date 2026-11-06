// Origem das janelas por guião no pacote automático (ING-03, EDL-01; ADR-0065). O worker grava em result.windows de onde veio
// a janela de cada guião: das marcas do teleprompter (afinadas pela transcrição) ou só da transcrição, e porquê.
// Funções puras para a página Edição automática e para os testes.

export type WindowItem = {
  source: "marks" | "transcript"; reason: string | null; windows: [number, number][];
  passes: number; takes: number; agree: boolean | null; hooks: string[];
};
export type WindowClock = {
  ok: boolean; method?: string | null; reason?: string | null; anchors?: number; support?: number; session?: string | null;
};
export type PackageWindows = { clock: WindowClock; items: Record<string, WindowItem> };

const REASONS: Record<string, string> = {
  pedido_sem_marcas: "o pedido não trouxe marcas do teleprompter",
  sem_sessao: "nenhuma sessão do teleprompter tem estes guiões",
  erro_marcas: "não deu para juntar as marcas",
  sem_marcas: "o teleprompter não registou leituras deste guião",
  relogio_sem_referencia: "não deu para acertar o relógio das marcas com o da câmara",
  marcas_inconsistentes: "as marcas não batem certo com a transcrição",
  fora_do_ficheiro: "as leituras deste guião caem fora desta gravação",
};
const METHODS: Record<string, string> = {
  transcricao: "pela transcrição",
  "transcricao+hora_do_ficheiro": "pela transcrição, confirmado pela hora da câmara",
  "hora_do_ficheiro+1_ancora": "pela hora da câmara e um guião na transcrição",
  "1_ancora": "por um guião na transcrição",
  hora_do_ficheiro: "só pela hora da câmara (sem confirmação na transcrição)",
};

export const windowReason = (code: string | null | undefined) => (code ? REASONS[code] ?? "motivo desconhecido" : null);

/** Lê result.windows de um job; null se não houver ou vier mal formado (job de um worker anterior). */
export function packageWindows(result: unknown): PackageWindows | null {
  const w = (result as { windows?: unknown } | null)?.windows as PackageWindows | undefined;
  if (!w || typeof w !== "object" || !w.clock || typeof w.clock !== "object" || !w.items || typeof w.items !== "object") return null;
  return w;
}

export function clockText(c: WindowClock): string {
  if (c.ok) {
    const how = METHODS[c.method ?? ""] ?? "acertadas";
    const sup = c.anchors ? ` (${c.support ?? 0} de ${c.anchors} ${c.anchors === 1 ? "guião" : "guiões"} a concordar)` : "";
    return `Marcas do teleprompter acertadas com a câmara ${how}${sup}.`;
  }
  return `Marcas do teleprompter não usadas: ${windowReason(c.reason) ?? "motivo desconhecido"}. Janelas só pela transcrição.`;
}

export const clipTime = (s: number) => {
  const t = Math.max(0, Math.round(s));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), x = t % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(x).padStart(2, "0")}` : `${m}:${String(x).padStart(2, "0")}`;
};

/** Uma linha por guião: origem ("marcas do teleprompter" / "transcrição"), pormenores e janelas na gravação. */
export function itemText(it: WindowItem): { source: string; detail: string; windows: string; warn: boolean } {
  const wins = (it.windows ?? []).map(([a, b]) => `${clipTime(a)}-${clipTime(b)}`).join(", ");
  if (it.source === "marks") {
    const parts: string[] = [];
    if (it.passes > 1) parts.push(`${it.passes} passagens`);
    if (it.hooks?.length) parts.push(`hooks ${it.hooks.map((h) => h.replace("hook_", "")).join(", ")}`);
    if (it.takes) parts.push(`${it.takes} ${it.takes === 1 ? "take marcado" : "takes marcados"}`);
    if (it.agree === false) parts.push("a transcrição não confirma");
    return { source: "marcas do teleprompter", detail: parts.join(" · "), windows: wins, warn: it.agree === false };
  }
  return { source: "transcrição", detail: windowReason(it.reason) ?? "", windows: wins || "não encontrado na gravação", warn: !wins };
}

/** Linhas pela ordem dos guiões do pedido; guiões que o worker não reportou ficam de fora. */
export function windowRows(w: PackageWindows, guioes: { id: string; n: number; tema: string | null }[] | null) {
  return (guioes ?? []).filter((g) => w.items[g.id]).map((g) => ({ id: g.id, n: g.n, tema: g.tema, ...itemText(w.items[g.id]) }));
}
