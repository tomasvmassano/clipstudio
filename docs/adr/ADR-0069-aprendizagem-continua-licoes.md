# ADR-0069 — Aprendizagem contínua, parte 1: motivo em cada edição e lições versionadas (W10-19)

**Data:** 2026-11-06 · **Estado:** proposto (aguarda o owner: migração por aplicar) · **Requisitos:** PRD §46.2 LRN-01, LRN-02, LRN-03 (restrições de LRN-04..07), FR-17-10, FR-06-04; R-13, R-14; AGENTS §2.1, §2.6, §7.

## Contexto

O motor escreve guiões; a equipa edita, aprova ou rejeita. Até aqui só a rejeição tinha categoria (FR-17-10, W7) e nada ligava a versão do motor à versão aprovada. O PRD (CHG-008) pede: guardar cada par motor → aprovada com um motivo de um toque (LRN-01, opcional mas obrigatório acima de ~30% de texto mudado; aprovar sem editar é sinal positivo), um job diário que propõe lições com evidência (LRN-02) e uma página onde quem tem a capacidade aprova, edita ou rejeita, com cada aprovação a criar uma versão da configuração com voltar atrás (LRN-03), em dois níveis, agência e cliente (LRN-04).

## Decisão

1. **Sinais imutáveis (`lrn_edit_signals`).** Uma linha por edição com motivo (`edit`, ao concluir a edição) e por decisão (`approved`, `approved_unedited`, `changes_requested`, `rejected`), com a versão do motor (a primeira `content_versions` com `created_kind = 'engine'`), a versão humana (a que ficou presa à decisão), os códigos, o texto livre, a distância de edição e a transição. Guiões escritos à mão ficam de fora. Tabela fechada, só de acrescentar, com o mesmo trigger de workspace das versões.
2. **Distância em palavras no servidor.** `_lrn_edit_ratio` = 1 − LCS(palavras) / max(n, m) sobre hooks + corpo + CTA; textos com mais de 360 000 pares de palavras usam a sobreposição por multiconjunto (aproximação, nunca bloqueia). A regra dos 30% (`_lrn_threshold`) decide-se no servidor ao aprovar (22023 `motivo_obrigatorio`); **guardar (autosave) nunca é bloqueado**. Concluir a edição pede o motivo mas "Agora não" não grava nada: a aprovação sem chips nem texto fica registada como "sem motivo".
3. **Chips = categorias do PRD + taxonomia FR-17-10.** Oito códigos fixos do PRD (hook fraco, frase longa, não soa ao cliente, PT-BR, factual, palavra proibida, ritmo, fecho fraco) mais os motivos ativos do cliente para guiões, sem repetir códigos. Cada chip tem um grupo (hook, corpo, CTA, factos, tom, outro) que é também a categoria da lição e diz a que agente se aplica (LRN-05).
4. **Funções novas por cima das de sempre.** `content_decide_learned` chama `content_transition` (ou `content_transition_reasoned` quando há categoria FR-17-10) e grava o sinal na mesma transação; `content_edit_reason` fotografa a cópia de trabalho com `_content_snapshot`. Nenhuma função existente foi reescrita: sem a flag `learn.edits` (fase `owner`) o cartão chama exatamente o que chamava.
5. **Lições e versões separadas da `agent_config_versions`.** `lrn_lessons` (proposta → aprovada/rejeitada; texto proposto imutável, texto final editável só na aprovação; evidência imutável) e `lrn_lesson_versions` (fotografia imutável do conjunto em vigor por âmbito, uma ativa de cada vez). Aprovar, retirar e voltar atrás criam sempre uma versão nova (voltar atrás copia as lições de uma versão anterior: nada é apagado). O motor lê com `worker_lessons` (cliente + agência, `precedence: client`).
6. **Evidência calculada pela base.** O Editor de lições (job `lesson_editor`, motor) recebe os pares da janela (`worker_lesson_pairs`) e grava com `worker_lesson_save` (idempotente por execução e posição) só a categoria, o texto, a justificação, o modelo e as versões de prompt e agente, mais os ids dos sinais citados. A base filtra os ids para este cliente e esta janela, conta as edições e monta até 3 exemplos antes/depois a partir das versões: o texto do motor nunca é evidência, e um id de outro cliente é descartado (sem evidência = recusado).
7. **Dois níveis.** Nível cliente: `learn.lessons.approve` (ws; dono, admin e gestor do cliente, além do dono da agência) e flag `learn.lessons`. Nível agência: `learn.lessons.agency` (org; dono e admin da agência), que a equipa de um cliente nunca tem. A lição da agência nasce por "Propor à agência" a partir de uma lição aprovada de um cliente e guarda só a regra (texto reescrito por quem promove) e a categoria: sem workspace, sem evidência, sem números (R-13, R-14, LRN-04); a origem fica só no histórico do cliente. A secção da agência na página só aparece a quem é equipa da agência.
8. **Agenda.** `lrn_lessons_tick` (pg_cron de hora a hora, só service_role/cron): depois das 06:00 do fuso do cliente, uma execução por dia com os sinais do dia anterior, só onde a flag não está desligada, há configuração ativa e houve sinais. "Propor lições agora" (`lrn_lessons_run`) põe uma execução na fila com os sinais desde a última concluída.

## Alternativas rejeitadas

- **Guardar as lições dentro de `agent_config_versions`:** obrigava a reescrever `agent_config_validate` (campo novo), a ativar uma configuração inteira por cada lição e não serve o nível da agência (não há configuração da organização). As lições são uma parte versionada à parte da configuração dos agentes; LRN-06 atribui métricas por `lrn_lesson_versions.id`.
- **Pedir o motivo em cada gravação automática:** a edição grava de 1,2 em 1,2 s; um diálogo por gravação seria inutilizável. O motivo pede-se ao concluir e ao decidir.
- **Mudar `content_transition` para exigir o motivo:** quebraria o código de equipa, `guiao_update` e o motor; a função nova é opt-in por flag.
- **Uma capacidade com âmbitos ws e org (`lessons.manage`, planeada no registo):** uma chave só não distingue "aprovar no cliente" de "aprovar para todos os clientes"; separar torna impossível a equipa de um cliente aprovar regras da agência por um grant de cliente. As chaves planeadas `lessons.read`/`lessons.manage` foram substituídas por `learn.read` (já existente) e as duas novas.

## Consequências e limites

- O job do motor está em numeiro-engine#27 (`engine/agents/lesson_editor.py`): até esse merge, "Propor lições agora" fica na fila (a página mostra o estado real). Ordem: migração da app, depois o motor.
- LRN-05 (o motor usar as lições e 5-10 pares parecidos) e LRN-06 (medir por versão) por fazer; `worker_lessons` e os ids de versão já estão prontos.
- Sem notificação "há lições por aprovar" (evita mexer em `notifications_kind_check` nesta tarefa).

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_aprendizagem.sql`: tirar o cron e as funções, apagar flags e grants; as tabelas e o tipo `lesson_editor` só num contract posterior, depois de exportar os dados. O código em main não usa nada disto.
