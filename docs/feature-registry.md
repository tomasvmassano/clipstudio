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
| `team.invite` | Equipa | A | org, ws | ativo | Convidar / Cancelar convite (`invite_member`, `revoke_invitation`) |
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
| `recording.use` | Teleprompter (M03) | B | ws, own | ativo | `/teleprompter`: abrir/entrar na sessão do dia, fila, reordenar, saltar conteúdos e blocos, retoma (`recording_session_open`, `recording_queue_set`, `recording_progress`, `recording_session_close`) |
| `recording.confirm` | Teleprompter | M | ws, own | ativo | Marcar gravado / "Gravaste?"; marcar, escolher, descartar e anotar takes (`take_create`, `take_update`) |
| `sources.read` | Fontes (M04) | B | ws | ativo | `/fontes` (`sources_list`), brief e fontes do guião (`content_context`) |
| `sources.create` | Fontes | M | ws | ativo | Adicionar fonte por URL/manual com dedup (`source_create`) |
| `sources.triage` | Fontes | M | ws | ativo | Selecionar, em triagem, descartar com motivo (`source_update`) |
| `requests.create` | Fontes | B | ws | ativo | Pedir um tema (`talent_request_create`); também no código de equipa |
| `references.read` | Referências (M07) | B | ws | ativo | `/referencias` Biblioteca e Descobrir (`references_list`, `references_discover`); referências no painel do guião; também no código de equipa |
| `references.manage` | Referências | M | ws | ativo | Guardar reel, adicionar por link, classificar, favorito, coleções, arquivar, ligar a fontes (`reference_create`, `reference_update`, `reference_link`) |
| `review.comment` | Revisão (M05) | M | ws, proj | W5 | — |
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
| `costs.read` | Custos (M10) | M | ws | ativo (parcial) | custo e tokens por execução e gasto do dia em `/agentes/configuracao`, limite diário na configuração; módulo Custos completo mais tarde |
| `costs.read_agency` | Custos | A | org | W4 | — |
| `agents.read` | Agentes (M06) | B | ws | ativo | `/agentes`, `/agentes/configuracao` (catálogo, versão ativa, estado do worker, execuções sem custo) |
| `agents.rehearse` | Agentes | M | ws | ativo | Ensaiar a sala |
| `agents.run` | Agentes | A | ws | ativo | `agent_job_enqueue` (Correr agora, idempotente por tipo e dia), `agent_job_cancel`, `agent_job_retry`; executado pelo worker do motor (W4-02), que grava guiões em revisão; dados de pesquisa do motor por cliente (W4-03, ADR-0016) |
| `agents.configure` | Agentes | A | ws | ativo | `agent_config_save` (versão nova validada), `agent_config_activate` (ativar ou voltar atrás), `agent_config_get` |
| `integrations.manage` | Settings (M15) | A | ws | W6 | — |
| `settings.manage` | Settings | A | ws | ativo (parcial) | `/definicoes`: nome, @, fuso, moeda, logótipo (bucket privado `branding`), cor da marca, só gravar aprovados (`workspace_update`, `workspace_settings`); limite de tarefas por pessoa com `tasks.manage`; integrações, notificações, segurança e dados do M15 por fazer |

Regras: ter `edit` não dá `approve` nem `publish` (CAP-04); uma feature flag ligada não concede acesso (CAP-09); toda a key nova entra aqui no mesmo PR em que nasce, senão o CI falha (PRD §34).
