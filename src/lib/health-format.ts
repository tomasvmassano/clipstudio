/*
 * Saúde do sistema (W10-01, FR-17-15): formatação pura, sem rede, para o painel /saude e testes unitários.
 * Nada aqui inventa estado: só traduz o que a base devolve (ops_health).
 */

export type HealthSource = "agent" | "media";

export const SOURCE_LABEL: Record<HealthSource, string> = { agent: "Agentes", media: "Media" };

export const KIND_LABEL: Record<string, string> = {
  daily_pipeline: "Corrida diária", scouts: "Batedores", analysis: "Análise",
  ingest: "Verificar envio", export: "Exportar vídeo", package: "Pacote de edição", clips: "Cortes de vídeos longos",
};
export const kindLabel = (k: string) => KIND_LABEL[k] ?? k;

export const STATUS_LABEL: Record<string, string> = { failed: "Falhou", dead: "Esgotou as tentativas", running: "A correr", queued: "À espera" };

/** Duração legível desde iso até now: "há 5 min", "há 3 h", "há 2 dias"; null = "nunca". */
export function ago(iso: string | null | undefined, now: number = Date.now()): string {
  if (!iso) return "nunca";
  const s = Math.round((now - new Date(iso).getTime()) / 1000);
  if (Number.isNaN(s)) return "nunca";
  if (s < 0) return "agora";
  if (s < 60) return "há menos de 1 min";
  const m = Math.floor(s / 60);
  if (m < 60) return `há ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 48) return `há ${h} h`;
  return `há ${Math.floor(h / 24)} dias`;
}

/** Estado do sinal de um trabalho a correr: lease expirada ganha a tudo; depois o tempo desde o último heartbeat. */
export function heartbeatState(job: { heartbeat_at: string | null; lease_expired: boolean }, now: number = Date.now()): "ok" | "atrasado" | "parado" {
  if (job.lease_expired) return "parado";
  if (!job.heartbeat_at) return "atrasado";
  const s = (now - new Date(job.heartbeat_at).getTime()) / 1000;
  return s > 120 ? "atrasado" : "ok";
}
export const HEARTBEAT_LABEL = { ok: "com sinal", atrasado: "sinal atrasado", parado: "sem sinal (lease expirada)" } as const;

/** Página certa, relativa ao cliente, para abrir um trabalho e recuperá-lo. */
export function jobPath(source: HealthSource, kind: string, assetId: string | null | undefined): string {
  if (source === "agent") return "/agentes/configuracao";
  if (kind === "package") return "/edicao-automatica";
  if (kind === "export" && assetId) return `/editor?asset=${encodeURIComponent(assetId)}`;
  return "/biblioteca";
}

/**
 * Segunda linha de defesa (a base já limpa com _ops_redact): nunca mostrar tokens, chaves, palavras-passe em URLs nem emails.
 * Mesmas regras que o servidor.
 */
export function redactSecrets(text: string | null | undefined): string {
  if (!text) return "";
  return text
    .replace(/(bearer|basic)\s+[A-Za-z0-9._~+/=-]+/gi, "$1 [removido]")
    .replace(/eyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]+/g, "[token removido]")
    .replace(/((api[_-]?key|apikey|access[_-]?key|secret|token|password|passwd|pwd|signature|credential|authorization)["']?\s*[=:]\s*["']?)[^\s&"',;]+/gi, "$1[removido]")
    .replace(/([a-z][a-z0-9+.-]*:\/\/)[^:/@\s]+:[^@\s]+@/gi, "$1[removido]@")
    .replace(/\b(sk|pk|rk)[-_][A-Za-z0-9_-]{12,}/g, "[chave removida]")
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[email removido]");
}

/** Tom geral do painel a partir dos números reais: crítico se há fila sem worker, lease expirada ou dead nas 24 h. */
export function overallTone(q: { uncovered: number; stalled: number }[], dead24h: number): "bad" | "warn" | "good" {
  if (q.some((x) => x.uncovered > 0 || x.stalled > 0)) return "bad";
  if (dead24h > 0) return "warn";
  return "good";
}
