/** Pacote por guião (STU-03, ADR-0070): tipos e regras puras da lista (sem rede), testadas em tests/package-script.test.mts. */
type JobStatus = "queued" | "running" | "done" | "failed" | "dead" | "cancelled";
type JobProgress = { pct?: number; step?: string } | null;

export type Camera = "front" | "side";
export const CAMERA_LABEL: Record<Camera, string> = { front: "Frente", side: "Lado (com o som)" };

export type ClipLink = {
  asset_id: string; content_id: string; camera: Camera; session_id: string | null; source: "upload" | "biblioteca" | "agente";
  linked_label: string | null; linked_at: string; title: string; name: string | null;
  state: "pendente" | "pronta" | "falhou" | "apagada" | "sem_versao"; storage: string | null; version_id: string | null;
  version_no: number | null; duration: number | null; repeated?: boolean;
};
export type ScriptJob = {
  id: string; status: JobStatus; progress: JobProgress; last_error: string | null; created_label: string | null;
  created_at: string; worker_seen: boolean; origin: "manual" | "auto" | null; front_name: string | null; side_name: string | null;
  front_version: string | null; side_version: string | null;
  result: { missing?: string[]; flags?: string[] } | null;
  outputs: { guiao_id: string; hook: number; asset_id: string; title: string; export: { status: JobStatus; progress: JobProgress } | null }[];
};
export type ScriptRow = {
  guiao: { id: string; n: number; date: string; tema: string | null };
  front: ClipLink | null; side: ClipLink | null; job: ScriptJob | null;
  auto: { reason: string | null; at: string; job_id: string | null } | null;
};
/** Motivos do automático (package_script_status.reason) em PT-PT. Erros do servidor vêm como "codigo" ou "codigo: detalhe". */
const AUTO_REASON: Record<string, string> = {
  sem_responsavel: "ninguém ligou o automático",
  funcionalidade_desligada: "a funcionalidade está desligada para quem ligou o automático",
  sem_r2: "o armazenamento de vídeo (R2) não está ligado neste cliente",
  sem_permissao: "quem ligou o automático já não tem permissão para pedir pacotes",
  nome_repetido: "há outro ficheiro com o mesmo nome na Biblioteca (renomeia a gravação)",
  gravacoes_em_falta: "falta uma das gravações pronta",
  camaras_invalidas: "a frente e o lado são o mesmo ficheiro",
  guiao_nao_encontrado: "o guião foi eliminado",
};
export function autoReasonLabel(reason: string | null | undefined): string | null {
  if (!reason) return null;
  const code = reason.split(":")[0].trim();
  return AUTO_REASON[code] ?? reason;
}

export type RowState = "sem_gravacoes" | "falta_frente" | "falta_lado" | "a_verificar" | "gravacao_falhou" | "pronto_para_pacote"
  | "na_fila" | "a_preparar" | "pacote_pronto" | "pacote_falhou";
export const ROW_STATE_LABEL: Record<RowState, string> = {
  sem_gravacoes: "sem gravações", falta_frente: "falta a frente", falta_lado: "falta o lado", a_verificar: "gravações a verificar",
  gravacao_falhou: "uma gravação falhou", pronto_para_pacote: "pronto para o pacote", na_fila: "pacote na fila", a_preparar: "a preparar o pacote",
  pacote_pronto: "pacote pronto", pacote_falhou: "pacote falhou",
};

/**
 * Estado de um guião na lista. O pacote só conta se for das gravações atuais (ligar outra gravação ou carregar uma versão
 * nova pede um pacote novo); sem isso, o estado vem das gravações.
 */
export function rowState(r: Pick<ScriptRow, "front" | "side" | "job">): RowState {
  const clipsOk = r.front?.state === "pronta" && r.side?.state === "pronta";
  const current = !!r.job && (!clipsOk || (r.job.front_version === r.front?.version_id && r.job.side_version === r.side?.version_id));
  if (r.job && current) {
    if (r.job.status === "queued") return "na_fila";
    if (r.job.status === "running") return "a_preparar";
    if (r.job.status === "done") return "pacote_pronto";
    return "pacote_falhou";
  }
  if (!r.front && !r.side) return "sem_gravacoes";
  if (!r.front) return "falta_frente";
  if (!r.side) return "falta_lado";
  if (r.front.state === "falhou" || r.side.state === "falhou" || r.front.state === "apagada" || r.side.state === "apagada") return "gravacao_falhou";
  if (!clipsOk) return "a_verificar";
  return "pronto_para_pacote";
}

/** Câmaras escolhidas no envio: no máximo um ficheiro por câmara. Devolve a mensagem de erro ou null. */
export function cameraProblem(cams: (Camera | "")[]): string | null {
  const used = cams.filter((c): c is Camera => !!c);
  if (new Set(used).size !== used.length) return "Escolhe no máximo um ficheiro para cada câmara.";
  return null;
}
