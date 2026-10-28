import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";
import type { Guiao } from "@/lib/types";

export type AgentStatus = "start" | "think" | "talk" | "done" | "error";
export type AgentEvent = {
  id: number; run_id: string; client_id: string | null; slot: number | null;
  agent: string; to_agent: string | null; status: AgentStatus; message: string | null;
  model: string | null; ms: number | null; cost_eur: number | null; simulated: boolean; created_at: string;
};

/** As personagens da sala. x/y em % da sala; a ordem segue a linha de produção. */
export const AGENTS: { id: string; nome: string; papel: string; x: number; y: number; cor: string }[] = [
  { id: "analista", nome: "Analista", papel: "lê os números de ontem", x: 10, y: 18, cor: "#60a5fa" },
  { id: "reporter", nome: "Repórter", papel: "traz notícias do dia", x: 10, y: 50, cor: "#f472b6" },
  { id: "curioso", nome: "Curioso", papel: "caça factos estranhos", x: 10, y: 82, cor: "#a78bfa" },
  { id: "filosofo", nome: "Filósofo", papel: "cita livros e autores", x: 32, y: 82, cor: "#c084fc" },
  { id: "strategist", nome: "Strategist", papel: "escolhe tema e formato", x: 34, y: 34, cor: "#fbbf24" },
  { id: "hooksmith", nome: "HookSmith", papel: "escreve 8 hooks", x: 56, y: 18, cor: "#fb923c" },
  { id: "writer", nome: "Writer", papel: "escreve o corpo", x: 56, y: 58, cor: "#34d399" },
  { id: "critic", nome: "Critic", papel: "dá nota de 0 a 10", x: 78, y: 18, cor: "#f87171" },
  { id: "editor", nome: "Editor", papel: "corta o que soa a robô", x: 78, y: 58, cor: "#2dd4bf" },
  { id: "aprendiz", nome: "Aprendiz", papel: "aprende com o que viralizou", x: 90, y: 86, cor: "#94a3b8" },
];
export const agentById = (id: string | null | undefined) => AGENTS.find((a) => a.id === (id ?? "").toLowerCase());

export type RunRow = { run_id: string; created_at: string; simulated: boolean; n: number };

export async function fetchRuns(access: Access, limit = 8): Promise<RunRow[]> {
  const { data, error } = await supabase().rpc("agent_runs", { p_ws: access.ws, p_token: access.token, p_limit: limit });
  if (error) throw new Error(friendlyError(error.message));
  return (data ?? []) as RunRow[];
}

export async function fetchRun(access: Access, runId: string): Promise<AgentEvent[]> {
  const { data, error } = await supabase().rpc("agent_run_events", { p_ws: access.ws, p_run: runId, p_token: access.token });
  if (error) throw new Error(friendlyError(error.message));
  return (data ?? []) as AgentEvent[];
}

/**
 * Tempo real: canal privado `agents:<ws>` (RLS em realtime.messages exige agents.read).
 * Só com login; no modo código devolve null e a página atualiza ao recarregar.
 */
export function subscribeAgents(access: Access, onEvent: (e: AgentEvent) => void): (() => void) | null {
  if (access.token) return null;
  const sb = supabase();
  let ch: ReturnType<typeof sb.channel> | null = null;
  let closed = false;
  sb.realtime.setAuth().then(() => {
    if (closed) return;
    ch = sb.channel("agents:" + access.ws, { config: { private: true } })
      .on("broadcast", { event: "agent_event" }, (m) => onEvent(m.payload as AgentEvent))
      .subscribe();
  });
  return () => { closed = true; if (ch) sb.removeChannel(ch); };
}

type Sim = { agent: string; to?: string; status: AgentStatus; message: string; slot?: number; ms?: number };

/**
 * Ensaio da sala: percorre os passos do motor para testar a animação e o tempo real.
 * Não inventa resultados (regra do AGENTS.md §7 e PRD §20): cada mensagem diz só o que o passo faria,
 * e usa apenas temas e hooks que já existem nos guiões do dia. Fica gravado com simulated=true.
 */
export function buildSimulation(gs: Guiao[]): Sim[] {
  const pick = gs.filter((g) => g.status !== "rejeitado").slice(0, 2);
  const ev: Sim[] = [
    { agent: "analista", status: "start", message: "[ensaio] Aqui lia os reels de ontem e passava o resumo ao Strategist." },
    { agent: "analista", to: "strategist", status: "talk", message: "[ensaio] Resumo de desempenho seguiria aqui. Sem dados reais nesta corrida." },
    { agent: "reporter", to: "strategist", status: "talk", message: "[ensaio] Notícias do dia seguiriam aqui, com fonte." },
    { agent: "curioso", to: "strategist", status: "talk", message: "[ensaio] Factos verificáveis seguiriam aqui, com fonte." },
    { agent: "filosofo", to: "writer", status: "talk", message: "[ensaio] Citações verificadas seguiriam aqui." },
  ];
  pick.forEach((g) => {
    const slot = g.n;
    ev.push(
      { slot, agent: "strategist", status: "think", message: `[ensaio] Slot ${slot}: escolher tema e formato.` },
      { slot, agent: "strategist", to: "hooksmith", status: "talk", message: `[ensaio] Tema do guião existente: "${g.tema}" (${g.formato}).` },
      { slot, agent: "hooksmith", status: "think", message: "[ensaio] Escrever hooks." },
      { slot, agent: "hooksmith", to: "critic", status: "talk", message: `[ensaio] Hook já existente: "${g.hooks?.[0]?.text ?? ""}"` },
      { slot, agent: "critic", to: "writer", status: "talk", message: "[ensaio] A nota do Critic apareceria aqui." },
      { slot, agent: "writer", to: "editor", status: "talk", message: "[ensaio] O corpo do guião passaria ao Editor." },
      { slot, agent: "editor", status: "done", message: "[ensaio] As verificações do Editor apareceriam aqui." },
    );
  });
  ev.push({ agent: "aprendiz", status: "done", message: "[ensaio] Fim do ensaio. Nenhum guião foi criado ou alterado." });
  return ev;
}

export async function simulateRun(access: Access, events: Sim[]) {
  const { data, error } = await supabase().rpc("agent_simulate", { p_ws: access.ws, p_events: events, p_token: access.token });
  if (error) throw new Error(friendlyError(error.message));
  return data as number;
}
