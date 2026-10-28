import { DEFAULT_CLIENT, supabase } from "@/lib/supabase";

export type Semana = { semana: string; n: number; views: number; media: number };
export type ReelRow = {
  id: string; platform: string; url: string | null; titulo: string | null;
  views: number | null; likes: number | null; comments: number | null; shares?: number | null;
  outlier: number | null; dt: string | null;
};
export type RefRow = { owner: string; n: number; mediana: number; melhor: number };
export type FormatoRow = { formato: string | null; n: number; validados: number; gravados: number; rejeitados: number; score: number | null };
export type ContaRow = { id: string; platform: string; handle: string; label: string | null; active: boolean; n: number; views: number; mediana: number | null; ultimo: string | null };
export type DiaRow = { date: string; n: number; validados: number; gravados: number; rejeitados: number };

export type Desempenho = {
  kpi: {
    reels: number; views: number; mediana: number | null; media: number | null;
    likes: number; comentarios: number; ultimo: string | null;
    views_30d: number; reels_30d: number; outliers: number;
  };
  contas: ContaRow[];
  semanas: Semana[];
  top: ReelRow[];
  recentes: ReelRow[];
  referencias: RefRow[];
  formatos: FormatoRow[];
  dias: DiaRow[];
};

/** Agregados do cliente (RPC security definer: nunca expõe transcrições). */
export async function fetchDesempenho(clientId = DEFAULT_CLIENT, accountId: string | null = null): Promise<Desempenho> {
  const { data, error } = await supabase().rpc("desempenho", { p_client: clientId, p_account: accountId });
  if (error) throw new Error(error.message);
  return data as Desempenho;
}

const PT = "pt-PT";
export const fmtInt = (v: number | null | undefined) => new Intl.NumberFormat(PT, { maximumFractionDigits: 0 }).format(v ?? 0);
export const fmtCompact = (v: number | null | undefined) => new Intl.NumberFormat(PT, { notation: "compact", maximumFractionDigits: 1 }).format(v ?? 0);
export const fmtDay = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleDateString(PT, { day: "numeric", month: "short", timeZone: "Asia/Dubai" }) : "—";
