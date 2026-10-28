import { supabase } from "@/lib/supabase";
import { friendlyError, type Access } from "@/lib/access";

export type HojeAgente = { agent: string; status: string; message: string | null; created_at: string; passos: number; simulated: boolean };
export type HojeAtividade = { tipo: "validado" | "gravado" | "rejeitado" | "editado" | "corrida"; n: number | null; tema: string | null; at: string };
export type Hoje = {
  views_30d: number;
  views_prev_30d: number;
  reels_30d: number;
  ultimo: string | null;
  diario: { date: string; views: number; reels: number }[];
  agentes: HojeAgente[];
  run_id: string | null;
  atividade: HojeAtividade[];
};

/** Resumo do Hoje (RPC só de leitura; corridas de ensaio ficam de fora). */
export async function fetchHoje(access: Access): Promise<Hoje> {
  const { data, error } = await supabase().rpc("hoje_resumo", { p_client: access.ws, p_token: access.token });
  if (error) throw new Error(friendlyError(error.message));
  return data as Hoje;
}

/** "há 12 min", "há 3 h", "ontem", "12 out". */
export function relTime(iso: string, now = Date.now()): string {
  const m = Math.round((now - new Date(iso).getTime()) / 60000);
  if (m < 1) return "agora";
  if (m < 60) return `há ${m} min`;
  const h = Math.round(m / 60);
  if (h < 24) return `há ${h} h`;
  if (h < 48) return "ontem";
  return new Date(iso).toLocaleDateString("pt-PT", { day: "numeric", month: "short", timeZone: "Asia/Dubai" });
}

export const pctDelta = (a: number, b: number) => (b > 0 ? ((a - b) / b) * 100 : 0);
