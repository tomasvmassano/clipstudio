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
  // W2: modelo canónico (PRD §4). As colunas acima ficam por compatibilidade com o motor e os dashboards.
  editorial_status: EditorialStatus;
  production_status: ProductionStatus;
  current_version_id: string | null;
  approved_version_id: string | null;
  cta: string | null;
  notas: string | null;
  lock_version: number;
  created_at: string;
};

export type EditorialStatus = "draft" | "in_review" | "changes_requested" | "approved" | "rejected" | "archived";
export type ProductionStatus = "not_started" | "scheduled" | "recording" | "recorded" | "editing" | "ready" | "published" | "cancelled";

export const EDITORIAL_LABEL: Record<EditorialStatus, string> = {
  draft: "rascunho",
  in_review: "em revisão",
  changes_requested: "alterações pedidas",
  approved: "aprovado",
  rejected: "rejeitado",
  archived: "arquivado",
};

/** O que se pode editar na cópia de trabalho (content_save). */
export type ContentPatch = Partial<{ hooks: Hook[]; corpo: string; cta: string; notas: string; tema: string; formato: string }>;
export type EditorialTarget = "in_review" | "approved" | "changes_requested" | "rejected" | "archived" | "restore";

export type ContentHistory = {
  versions: { id: string; version_no: number; hooks: Hook[]; corpo: string; cta: string | null; created_at: string; created_kind: string; author: string | null; is_current: boolean; is_approved: boolean }[];
  transitions: { kind: "editorial" | "production"; from: string | null; to: string; reason: string | null; at: string; actor: string | null; version_no: number | null }[];
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
