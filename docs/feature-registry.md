# Registo de capacidades (feature registry)

Fonte: PRD v2.1 CAP-01, CAP-04 e módulos M01–M16. Cada botão, rota, endpoint, job ou export tem uma `capability key` estável. **Capacidade desconhecida = negado** (AGENTS §15). Esta lista alimenta a tabela `feature_registry` no W1 e a consola de permissões (CAP-02).

Risco: **A** alto (publica, apaga, mexe em permissões, dinheiro ou dados de outro), **M** médio (altera conteúdo), **B** baixo (leitura).
Âmbitos: `org` (agência), `ws` (workspace), `proj` (projeto), `own` (só o que lhe está atribuído).
Estado: **ativo** (existe e é verificado no servidor por `authorize()`; também disponível ao código de equipa de transição quando está em `legacy_can`), **W1…W7** (onda do PRD §26 em que entra).

| Key | Módulo | Risco | Âmbitos | Estado | Onde hoje |
| --- | --- | --- | --- | --- | --- |
| `workspaces.read` | Agência | B | org | W1 | — |
| `workspaces.create` | Agência | A | org | W1 | — |
| `workspaces.archive` | Agência | A | org | W1 | — |
| `team.read` | Equipa (M13) | B | org, ws | ativo | `/equipa` (`workspace_team`) |
| `team.invite` | Equipa | A | org, ws | ativo | Convidar / Cancelar convite (`invite_member`, `revoke_invitation`) |
| `team.manage` | Equipa | A | org, ws | W1 | — |
| `permissions.manage` | CAP | A | org, ws | W1 | — |
| `audit.read` | CAP | M | org, ws | W1 | — |
| `scripts.read` | Guiões (M02) | B | ws, proj, own | ativo | `/guioes`, `/`, teleprompter |
| `scripts.create` | Guiões | M | ws, proj | W2 | motor (fora da app) |
| `scripts.edit` | Guiões | M | ws, proj, own | ativo | Editar no cartão |
| `scripts.submit` | Guiões | M | ws, proj, own | W2 | — |
| `scripts.approve` | Guiões | A | ws, proj | ativo | Validar |
| `scripts.reject` | Guiões | M | ws, proj | ativo | Rejeitar |
| `scripts.delete` | Guiões | A | ws | W2 | — |
| `scripts.export` | Guiões | M | ws | ativo | Exportar .txt |
| `recording.use` | Teleprompter (M03) | B | ws, own | ativo | `/teleprompter` |
| `recording.confirm` | Teleprompter | M | ws, own | ativo | Marcar gravado / "Gravaste?" |
| `sources.read` | Fontes (M04) | B | ws | ativo | `/ideias` |
| `sources.create` | Fontes | M | ws | W2 | — |
| `sources.triage` | Fontes | M | ws | W2 | — |
| `references.read` | Referências (M07) | B | org, ws | W2 | — |
| `references.manage` | Referências | M | org, ws | W2 | — |
| `review.comment` | Revisão (M05) | M | ws, proj | W5 | — |
| `review.approve` | Revisão | A | ws, proj | W5 | — |
| `media.upload` | Biblioteca (M08) | M | ws, proj | W5 | — |
| `media.download` | Biblioteca | M | ws, proj | W5 | — |
| `media.share` | Biblioteca | A | ws, proj | W5 | — |
| `clipping.create` | Clipping | M | ws, proj | W5 | — |
| `clipping.export` | Clipping | M | ws, proj | W5 | — |
| `tasks.read` | Calendário (M11) | B | ws, proj, own | W3 | — |
| `tasks.manage` | Calendário | M | ws, proj | W3 | — |
| `publishing.schedule` | Publicação (M12) | A | ws, conta | W6 | — |
| `publishing.publish` | Publicação | A | ws, conta | W6 | — |
| `social_accounts.manage` | Publicação | A | ws | W6 | — |
| `analytics.read` | Desempenho (M09) | B | ws, conta | ativo | `/desempenho`, `/` |
| `costs.read` | Custos (M10) | M | ws | W4 | — |
| `costs.read_agency` | Custos | A | org | W4 | — |
| `agents.read` | Agentes (M06) | B | ws | ativo | `/agentes` |
| `agents.rehearse` | Agentes | M | ws | ativo | Ensaiar a sala |
| `agents.run` | Agentes | A | ws | W4 | — |
| `agents.configure` | Agentes | A | ws | W4 | — |
| `integrations.manage` | Settings (M15) | A | ws | W6 | — |
| `settings.manage` | Settings | A | ws | W1 | — |

Regras: ter `edit` não dá `approve` nem `publish` (CAP-04); uma feature flag ligada não concede acesso (CAP-09); toda a key nova entra aqui no mesmo PR em que nasce, senão o CI falha (PRD §34).
