# Registo de capacidades (feature registry)

Fonte: PRD v2.1 CAP-01, CAP-04 e módulos M01–M16. Cada botão, rota, endpoint, job ou export tem uma `capability key` estável. **Capacidade desconhecida = negado** (AGENTS §15). Esta lista alimenta a tabela `feature_registry` no W1 e a consola de permissões (CAP-02).

Risco: **A** alto (publica, apaga, mexe em permissões, dinheiro ou dados de outro), **M** médio (altera conteúdo), **B** baixo (leitura).
Âmbitos: `org` (agência), `ws` (workspace), `proj` (projeto), `own` (só o que lhe está atribuído).
Estado: **ativo** (existe e é verificado no servidor por `authorize()`; também disponível ao código de equipa de transição quando está em `legacy_can`), **W1…W7** (onda do PRD §26 em que entra).

| Key | Módulo | Risco | Âmbitos | Estado | Onde hoje |
| --- | --- | --- | --- | --- | --- |
| `workspaces.read` | Agência | B | org | ativo | `/clientes` (`workspaces_list`): dono vê todos, admin da agência só os atribuídos |
| `workspaces.create` | Agência | A | org | ativo | Novo cliente (`workspace_create`), opcionalmente com a estrutura de outro cliente sem dados privados |
| `workspaces.archive` | Agência | A | org | ativo | Arquivar com motivo e confirmação, recuperar (`workspace_archive`, `workspace_restore`) |
| `team.read` | Equipa (M13) | B | org, ws | ativo | `/equipa` (`workspace_team`), `/permissoes` (só as suas, com o porquê), `/definicoes` |
| `team.invite` | Equipa | A | org, ws | ativo | Convidar / Cancelar convite (`invite_member`, `revoke_invitation`); Enviar e Reenviar (`POST /api/invites/:id/send` → `invitation_issue_link`, W1-14). Página pública `/convite?t=` (`invitation_preview`, `invitation_decline`): sem capacidade, só com o token do email |
| `team.manage` | Equipa | A | org, ws | ativo | `/equipa`: mudar papel, suspender, reativar, remover com reatribuição de tarefas (`member_update`, `member_remove`); dono da agência atribui staff (`agency_staff_assign`) |
| `permissions.manage` | CAP | A | org, ws | ativo | `/permissoes`: por pessoa (o que tem, porquê, permitir/negar com motivo e prazo), por papel, exceções ativas (`permissions_matrix`, `grant_set`, `grant_revoke`, `access_explain`); papéis personalizados por fazer |
| `audit.read` | CAP | M | org, ws | ativo | `/historico` (`audit_list`): quem fez o quê, com antes e depois, filtros por ação, pessoa e período; vista de agência (todos os clientes) por fazer |
| `scripts.read` | Guiões (M02) | B | ws, proj, own | ativo | `/guioes`, `/`, teleprompter |
| `scripts.create` | Guiões | M | ws, proj | ativo | Novo guião, Duplicar (`content_create`, `content_duplicate`); o motor insere direto |
| `scripts.edit` | Guiões | M | ws, proj, own | ativo | Editor por blocos com autosave, restaurar versão (`content_save`, `content_restore_version`) |
| `scripts.submit` | Guiões | M | ws, proj, own | ativo | Enviar para revisão (`content_transition` → `in_review`) |
| `scripts.approve` | Guiões | A | ws, proj | ativo | Validar |
| `scripts.reject` | Guiões | M | ws, proj | ativo | Rejeitar |
| `scripts.delete` | Guiões | A | ws | ativo | Arquivar / recuperar do arquivo (sem eliminação definitiva) |
| `scripts.export` | Guiões | M | ws | ativo | Exportar .txt |
| `recording.use` | Teleprompter (M03) | B | ws, own | ativo | `/teleprompter`: abrir/entrar na sessão do dia, fila, reordenar, saltar conteúdos e blocos, retoma (`recording_session_open`, `recording_queue_set`, `recording_progress`, `recording_session_close`); tempos de gravação (`recording_marks_add`, `recording_timeline`, W5-01) |
| `recording.confirm` | Teleprompter | M | ws, own | ativo | Marcar gravado / "Gravaste?"; marcar, escolher, descartar e anotar takes (`take_create`, `take_update`) |
| `sources.read` | Fontes (M04) | B | ws | ativo | `/fontes` (`sources_list`), brief e fontes do guião (`content_context`) |
| `sources.create` | Fontes | M | ws | ativo | Adicionar fonte por URL/manual com dedup (`source_create`) |
| `sources.triage` | Fontes | M | ws | ativo | Selecionar, em triagem, descartar com motivo (`source_update`) |
| `requests.create` | Fontes | B | ws | ativo | Pedir um tema (`talent_request_create`); também no código de equipa |
| `references.read` | Referências (M07) | B | ws | ativo | `/referencias` Biblioteca e Descobrir (`references_list`, `references_discover`); referências no painel do guião; também no código de equipa |
| `references.manage` | Referências | M | ws | ativo | Guardar reel, adicionar por link, classificar, favorito, coleções, arquivar, ligar a fontes (`reference_create`, `reference_update`, `reference_link`) |
| `review.comment` | Revisão (M05) | M | ws, proj | ativo (guiões, W2-06) | Comentar e responder em guiões (`content_comment_add`); ler com `scripts.read` (`content_comments`, `review_inbox` em `/c/[ws]/revisao`); resolver: autor, `scripts.edit` ou `scripts.approve` (`content_comment_resolve`). Revisão de vídeo em W5 |
| `review.approve` | Revisão | A | ws, proj | W5 | — |
| `media.upload` | Biblioteca (M08) | M | ws, proj | W5 | — |
| `media.download` | Biblioteca | M | ws, proj | W5 | — |
| `media.share` | Biblioteca | A | ws, proj | W5 | — |
| `clipping.create` | Clipping | M | ws, proj | W5 | — |
| `clipping.export` | Clipping | M | ws, proj | W5 | — |
| `tasks.read` | Tarefas (M11, TEAM-06) | B | ws, proj, own | ativo | `/tarefas` (lista, detalhe, comentários, histórico); também o código de equipa |
| `tasks.work` | Tarefas | B | ws, own | ativo | mudar estado/bloquear as tarefas de que é responsável, comentar e mencionar; caixa de entrada `/caixa` |
| `calendar.read` | Calendário (M11) | B | ws | ativo | `/calendario` (dia, semana, mês; guiões, tarefas e sessões); também o código de equipa |
| `calendar.schedule` | Calendário | M | ws, proj | ativo | reagendar guiões (arrastar ou "Mover para"), agendar, tirar da agenda, cancelar, reativar |
| `production.update` | Calendário | M | ws, own | ativo | gravado → em edição → pronto (e voltar); marcar e acrescentar itens da checklist do guião |
| `tasks.manage` | Tarefas | M | ws, proj | ativo | criar, atribuir, prazos, prioridades, dependências, cancelar; automações de handoff (`task_rule_save`); templates (`template_save`, `template_apply`, `template_clone` exige gerir os dois clientes); carga e limite de WIP (`workload`) |
| `publishing.schedule` | Publicação (M12) | A | ws, conta | W6 | — |
| `publishing.publish` | Publicação | A | ws, conta | W6 | — |
| `social_accounts.manage` | Publicação | A | ws | W6 | — |
| `analytics.read` | Desempenho (M09) | B | ws, conta | ativo | `/desempenho`, `/` |
| `dashboard.configure` | Início (M01) | M | ws | ativo | `/` Personalizar: widgets e ordem por função no cliente (`dashboard_layouts_get`, `dashboard_layout_set`, `dashboard_layout_reset`), auditado |
| `dashboard.agency` | Agência | B | org | ativo | `/` (Painel, entrada da equipa da agência; ADR-0018): clientes a que a pessoa tem acesso lado a lado, com totais e comparação (`agency_dashboard`); menu próprio do espaço da agência, com `/clientes` e `/caixa` de todos os clientes |
| `team.read` (org) · `team.invite` (org) · `team.manage` (org) | Equipa da agência | M/A | org | ativo | `/equipa-agencia` (W1-13, ADR-0020): `agency_team`, `agency_invite`, `agency_invite_revoke`, `agency_member_update`; atribuir e tirar de clientes com `agency_staff_assign` e `member_remove` |
| `costs.read` | Custos (M10) | M | ws | ativo (parcial) | custo e tokens por execução e gasto do dia em `/agentes/configuracao`, limite diário na configuração; módulo Custos completo mais tarde |
| `costs.read_agency` | Custos | A | org | W4 | — |
| `agents.read` | Agentes (M06) | B | ws | ativo | `/agentes`, `/agentes/configuracao` (catálogo, versão ativa, estado do worker, execuções sem custo) |
| `agents.rehearse` | Agentes | M | ws | ativo | Ensaiar a sala |
| `agents.run` | Agentes | A | ws | ativo | `agent_job_enqueue` (Correr agora, idempotente por tipo e dia), `agent_job_cancel`, `agent_job_retry`; executado pelo worker do motor (W4-02), que grava guiões em revisão; dados de pesquisa do motor por cliente (W4-03, ADR-0016) |
| `agents.configure` | Agentes | A | ws | ativo | `agent_config_save` (versão nova validada), `agent_config_activate` (ativar ou voltar atrás), `agent_config_get` |
| `dashboard.business.read` | Agência: vista de negócio (BIZ-01..04) | B | org, ws | W1 (CHG-003) | — |
| `finance.read` | Agência: contratos, margem, custos (BIZ-04..06) | A | org, ws | W6 (CHG-003) | — |
| `finance.manage` | Agência: contratos por cliente (BIZ-05) | A | org, ws | W6 (CHG-003) | — |
| `access.preview` | Administração: pré-visualizar como papel (BIZ-07) | M | org, ws | W1 (CHG-003) | — |
| `persona.manage` | Agentes: lista de frases-persona (R-17) | A | ws | W5 (CHG-003) | — |
| `media.ingest` | Ingestão FX3/telemóvel (ING-02..04) | M | ws | W5 (CHG-003) | — |
| `edit.package.run` | Pacote de edição (EDL-01) | M | ws | W5 (CHG-003) | — |
| `styles.manage` | Catálogo de estilos (VAR-02) e preset de edição (EDL-01) | M | ws | ativo (W5-02) | `/c/[ws]/edicao`: criar e gravar estilos (versão nova a cada gravação, `edit_style_save`), ativar, passar a rascunho e arquivar (`edit_style_set_status`), gravar o preset (`edit_preset_save`), começar pelo ponto de partida (`edit_catalog_init`). Ler com `scripts.read` (`edit_catalog`, `edit_style_history`) |
| `projects.manage` | Campanhas e séries (FR-02-03) | M | ws | ativo (W2-07) | Criar, renomear e arquivar campanhas e séries (`project_save`); ler com `scripts.read` (`projects_list`). Campanha, responsável, plataformas e etiquetas do guião com `scripts.edit` (`content_meta_set`, `content_owners`); filtros da fila do teleprompter |
| `performance.read` | Centro de desempenho (PERF) | B | ws, org | W6 (CHG-003) | — |
| `performance.origin.override` | Corrigir origem sistema/externo (R-16) | M | ws | W6 (CHG-003) | — |
| `publishing.approve` | Aprovar publicação de originais (PUB-06) | A | ws, conta | W6 (CHG-003) | — |
| `publishing.republish.approve` | Aprovar republicações (PUB-05/06) | A | ws, conta | W6 (CHG-003) | — |
| `references.dissect` | Referências por link: dissecar e adaptar (REF-01..04) | M | ws, org | W4 (CHG-005) | — |
| `styles.library.manage` | Biblioteca de estilos da agência (REF-05..07) | M | org | W5 (CHG-005) | — |
| `styles.import` | Importar estilo da agência para um cliente (REF-08) | M | org, ws | W5 (CHG-005) | — |
| `integrations.manage` | Settings (M15) | A | ws | W6 | — |
| — (própria pessoa) | Perfil (M14) | todos com conta | user | ativo (W1-15) | `/perfil` e `/c/[ws]/perfil`: nome, fotografia, palavra-passe, verificação em dois passos, fuso, tema, cliente preferido, terminar sessões, histórico de segurança (`profile_update`, `my_security_log`, `security_event`); sem capacidade: cada pessoa só mexe no que é seu |
| `settings.manage` | Settings | A | ws | ativo (parcial) | `/definicoes`: nome, @, fuso, moeda, logótipo (bucket privado `branding`), cor da marca, só gravar aprovados (`workspace_update`, `workspace_settings`); limite de tarefas por pessoa com `tasks.manage`; integrações, notificações, segurança e dados do M15 por fazer |

Regras: ter `edit` não dá `approve` nem `publish` (CAP-04); uma feature flag ligada não concede acesso (CAP-09); toda a key nova entra aqui no mesmo PR em que nasce, senão o CI falha (PRD §34).
