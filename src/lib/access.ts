import { supabase } from "@/lib/supabase";

/** Como esta página acede aos dados: workspace + (só no modo código) o token legado. */
export type Access = { ws: string; token: string | null };

export type WorkspaceCtx = {
  id: string;
  name: string;
  handle: string | null;
  timezone: string;
  currency: string;
  role: string;
  affiliation: "agency_staff" | "client_staff";
  capabilities: string[];
};

export type AppContext = {
  user: { id: string; email: string; confirmed: boolean };
  agency: { organization: string; name: string; role: string; status: string }[] | null;
  workspaces: WorkspaceCtx[];
};

/** Capacidades do código de equipa (espelha legacy_can no SQL; o servidor é quem decide). */
export const LEGACY_CAPS = [
  "scripts.read", "scripts.edit", "scripts.submit", "scripts.approve", "scripts.reject", "scripts.export",
  "recording.use", "recording.confirm", "sources.read", "analytics.read", "agents.read", "agents.rehearse",
];

/** Aceita convites pendentes para o email confirmado e devolve o contexto do utilizador. */
export async function loadContext(): Promise<AppContext | null> {
  const sb = supabase();
  await sb.rpc("accept_invitations").then(() => undefined, () => undefined);
  const { data, error } = await sb.rpc("my_context");
  if (error) throw new Error(friendlyError(error.message));
  return (data as AppContext | null) ?? null;
}

/** Mensagens de erro do servidor em PT-PT. */
export function friendlyError(msg: string): string {
  if (msg.includes("sem_permissao") || msg.includes("permission denied")) return "Não tens permissão para isto neste workspace.";
  if (msg.includes("codigo_invalido") || msg.includes("nao_autenticado")) return "Sessão inválida ou expirada. Entra outra vez.";
  if (msg.includes("acima_do_teto")) return "Não podes dar a alguém um papel acima do teu.";
  if (msg.includes("email_invalido")) return "Email inválido.";
  if (msg.includes("papel_invalido")) return "Papel inválido.";
  if (msg.includes("nada_a_alterar")) return "Nada para guardar.";
  if (msg.includes("conflito_edicao")) return "Alguém mudou este guião entretanto. Recarreguei a versão mais recente: revê e volta a guardar.";
  if (msg.includes("motivo_obrigatorio")) return "Escreve o motivo.";
  if (msg.includes("transicao_invalida")) return "Esta ação já não se aplica ao estado atual do guião. Recarrega.";
  if (msg.includes("nao_elegivel")) return "Guiões rejeitados ou arquivados não se gravam.";
  if (msg.includes("aprovacao_necessaria")) return "Neste cliente só se gravam guiões aprovados.";
  if (msg.includes("arquivado")) return "Este guião está arquivado. Recupera-o primeiro.";
  if (msg.includes("corpo_vazio")) return "O corpo não pode ficar vazio.";
  if (msg.toLowerCase().includes("failed to fetch") || msg.toLowerCase().includes("network")) return "Sem ligação ao servidor. Verifica a internet e tenta de novo.";
  return msg;
}

export const ROLE_LABEL: Record<string, string> = {
  agency_owner: "Dono da agência",
  workspace_owner: "Dono",
  workspace_admin: "Admin",
  manager: "Gestor",
  contributor: "Colaborador",
  reviewer: "Revisor",
  viewer: "Leitor",
  creator: "Creator (código)",
};
