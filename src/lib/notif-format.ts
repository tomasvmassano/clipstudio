/*
 * Notificações por evento (FR-15-05, FR-14-02, ADR-0040): funções puras de apresentação. Sem rede, testadas em
 * tests/notif-format.test.mts. Quem decide o que é permitido é o servidor; isto só explica ao utilizador porquê.
 */

export type NotifChannelKey = "in_app" | "email" | "digest";
export type NotifChannel = { key: NotifChannelKey; label: string; available: boolean; unavailable_reason: string | null };
export type NotifGroup = "tarefas" | "guioes" | "automacao";
export type SuppressReason = "org_off" | "user_off" | "muted";
export type Suppressed = { kind: string; reason: SuppressReason; n: number };

export const GROUP_LABEL: Record<NotifGroup, string> = { tarefas: "Tarefas", guioes: "Guiões", automacao: "Automação" };
export const GROUP_ORDER: NotifGroup[] = ["tarefas", "guioes", "automacao"];
export const REASON_LABEL: Record<SuppressReason, string> = {
  org_off: "desligadas pelo cliente", user_off: "desligadas pela pessoa", muted: "com o cliente silenciado",
};

export function groupBy<T extends { group: NotifGroup }>(events: T[]): { group: NotifGroup; label: string; events: T[] }[] {
  return GROUP_ORDER.map((g) => ({ group: g, label: GROUP_LABEL[g], events: events.filter((e) => e.group === g) })).filter((x) => x.events.length > 0);
}

/** Resumo das notificações não criadas nos últimos 30 dias, por tipo. "" quando não houve nenhuma. */
export function suppressedLine(rows: Suppressed[] | null | undefined, kind: string): string {
  const mine = (rows ?? []).filter((r) => r.kind === kind && r.n > 0);
  if (mine.length === 0) return "";
  const total = mine.reduce((s, r) => s + r.n, 0);
  const parts = mine.map((r) => `${r.n} ${REASON_LABEL[r.reason] ?? r.reason}`);
  return `${total} não ${total === 1 ? "criada" : "criadas"} nos últimos 30 dias (${parts.join(", ")})`;
}

/** Porque é que um interruptor pessoal não se pode mudar. null = pode. */
export function personalLock(ch: { allowed: boolean; locked: boolean }, mandatoryReason: string | null): string | null {
  if (ch.locked) return mandatoryReason ?? "Este cliente tornou esta notificação obrigatória.";
  if (!ch.allowed) return "Desligada neste cliente por quem gere as definições.";
  return null;
}

export type MuteOption = { key: string; label: string; hours: number | null };
export const MUTE_OPTIONS: MuteOption[] = [
  { key: "1h", label: "1 hora", hours: 1 },
  { key: "8h", label: "8 horas", hours: 8 },
  { key: "1d", label: "1 dia", hours: 24 },
  { key: "7d", label: "1 semana", hours: 24 * 7 },
  { key: "forever", label: "Até eu voltar a ligar", hours: null },
];

/** Fim do silêncio em UTC (ISO) para uma opção; null = sem fim. */
export function muteUntil(key: string, now: Date = new Date()): string | null {
  const o = MUTE_OPTIONS.find((x) => x.key === key);
  if (!o) throw new Error("opção desconhecida");
  return o.hours === null ? null : new Date(now.getTime() + o.hours * 3_600_000).toISOString();
}

/** Data/hora no fuso do cliente (as datas vêm em UTC). */
export function fmtInTz(iso: string, tz: string | null | undefined): string {
  try {
    return new Intl.DateTimeFormat("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: tz || "UTC" }).format(new Date(iso));
  } catch {
    return new Intl.DateTimeFormat("pt-PT", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "UTC" }).format(new Date(iso)) + " UTC";
  }
}
