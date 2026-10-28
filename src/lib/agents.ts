import { supabase } from "@/lib/supabase";
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

export async function fetchRuns(clientId: string, limit = 8) {
  const { data, error } = await supabase()
    .from("agent_feed").select("run_id, created_at, simulated").eq("client_id", clientId)
    .order("created_at", { ascending: false }).limit(400);
  if (error) throw error;
  const seen = new Map<string, { run_id: string; created_at: string; simulated: boolean; n: number }>();
  for (const r of data ?? []) {
    const cur = seen.get(r.run_id);
    if (cur) cur.n++;
    else seen.set(r.run_id, { ...r, n: 1 });
  }
  return [...seen.values()].slice(0, limit);
}

export async function fetchRun(runId: string): Promise<AgentEvent[]> {
  const { data, error } = await supabase().from("agent_feed").select("*").eq("run_id", runId).order("id");
  if (error) throw error;
  return (data ?? []) as AgentEvent[];
}

/** Eventos novos em tempo real (broadcast do trigger em agent_log). */
export function subscribeAgents(clientId: string, onEvent: (e: AgentEvent) => void): () => void {
  const ch = supabase()
    .channel("agents:" + clientId)
    .on("broadcast", { event: "agent_event" }, (m) => onEvent(m.payload as AgentEvent))
    .subscribe();
  return () => { supabase().removeChannel(ch); };
}

type Sim = { agent: string; to?: string; status: AgentStatus; message: string; slot?: number; ms?: number };

/** Uma corrida fictícia montada com guiões reais do dia, para ver a sala antes do motor ter chave. */
export function buildSimulation(gs: Guiao[]): Sim[] {
  const pick = gs.filter((g) => g.status !== "rejeitado").slice(0, 2);
  const ev: Sim[] = [
    { agent: "analista", status: "start", message: "Bom dia. A ler os reels de ontem." },
    { agent: "analista", to: "strategist", status: "talk", message: "Homens e mulheres continua a puxar: 2,4× a mediana nos últimos 7 dias. Notícias a 0,6×." },
    { agent: "reporter", to: "strategist", status: "talk", message: "Três notícias com debate hoje. Nenhuma com fonte sólida o suficiente para um callout." },
    { agent: "curioso", to: "strategist", status: "talk", message: "Tenho um facto: caranguejos num balde puxam-se uns aos outros para baixo. Dá para mecanismo." },
    { agent: "filosofo", to: "writer", status: "talk", message: "Para amizade e inveja: La Rochefoucauld, 'na desgraça dos amigos há sempre algo que não nos desagrada'." },
  ];
  pick.forEach((g, i) => {
    const slot = g.n;
    const h = g.hooks ?? [];
    const primeira = (g.corpo ?? "").split("\n").find(Boolean) ?? "";
    ev.push(
      { slot, agent: "strategist", status: "think", message: `Slot ${slot}: a escolher tema e máquina.` },
      { slot, agent: "strategist", to: "hooksmith", status: "talk", message: `Tema "${g.tema}". Formato ${g.formato}. Quero tese inteira no hook.` },
      { slot, agent: "hooksmith", status: "think", message: "A escrever 8 hooks com mecanismos diferentes." },
      { slot, agent: "hooksmith", to: "critic", status: "talk", message: `Melhores 3: "${h[0]?.text ?? ""}" e mais dois.` },
      { slot, agent: "critic", to: "hooksmith", status: "talk", message: i === 0 ? "O 3.º está fraco (6/10). Troca." : "Os três passam. 8,4 de média." },
      ...(i === 0 ? [{ slot, agent: "hooksmith", to: "critic", status: "talk" as const, message: `Trocado: "${h[2]?.text ?? ""}"` }] : []),
      { slot, agent: "writer", status: "think", message: "A escrever o corpo na voz do Numeiro." },
      { slot, agent: "writer", to: "editor", status: "talk", message: `Abre assim: "${primeira.slice(0, 140)}"` },
      { slot, agent: "editor", to: "writer", status: "talk", message: i === 0 ? "Ritmo de robô: 41% de frases curtas. E acabaste com pergunta genérica. Refaz o fecho." : "Limpo. 0 problemas." },
      ...(i === 0 ? [{ slot, agent: "writer", to: "editor", status: "talk" as const, message: "Fecho refeito com veredito. Frases curtas a 28%." }] : []),
      { slot, agent: "critic", status: "done", message: `Guião ${slot} aprovado. Nota ${(8 + i * 0.3).toFixed(1)}.` },
    );
  });
  ev.push(
    { agent: "editor", status: "done", message: "Guiões prontos e enviados para a página Guiões." },
    { agent: "aprendiz", status: "done", message: "Anotado: hooks com número batem os de pergunta esta semana." },
  );
  return ev;
}

export async function simulateRun(token: string, events: Sim[]) {
  const { data, error } = await supabase().rpc("agent_simulate", { p_token: token, p_events: events });
  if (error) throw new Error(error.message.includes("codigo_invalido") ? "Código de equipa inválido." : error.message);
  return data as number;
}
