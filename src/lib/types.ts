// Modelo de dados da app. Tudo tem client_id: a app nasce multi-cliente.
export type Hook = { text: string; mecanismo: string };

export type Guiao = {
  id: string;
  client_id: string;
  date: string; // YYYY-MM-DD (dia de Dubai)
  n: number;
  formato: string | null;
  maquina: string | null;
  tema: string | null;
  hooks: Hook[];
  corpo: string;
  fonte: string | null;
  legenda: string | null;
  comentario_fixado: string | null;
  critic_score: number | null;
  origem: string | null;
  status: "aprovado" | "rejeitado";
  motivo_rejeicao: string | null;
  validado: boolean;
  validado_em: string | null;
  gravado: boolean;
  gravado_em: string | null;
  history: { hooks: Hook[]; corpo: string; at: string | null }[];
  updated_at: string;
};

export type GuiaoPatch = Partial<
  Pick<Guiao, "status" | "motivo_rejeicao" | "validado" | "gravado" | "hooks" | "corpo" | "formato" | "tema" | "n">
>;

export type Idea = {
  id: number;
  fonte_tipo: string | null;
  titulo: string | null;
  take_numeiro: string | null;
  categoria: string | null;
  status: string | null;
  created_at: string;
  expires_at: string | null;
  data: Record<string, unknown> | null;
};

export type Session = { token: string; client_id: string; role: string; label: string | null };

export const WPS = 2.6; // palavras por segundo do Numeiro, para estimar duração

export const FORMATO_LABEL: Record<string, string> = {
  conselho_absurdo: "lei absurda",
  paradoxo: "redefinição",
  mecanismo: "mecanismo",
  rant_habito: "rant",
  hipocrisia: "hipocrisia",
  callout: "callout",
  lista: "lista",
  tabu: "tabu",
  historia_pessoal: "confissão",
  citacao: "citação",
  noticia: "notícia",
};
