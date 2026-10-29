# ADR-0029 · Campanhas, responsável, plataformas e etiquetas no guião

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** FR-02-03, FR-03-01

## Contexto
O PRD organiza o cliente em campanhas e séries (§3, entidade `projects`) e pede no guião campanha, plataforma, responsável e etiquetas (FR-02-03). A fila do teleprompter tem de se filtrar por campanha e responsável (FR-03-01). Nada disto existia.

## Decisão
- Tabela `projects` por cliente (campanha ou série, ativa ou arquivada, datas opcionais, nome único sem maiúsculas). Fechada à API; lê-se por `projects_list` (`scripts.read`) e gere-se por `project_save` com a capacidade nova `projects.manage` (dono, admin, gestor).
- Colunas novas em `guioes`: `project_id`, `owner_id`, `tags`, `platforms`, com valores por defeito (aditivo). Mudam só por `content_meta_set` (`scripts.edit`): não são texto, por isso não criam versão nem tiram a aprovação. A campanha tem de ser do mesmo cliente e estar ativa; o responsável tem de poder editar guiões nesse cliente; etiquetas normalizadas (minúsculas, sem repetidas, até 10); plataformas instagram, tiktok, youtube. Auditoria antes/depois, evento `script.meta_changed` e notificação `script_assigned` a quem fica responsável.
- `content_owners` lista quem pode ser responsável (com o nome do perfil).
- Teleprompter: `_tp_session_row` passa a trazer os campos novos. O filtro é por dispositivo (guardado no browser), porque a fila é partilhada entre dispositivos e cada pessoa pode querer ver só os seus. Reordenar com filtro troca com o vizinho visível e grava a fila inteira.

## Alternativas rejeitadas
- Campanha e responsável como parte da versão do guião: mudar o responsável tiraria a aprovação.
- Filtro guardado na sessão de gravação: mudaria a fila para todos os dispositivos.
- Responsável pela tarefa de revisão: a tarefa existe só em parte do ciclo; o guião precisa de dono do princípio ao fim.

## Consequências
Os filtros por campanha e responsável ficam disponíveis para o calendário (FR-11-03) e o desempenho (FR-09-04). Gestão completa de campanhas (renomear, arquivar fora do guião) fica para uma página própria. Rollback no fim da migração.
