import { supabase } from "@/lib/supabase";

/** Como esta página acede aos dados: workspace + (só no modo código) o token legado. */
export type Access = { ws: string; token: string | null };

export type WorkspaceCtx = {
  id: string;
  name: string;
  handle: string | null;
  timezone: string;
  currency: string;
  logo_path?: string | null;
  brand_color?: string | null;
  role: string;
  affiliation: "agency_staff" | "client_staff";
  capabilities: string[];
};

export type AppContext = {
  user: {
    id: string; email: string; confirmed: boolean;
    display_name?: string | null; avatar_path?: string | null; timezone?: string | null; theme?: "system" | "light" | "dark"; preferred_workspace?: string | null;
  };
  /** A pessoa tem MFA ativo e esta sessão ainda não passou o código (aal1): o servidor recusa tudo até passar. */
  mfa_required?: boolean;
  agency: { organization: string; name: string; role: string; status: string; capabilities?: string[] }[] | null;
  workspaces: WorkspaceCtx[];
  /** Erro ao aceitar convites pendentes neste login (mostrado a quem ainda não tem clientes). */
  invite_error?: string;
};

/** Capacidades do código de equipa (espelha legacy_can no SQL; o servidor é quem decide). */
export const LEGACY_CAPS = [
  "scripts.read", "scripts.edit", "scripts.submit", "scripts.approve", "scripts.reject", "scripts.export",
  "recording.use", "recording.confirm", "sources.read", "requests.create", "references.read", "tasks.read", "calendar.read", "analytics.read", "agents.read", "agents.rehearse", "review.comment",
];

/** Aceita convites pendentes para o email confirmado e devolve o contexto do utilizador. */
export async function loadContext(): Promise<AppContext | null> {
  const sb = supabase();
  // se aceitar convites falhar, a app abre na mesma e diz porquê (em vez de um "sem acesso" mudo)
  const acc = await sb.rpc("accept_invitations");
  const { data, error } = await sb.rpc("my_context");
  if (error?.message.includes("sessao_terminada")) {
    // sessão terminada noutro dispositivo ou por quem gere a equipa (W10-08): sai só deste browser e manda entrar outra vez
    await sb.auth.signOut({ scope: "local" }).catch(() => undefined);
    throw new Error(friendlyError(error.message));
  }
  if (error) throw new Error(friendlyError(error.message));
  const ctx = (data as AppContext | null) ?? null;
  return ctx && acc.error ? { ...ctx, invite_error: friendlyError(acc.error.message) } : ctx;
}

/** Mensagens de erro do servidor em PT-PT. */
// Em pré-visualização (BIZ-07) o servidor recusa as escritas com 42501: a mensagem diz porquê.
let previewMode = false;
export function setPreviewMode(on: boolean) { previewMode = on; }

