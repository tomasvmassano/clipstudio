# Matriz de acessos

Fonte: PRD v2.1 §3 (papéis), §5A (TEAM-01…16), CAP-03/05/08. **PROPOSTA de defaults**, a validar pelo owner; grants individuais e negações explícitas por cima (CAP-03).

**Avaliação** (PRD §3): `allow` só se identidade ativa ∧ membership ativo ∧ workspace autorizado ∧ grant suficiente ∧ recurso no âmbito ∧ sem `deny` explícito. Por defeito `deny`. A afiliação (`agency_staff`/`client_staff`) e o cargo (clipper, editor…) **não** são papéis.

## Papéis da agência (âmbito `org`)

| Capacidade | agency_owner | agency_admin | agency_manager | agency_member |
| --- | --- | --- | --- | --- |
| `workspaces.read` (lista `/clientes`) | todos, incluindo arquivados | só os atribuídos | — (troca pelos atribuídos no seletor) | — (idem) |
| `workspaces.create` / `archive` | ✓ | — (delegar exige grants de âmbito org, por fazer) | — | — |
| `team.invite` (staff interno) | ✓ | se delegado | — | — |
| `team.manage` (atribuir staff a clientes, `agency_staff_assign`) | ✓ | — (idem) | — | — |
| `permissions.manage` (org) | ✓ | limitado | — | — |
| `costs.read_agency` | ✓ | se delegado | — | — |
| `audit.read` (org) | ✓ | ✓ | — | — |
| `flags.manage` (funcionalidades em teste, `/funcionalidades`) | ✓ | — | — | — |
| `biz.read` (vista de negócio, só operacional dos clientes atribuídos) | ✓ (todos) | ✓ | ✓ | ✓ |
| `biz.finance` (contratos, receita, custos, margem) | ✓ | — | — | — |
| `contracts.manage` | ✓ | — | — | — |
| `publishing.limits.manage` (W7) | ✓ | — | — | — |
| `privacy.manage` (W7) | ✓ | — | — | — |

Um `agency_member` sem atribuição a um workspace **não vê nada** desse workspace (R-03, TEAM-03).

## Papéis do workspace (âmbito `ws`)

