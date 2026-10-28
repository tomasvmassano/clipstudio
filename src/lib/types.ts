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

// W2-03: fontes (tabela ideas), pedidos do talento e brief.
export type SourceStatus = "nova" | "triagem" | "selecionada" | "usada" | "descartada" | "rejeitada";
export type Source = {
  id: number;
  client_id: string;
  kind: "source" | "talent_request";
  fonte_tipo: string | null;
  titulo: string | null;
  fonte: string | null;
  fonte_url: string | null;
  url_normalized: string | null;
  categoria: string | null;
  formato_sugerido: string | null;
  urgencia: string | null;
  autor: string | null;
  tags: string[];
  resumo: string | null;
  notas: string | null;
  status: SourceStatus;
  status_reason: string | null;
  expira_em: string | null;
  agent: string | null;
  created_kind: "engine" | "user" | "legacy_code";
  created_label: string | null;
  ingested_via: string;
  created_at: string;
  data: Record<string, unknown> | null;
  take: string | null;
  linked: { id: string; date: string; n: number; tema: string | null; editorial_status: EditorialStatus }[];
};
export const SOURCE_STATUS_LABEL: Record<SourceStatus, string> = {
  nova: "nova", triagem: "em triagem", selecionada: "selecionada", usada: "usada", descartada: "descartada", rejeitada: "descartada",
};
export type Brief = {
  id: string; version_no: number; objetivo: string | null; audiencia: string | null; tese: string | null; formato: string | null;
  duracao_s: number | null; plataformas: string[]; cta: string | null; referencias: string | null; restricoes: string | null;
  dono: string | null; deadline: string | null; created_at: string; created_label: string | null;
};
export type BriefFields = Partial<Omit<Brief, "id" | "version_no" | "created_at" | "created_label">>;
export type ContentContext = {
  brief: Brief | null;
  brief_versions: number;
  approved_brief_id: string | null;
  sources: { id: number; titulo: string | null; kind: string; fonte_tipo: string | null; fonte: string | null; fonte_url: string | null; status: SourceStatus }[];
  references: { id: number; titulo: string; creator: string | null; url: string | null; formato: string | null }[];
};

// W2-04: referências (M07). Métricas só quando vêm do scraper, com data de recolha (FR-07-06).
export type RefMetrics = { views: number | null; likes: number | null; comments: number | null; outlier: number | null; duration: number | null; collected_at: string | null; source: "scraper" };
export type RefAnalysis = { tese: string | null; gatilho?: string | null; estrutura?: string | null; porque_viraliza: string | null; formato: string | null; analyzed_at?: string | null };
export type Reference = {
  id: number; workspace_id: string; url: string | null; reel_id: string | null; platform: string | null; creator: string | null; titulo: string;
  hook: string | null; formato: string | null; estilo: string | null; narrativa: string | null; duracao_s: number | null; idioma: string | null;
  tags: string[]; colecoes: string[]; notas: string | null; favorito: boolean; archived_at: string | null; created_label: string | null; created_at: string;
  metrics: RefMetrics | null; analysis: RefAnalysis | null; links: { content_id: string | null; source_id: number | null; label: string }[];
};
export type DiscoverReel = {
  id: string; url: string | null; platform: string | null; creator: string; hook: string | null; caption: string | null; views: number | null;
  likes: number | null; comments: number | null; outlier: number | null; duration: number | null; collected_at: string | null; analysis: RefAnalysis | null;
};
export type Discover = { creators: { id: string; handle: string; platform: string; reels: number }[]; reels: DiscoverReel[] };