export function friendlyError(msg: string): string {
  if (previewMode && (msg.includes("sem_permissao") || msg.includes("permission denied")))
    return "Estás em pré-visualização: só leitura. Sai da pré-visualização para fazer alterações.";
  if (msg.includes("sem_permissao") || msg.includes("permission denied")) return "Não tens permissão para isto neste workspace.";
  if (msg.includes("sessao_terminada")) return "Esta sessão foi terminada. Entra outra vez.";
  if (msg.includes("sessao_nao_encontrada")) return "Essa sessão já não existe. A lista foi atualizada.";
  if (msg.includes("sessao_desconhecida")) return "Não foi possível identificar esta sessão. Sai e volta a entrar.";
  if (msg.includes("codigo_invalido") || msg.includes("nao_autenticado")) return "Sessão inválida ou expirada. Entra outra vez.";
  if (msg.includes("acima_do_teto")) return "Não podes dar a alguém um papel acima do teu.";
  if (msg.includes("email_invalido")) return "Email inválido.";
  if (msg.includes("papel_invalido")) return "Papel inválido.";
  if (msg.includes("nada_a_alterar")) return "Nada para guardar.";
  if (msg.includes("guiao_nao_encontrado")) return "Este guião já não existe neste cliente ou não tens acesso.";
  if (msg.includes("funcionalidade_desligada")) return "Esta funcionalidade ainda está em teste e não está ligada para ti.";
  if (msg.includes("conflito_versao_edicao")) return "Alguém gravou uma versão deste vídeo entretanto. Recarrega a versão mais recente e volta a aplicar as tuas alterações.";
  if (msg.startsWith("modo_guiado:")) return "No modo guiado não dá para gravar isto: " + msg.slice("modo_guiado:".length).trim() + ".";
  if (msg.startsWith("documento_invalido:")) return "Não dá para gravar: " + msg.slice("documento_invalido:".length).trim() + ".";
  if (msg.includes("versao_imutavel")) return "As versões de edição não se alteram: grava uma nova.";
  if (msg.includes("conflito_edicao")) return "Alguém mudou este guião entretanto. Recarreguei a versão mais recente: revê e volta a guardar.";
  if (msg.includes("motivo_obrigatorio")) return "Escreve o motivo.";
  if (msg.includes("versao_antiga")) return "Há uma versão mais recente deste vídeo. Decide sobre essa.";
  if (msg.includes("ja_aprovado")) return "Este vídeo já foi aprovado. Para mudar, junta uma versão nova na biblioteca.";
  if (msg.includes("momento_invalido")) return "Esse momento fica fora do vídeo.";
  if (msg.includes("anotacao_invalida")) return "O desenho não é válido (demasiadas formas ou pontos, ou fora do vídeo). Desfaz parte e tenta de novo.";
  if (msg.includes("anotacao_sem_momento")) return "O desenho precisa do momento do vídeo.";
  if (msg.includes("anotacao_em_resposta")) return "As respostas não levam desenho.";
  if (msg.includes("anotacao_so_em_ficheiro")) return "Só se desenha em vídeos guardados na app (não nos da Drive).";
  if (msg.includes("media_nao_encontrado")) return "Este vídeo já não existe ou não tens acesso.";
  if (msg.includes("transicao_invalida")) return "Esta ação já não se aplica ao estado atual do guião. Recarrega.";
  if (msg.includes("nao_elegivel")) return "Guiões rejeitados ou arquivados não se gravam.";
  if (msg.includes("aprovacao_necessaria")) return "Neste cliente só se gravam guiões aprovados.";
  if (msg.includes("pre_requisito_em_falta")) return "Falta um pré-requisito desta transição. Vê as regras em Definições.";
  if (msg.includes("confirmacao_invalida")) return "Confirmação em falta ou errada: nada foi eliminado.";
  if (msg.includes("nao_arquivado")) return "Só se eliminam guiões arquivados. Arquiva-o primeiro.";
  if (msg.includes("tem_dependencias")) return "Este guião ainda tem tarefas, publicações ou ativos ligados.";
  if (msg.includes("prazo_expirado")) return "Já passaram mais de 30 dias: não se recupera.";
  if (msg.includes("sessao_individual")) return "Isto precisa de uma sessão individual (não do código de equipa).";
  if (msg.includes("texto_mudou")) return "O texto mudou depois de gravado: abre o guião e decide à mão.";
  if (msg.includes("arquivado")) return "Este guião está arquivado. Recupera-o primeiro.";
  if (msg.startsWith("duplicado:")) return "Esta fonte já existe neste cliente.";
  if (msg.includes("link_nao_suportado")) return "Cola um link de um Reel do Instagram ou de um vídeo do TikTok. Para outros links usa Adicionar por link.";
  if (msg.includes("transcricao_invalida")) return "A transcrição tem de ter entre 20 e 20 000 caracteres.";
  if (msg.includes("sem_disseccao")) return "Primeiro é preciso dissecar esta referência.";
  if (msg.includes("referencia_arquivada")) return "Esta referência está arquivada. Recupera-a primeiro.";
  if (msg.includes("referencia_nao_encontrada")) return "Esta referência já não existe neste cliente ou não tens acesso.";
  if (msg.includes("url_obrigatorio")) return "Falta o link da referência.";
  if (msg.includes("url_invalido")) return "O link tem de começar por http:// ou https://.";
  if (msg.includes("titulo_obrigatorio")) return "Falta o título.";
  if (msg.includes("texto_curto")) return "Escreve um pouco mais sobre o que queres.";
  if (msg.includes("texto_longo")) return "O pedido é demasiado longo (máximo 2000 caracteres).";
  if (msg.includes("duracao_s")) return "A duração tem de estar entre 1 e 3600 segundos.";
  if (msg.includes("corpo_vazio")) return "O corpo não pode ficar vazio.";
  if (msg.includes("sem_configuracao_ativa")) return "Este cliente ainda não tem configuração dos agentes ativa.";
  if (msg.includes("orcamento_esgotado")) return "O limite de custo diário dos agentes já foi atingido hoje.";
  if (msg.includes("configuracao_invalida")) return "Esta versão tem erros: corrige-os e guarda uma versão nova antes de ativar.";
  if (msg.includes("execucao_nao_encontrada")) return "Esta execução já não existe.";
  if (msg.includes("filtro_invalido")) return "Filtro inválido. Limpa os filtros e tenta de novo.";
  if (msg.includes("mfa_necessario")) return "Confirma primeiro o código da verificação em dois passos.";
  if (msg.includes("fuso_invalido")) return "Fuso horário inválido.";
  if (msg.includes("tema_invalido")) return "Tema inválido.";
  if (msg.includes("nome_longo")) return "O nome tem de ter até 80 caracteres.";
  if (msg.includes("caminho_invalido")) return "Imagem inválida. Escolhe outra.";
  if (msg.includes("demasiados_eventos")) return "Demasiadas alterações de segurança seguidas. Espera um pouco.";
  if (msg.includes("bloco_invalido")) return "Esse bloco já não existe neste guião. Recarrega.";
  if (msg.includes("resposta_invalida")) return "Só se responde a comentários (não a respostas).";
  if (msg.includes("comentario_nao_encontrado")) return "Esse comentário já não existe.";
  if (msg.includes("aguarda_para_reenviar")) return "Acabaste de enviar este convite. Espera um minuto antes de reenviar.";
  if (msg.includes("limite_envios")) return "Este convite já foi enviado 5 vezes. Cancela-o e cria um novo se for preciso.";
  if (msg.includes("convite_fechado")) return "Este convite já foi aceite, recusado ou cancelado.";
  if (msg.includes("link_invalido")) return "Este link de convite não é válido.";
  if (msg.includes("ja_e_staff")) return "Essa pessoa já faz parte da equipa da agência.";
  if (msg.includes("convite_pendente")) return "Já há um convite pendente para esse email.";
  if (msg.includes("pessoa_e_equipa_de_cliente")) return "Essa pessoa faz parte da equipa de um cliente e não pode entrar na agência.";
  if (msg.includes("dono_protegido")) return "O dono da agência não se altera aqui.";
  if (msg.includes("periodo_invalido")) return "Período inválido: o fim não pode ser antes do início.";
  if (msg.includes("periodo_demasiado_longo")) return "O período máximo é de um ano.";
  if (msg.includes("widget_desconhecido") || msg.includes("widgets_invalidos")) return "Há widgets repetidos ou que já não existem. Recarrega e tenta de novo.";
  if (msg.includes("widgets_vazios")) return "Escolhe pelo menos um widget.";
  if (msg.includes("funcao_invalida")) return "Função inválida.";
  if (msg.includes("efeito_invalido")) return "Escolhe permitir ou negar.";
  if (msg.includes("capacidade_invalida")) return "Essa permissão não existe para clientes.";
  if (msg.includes("logotipo_invalido")) return "Esse logótipo não foi encontrado. Carrega-o outra vez.";
  if (msg.includes("cor_invalida")) return "Cor inválida (formato #RRGGBB).";
  if (msg.includes("nome_invalido")) return "O nome tem de ter entre 2 e 80 caracteres.";
  if (msg.includes("handle_invalido")) return "O @ só pode ter letras minúsculas, números, ponto e underscore (até 30).";
  if (msg.includes("fuso_invalido")) return "Fuso horário desconhecido.";
  if (msg.includes("moeda_invalida")) return "Moeda inválida (código de 3 letras, ex.: EUR).";
  if (msg.includes("organizacao_ambigua")) return "Pertences a mais de uma agência: este caso ainda não é suportado.";
  if (msg.includes("cliente_origem_invalido")) return "O cliente de onde querias copiar não existe nesta agência.";
  if (msg.includes("membro_nao_encontrado")) return "Esta pessoa já não está na equipa. Recarrega.";
  if (msg.includes("nao_a_si_proprio")) return "Não podes mudar o teu próprio acesso. Pede a outra pessoa com permissão.";
  if (msg.includes("ultimo_dono")) return "É o último dono do cliente. Passa primeiro a posse a outra pessoa.";
  if (msg.includes("estado_invalido")) return "Estado inválido.";
  if (msg.includes("nao_e_staff_da_agencia")) return "Essa pessoa não faz parte da equipa da agência.";
  if (msg.includes("ja_e_equipa_do_cliente")) return "Essa pessoa já é da equipa do cliente.";
  if (msg.includes("campo_desconhecido")) return "Pedido com um campo que não existe. Recarrega a página.";
  if (msg.includes("dependencia_invalida")) return "Cada tarefa do template só pode depender de tarefas acima dela.";
  if (msg.includes("template_nao_encontrado")) return "Este template já não existe ou está desligado.";
  if (msg.includes("nome_obrigatorio")) return "Dá um nome ao template.";
  if (msg.includes("limite_invalido")) return "O limite tem de estar entre 1 e 100.";
  if (msg.includes("prazo_invalido")) return "Prazo inválido: dias entre -60 e 60, hora entre 0 e 23.";
  if (msg.includes("data_passada")) return "Não se agenda para um dia que já passou.";
  if (msg.includes("data_longe")) return "Essa data está longe demais (máximo um ano e um mês).";
  if (msg.includes("nao_reagendavel")) return "Guiões cancelados ou publicados não mudam de dia. Reativa primeiro.";
  if (msg.includes("intervalo_invalido")) return "Intervalo de datas inválido.";
  if (msg.includes("responsavel_sem_acesso")) return "Essa pessoa não tem acesso a tarefas neste cliente.";
  if (msg.includes("dependencias_abertas")) return "Ainda há tarefas de que esta depende por fechar.";
  if (msg.includes("dependencia_circular")) return "Isso criava um ciclo: uma tarefa ficaria à espera de si própria.";
  if (msg.includes("mencao_sem_acesso")) return "Só podes mencionar quem tem acesso a este cliente.";
  if (msg.includes("comentario_vazio")) return "Escreve o comentário.";
  if (msg.includes("comentario_longo")) return "O comentário é demasiado longo (máximo 4000 caracteres).";
  if (msg.includes("tarefa_nao_encontrada")) return "Esta tarefa já não existe ou não tens acesso.";
  if (msg.includes("evento_invalido")) return "Esse evento não pode ser usado numa automação.";
  if (msg.includes("sessao_fechada")) return "Esta sessão de gravação já foi fechada. Abre o teleprompter outra vez.";
  if (msg.includes("sessao_nao_encontrada")) return "A sessão de gravação já não existe. Abre o teleprompter outra vez.";
  if (msg.includes("item_desconhecido")) return "Este guião já não está na fila desta sessão. Recarrega a fila.";
  if (msg.includes("bloco_invalido")) return "Esse bloco não existe neste guião.";
  if (msg.includes("take_descartado")) return "Recupera o take antes de o escolher.";
  if (msg.includes("client_ref_reutilizado")) return "Take repetido com dados diferentes. Recarrega a sessão.";
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