| Capacidade | ws_owner | ws_admin | manager | contributor | reviewer | viewer |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `scripts.create` / `edit` / `submit` | ✓ | ✓ | ✓ | ✓ (own) | — | — |
| `scripts.approve` / `reject` | ✓ | ✓ | ✓ | — | ✓ | — |
| `scripts.delete` | ✓ | ✓ | — | — | — | — |
| `scripts.export` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `recording.use` / `confirm` | ✓ | ✓ | ✓ | ✓ (own) | — | — |
| `styles.manage` (W5-02) | ✓ | ✓ | ✓ | — | — | — |
| `projects.manage` (W2-07) | ✓ | ✓ | ✓ | — | — | — |
| `analytics.manage` (W6, centro de desempenho) | ✓ | ✓ | ✓ | — | — | — |
| `tasks.delegate` (W6) | ✓ | ✓ | ✓ | ✓ (as suas) | ✓ (as suas) | — |
| `ops.presence` (W6) | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `publishing.schedule` (W7) | ✓ | ✓ | ✓ | — | — | — |
| `publishing.approve` (W7) | ✓ | ✓ | ✓ | — | — | — |
| `publishing.republish.approve` / `publishing.policy.manage` / `social_accounts.manage` (W7) | ✓ | ✓ | — | — | — | — |
| `learn.read` (W7) | ✓ | ✓ | ✓ | — | ✓ | — |
| `learn.manage` (W7) | ✓ | ✓ | ✓ | — | — | — |
| `calendar.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `calendar.schedule` | ✓ | ✓ | ✓ | — | — | — |
| `production.update` | ✓ | ✓ | ✓ | ✓ (own) | — | — |
| `tasks.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `tasks.work` (só as suas tarefas; comentar) | ✓ | ✓ | ✓ | ✓ (own) | ✓ (own) | — |
| `tasks.manage` (criar, atribuir, automações) | ✓ | ✓ | ✓ | — | — | — |
| `sources.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `sources.create` / `triage` | ✓ | ✓ | ✓ | ✓ | — | — |
| `requests.create` (pedido do talento) | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `references.read` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `references.manage` | ✓ | ✓ | ✓ | — | — | — |
| ligar referência a guião | precisa de `references.read` + `scripts.edit` no mesmo cliente |||||
| `review.comment` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `review.approve` | ✓ | ✓ | ✓ | — | ✓ | — |
| `media.upload` / `download` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `media.share` | ✓ | ✓ | ✓ | — | — | — |
| `publishing.schedule` / `publish` | ✓ | ✓ | grant | — | — | — |
| `analytics.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `costs.read` | ✓ | ✓ | grant | — | — | — |
| `agents.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `agents.rehearse` / `run` | ✓ | ✓ | ✓ | — | — | — |
| `agents.configure` | ✓ | ✓ | — | — | — | — |
| custo de execuções e limite diário | precisa de `costs.read`; sem ela a app e o RPC omitem custo, tokens, gasto e limite |||||
| worker do motor (`worker_claim`, `worker_heartbeat`, `worker_save_script`, `worker_finish`) | só `service_role` e o utilizador de base `engine_worker` (sem login até o dono definir password); nenhum papel de utilizador nem o código de equipa |||||
| `engine_worker` nas tabelas | lê e escreve só as tabelas de pesquisa do motor; não lê `guioes`, `workspace_access`, `agent_jobs` nem configurações; guiões só por `worker_save_script` |||||
| dados de pesquisa do motor (W4-03) | por cliente (`client_id` em reels, temas, citações, análises, generated, meta, relatórios); o motor só lê e escreve no cliente da execução; Descobrir e referências só mostram reels e análises do próprio cliente; anon e authenticated sem linhas (RLS sem política). A política do `engine_worker` exige o cliente da sessão (`engine.client_id`); sem ele não vê nada |||||
| Início (`dashboard_get`, W1-10) | cada widget e cada número só com as capacidades dele no cliente (registo `dashboard_widgets`); layout por função, mudado só com `dashboard.configure` (dono e admin), auditado; código de equipa só no próprio cliente, sem custos |||||
| Painel da agência (`agency_dashboard`) | só equipa da agência com `dashboard.agency`; só clientes ativos com acesso (dono: todos); números por cliente com a capacidade nesse cliente; equipa de cliente recusada (42501) |||||
| Espaços (W1-11) | agência em `/`, `/clientes`, `/caixa` (só `dashboard.agency`); cliente em `/c/<cliente>/…`; o endereço não autoriza nada, cada RPC volta a verificar; cliente sem acesso ou inexistente: a mesma mensagem |||||
| Convites (W1-11) | equipa de cliente só convida para o seu cliente, nunca staff da agência nem acima do seu papel; uma pessoa da equipa de um cliente só pertence a um cliente (convite para outro é cancelado e registado) |||||
| Equipa da agência (W1-13) | ver: dono e admin da agência; convidar, mudar papel, suspender, atribuir: só o dono; ninguém se altera a si próprio; dono protegido; cada pessoa mostra só os clientes que quem vê pode ver; equipa de cliente e membros da agência sem `team.read` recusados (42501) |||||
| `team.invite` (client_staff, mesmo workspace) | ✓ | ✓ | — | — | — | — |
| Comentários em guiões (W2-06) | ler: `scripts.read`; comentar: `review.comment` (contributor, reviewer, manager, admin, dono, código do Numeiro); resolver: autor ou quem edita/aprova; leitor só lê; outro cliente 42501; não se apagam nem se reescrevem |||||
| Perfil (W1-15) | cada pessoa só lê e muda o seu (RPCs com `auth.uid()`; tabela fechada); avatar só na pasta `<uid>/`; cliente preferido só entre os seus; com MFA ligado, sessão sem código (aal1) não passa em `_authorize` nem `_org_can` |||||
| Enviar/reenviar convite (W1-14) | quem tem `team.invite` no espaço do convite (cliente) ou na agência (convites da agência); dono da agência em todos; outro cliente 42501/403; anónimo 42501 |||||
| Abrir ou recusar pelo link (W1-14) | qualquer pessoa com o token do email, sem conta; aceitar exige entrar com o email do convite (confirmado); token errado não revela nada |||||
| `team.manage` / `permissions.manage` (ws) | ✓ | dentro do teto | — | — | — | — |
| regras de `grant_set` / `grant_revoke` | só com `permissions.manage`; nunca a si próprio; só a quem está ao seu nível ou abaixo; staff da agência só pelo dono da agência; permitir só o que o próprio tem (negar é sempre possível dentro do teto); motivo obrigatório; prazo até um ano; uma exceção ativa por pessoa e capacidade; nada se apaga (fica `revoked_at`) |||||
| `audit_list` (`/historico`) | com `audit.read` no cliente: dono e admin do cliente, dono da agência; só o histórico desse cliente |||||
| `access_explain` ("porque tem acesso?") | cada pessoa sobre si; sobre outros só com `permissions.manage` no mesmo cliente |||||
| regras de `member_update` / `member_remove` | nunca a si próprio; só quem está ao seu nível ou abaixo; staff da agência só pelo dono da agência; o último dono do cliente não perde o papel nem é removido (exceto pelo dono da agência) |||||
| `settings.manage` / `integrations.manage` | ✓ | ✓ | — | — | — | — |
| ver `/definicoes` (`workspace_settings`) | ✓ | ✓ | ✓ | ✓ | ✓ | — (precisa de `team.read`) |
| ver o logótipo (storage `branding`, URL assinado) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (com `scripts.read`); nunca de outro cliente |

Teto de autoridade: ninguém concede mais do que tem (R-12); um admin do cliente nunca cria papéis da agência nem convida staff da agência (TEAM-02, TEAM-04).

## Mapeamento de hoje

Tempos de gravação (W5-01): escrever com `recording.use`, ler com `recording.use` ou `scripts.read`; a tabela `recording_marks` não tem leitura direta.

O código de equipa `studio_tokens(role='creator')` do Numeiro corresponde a um `contributor` com `scripts.approve`, `scripts.reject` e `recording.confirm` por grant (W2: também `scripts.submit`, para poder reaprovar depois de editar, e `requests.create`, para pedir temas, e `references.read`; W3: `tasks.read` e `calendar.read`, só leitura, porque o código não tem identidade para ser responsável; não tem `scripts.create`, `scripts.delete`, `sources.create` nem `sources.triage`). Na migração W1 cada pessoa que usa o código recebe uma conta individual com esse papel. O código só é desligado depois de a migração estar validada (AGENTS §5).

Pesquisa global (W7): o dono da agência pesquisa todos os clientes da organização; staff só os atribuídos; equipa do cliente só o seu; código de equipa só o cliente do código e nunca pessoas. Cada grupo exige a leitura da entidade nesse cliente e a negação explícita retira o grupo.

Biblioteca de media (W8, ADR-0038): ver e pré-visualizar `media.read` (todos os papéis do cliente); carregar, versão nova, editar, lixo e recuperar, links externos `media.upload`; descarregar `media.download`; partilhar e revogar `media.share`; órfãos e eliminação definitiva `media.manage`; tipos, tamanho, quota e lixo do cliente `media.policy.manage` (só o dono da agência). Código de equipa: nada. Link de partilha: quem tiver o token, só aquela versão, até expirar ou ser revogado. O bucket `media` repete a decisão nas políticas de `storage.objects`: inserir só no caminho pendente da própria pessoa, ler só com autorização de 60 s criada pelas RPCs, apagar só órfãos e eliminação pedida com `media.manage`.

Centro de integrações (W8, ADR-0039): ver as do cliente `integrations.read` (dono, admin e gestor do cliente); testar e revogar `integrations.manage` (dono e admin do cliente); vista da agência `integrations.agency.read` (dono da agência). Colaborador, revisor, leitor, staff sem atribuição e código de equipa: nada. Nunca se expõem tokens nem referências do Vault.

Notificações (W8, ADR-0040): ver as do cliente com `team.read`; mudar com `settings.manage` (contagens de supressão da equipa só aqui). Preferências pessoais e silêncio: a própria pessoa, só nos clientes onde recebe (`tasks.read`), nunca de outra pessoa. Obrigatórias (atribuições, tarefa criada automaticamente ou delegada, guião atribuído, erro de automação para quem tem `agents.configure`, e as que o cliente marcar) não se desligam. Código de equipa: nunca.

Portal do cliente (W8, ADR-0041): entrar com `scripts.read` (staff da agência sem atribuição e outro cliente: 42501). Blocos: guiões `scripts.approve` (rejeitar `scripts.reject`); publicações `calendar.read` com a flag `pub.planning` (aprovar pela política TEAM-10; código de equipa só lê); entregas `scripts.read`, sem valores; desempenho `analytics.read` com a flag `perf.center`; pedidos: ver com `requests.create` ou `sources.read`, criar com `requests.create`. Nunca chegam ao cliente: valores, moeda, pagamento, renovação e notas do contrato, custos, margens, notas internas de saúde e de triagem, flags, permissões, outros clientes.
