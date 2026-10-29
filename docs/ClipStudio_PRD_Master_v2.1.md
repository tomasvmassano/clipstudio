# ClipStudio — PRD master v2.1 (consolidado + governance + operations)

**Documento canónico · 28 outubro 2026 · Estado: especificação para validação**

**Nota:** A Parte I preserva a especificação detalhada da v1.1; a Parte II complementa e, em caso de conflito, prevalece nas decisões explicitamente assinaladas. O PDF Viral Engine é a origem do preset Numeiro, não uma limitação multi-cliente.

**Data:** 28 outubro 2026

**Estado:** especificação proposta para validação e implementação

**Modelo:** agência com equipa transversal + workspaces de clientes com equipas próprias e dados isolados

**Base de evidência:** inspeção estática de `clipstudio-main.zip` e auditoria anterior; **não** constitui teste E2E do deploy ou confirmação das políticas SQL de produção.

## 0. Resumo executivo

O ClipStudio 2.0 será uma plataforma interna multi-cliente para transformar fontes e referências em guiões, aprovação, gravação, ativos, publicação, medição e aprendizagem. A aplicação deve suportar múltiplos workspaces independentes, um utilizador em vários workspaces e colaboração com controlo de acesso. O escopo é completo; a entrega é faseada por dependências técnicas, não por redução arbitrária de funcionalidades.

### Objetivos mensuráveis

- 100% das rotas visíveis resolvem corretamente; nenhum botão visível é inerte.
- 0 acessos cruzados entre workspaces nos testes de autorização.
- 100% das mutações críticas registam autor, data, workspace e versão.
- Fluxo Fonte → Guião → Aprovação → Gravação → Biblioteca → Publicação → Desempenho demonstrado em staging com dados reais de teste.
- Testes automatizados de autorização, estados de erro, fluxos principais e regressão obrigatórios para release.

### Fora de âmbito desta especificação

Billing SaaS self-service e marketplace público de agentes; não há exclusão de gestão de custos por workspace. Integrações que não disponibilizem APIs autorizadas terão fallback manual. A disponibilidade de métricas específicas varia por plataforma.

## 1. Estado atual verificado no repositório

- Stack: Next.js 16, React 19, TypeScript, Supabase JS; `package.json` sem framework de testes declarada.
- Rotas existentes: `/`, `/guioes`, `/teleprompter`, `/ideias`, `/desempenho`.
- Entradas na navegação sem rota implementada: `/revisao`, `/agentes`, `/referencias`, `/biblioteca`, `/custos` (`src/components/app-shared.tsx`).
- `src/lib/supabase.ts` define `DEFAULT_CLIENT = "numeiro"`; não equivale a isolamento multi-tenant.
- `src/lib/data.ts`: `fetchGuioes` filtra `client_id`, mas `fetchIdeas` não filtra workspace; `updateGuiao` usa RPC `guiao_update`; autenticação atual usa código de equipa e token em localStorage.
- `src/lib/types.ts`: `Guiao.status` apenas `aprovado | rejeitado`; `Guiao` tem `validado`, `gravado`, `hooks`, `corpo`, `history`; `Idea` tem `take_numeiro`. O esquema precisa de migração compatível e generalização.
- `src/components/use-guioes.ts` tem default de cliente fixo. A autorização SQL/RLS e implementação de RPCs não estão incluídas no ZIP e exigem inspeção em ambiente seguro.
- `src/components/app-search.tsx` tem pesquisa visual sem pesquisa funcional; links `#` foram identificados na auditoria.

## 2. Arquitetura organizacional e decisões de produto

**Decisão vinculativa:** existem duas equipas distintas: (A) equipa da agência, que pode colaborar com vários clientes usando uma única conta; (B) equipa própria de cada cliente, cujos membros têm acesso exclusivamente ao respetivo workspace. O sistema tem **uma identidade global por pessoa**, não dois sistemas de autenticação.

### Hierarquia e propriedade

`Agency Organization → Client Workspaces → Projects/Campaigns → Content/Tasks/Assets`. A organização da agência é a entidade operadora; cada cliente é um workspace com equipa, dados, definições, agentes, integrações e métricas isolados. Uma pessoa interna da agência pode pertencer a múltiplos workspaces mediante atribuição explícita, além dos privilégios administrativos limitados ao âmbito da agência. A equipa de cada cliente não obtém acesso aos restantes workspaces nem ao painel interno da agência.

**Definições distintas:**

- `affiliation_type` = `agency_staff` ou `client_staff` (origem/afiliação organizacional).
- `job_title` = clipper, editor, videógrafo, social media manager, estratega, copywriter, produtor, gestor de projeto etc. (especialidade, sem concessão automática de permissões).
- `role` = autoridade RBAC no âmbito agency/workspace/project.
- `grants` = permissões específicas e exceções auditadas. Não inferir autoridade a partir de cargo ou de um campo de UI.

**Regra de âmbito:** um `agency_staff` sem atribuição a um workspace não acede automaticamente aos conteúdos desse cliente, exceto agência Owner e contas administrativas explicitamente autorizadas com escopo global e auditoria. O acesso global da agência nunca se transfere para `client_staff`. Afiliação e permissões são verificadas a cada pedido, mesmo quando um utilizador guarda URLs ou muda de workspace.

### Regras globais

R-01. Toda a leitura/escrita de dados de negócio deve ser autorizada no servidor com base na identidade, pertença organizacional, atribuição ao workspace, função e escopo do recurso; `workspace_id` do browser nunca é prova de autorização.

R-02. Todas as tabelas de negócio multi-tenant têm `workspace_id`, FK e RLS; storage, pesquisa e realtime aplicam a mesma fronteira.

R-03. Uma conta de agência pode participar em N workspaces com funções diferentes; a conta do cliente pertence a um único workspace de cliente no produto 1.1. Não permitir convites cruzados por administradores do cliente.

R-04. Dashboard global da agência agrega apenas workspaces autorizados; o cliente vê apenas o seu.

R-05. Todas as ações críticas são auditáveis com ator, afiliação, âmbito, recurso, data e resultado; nunca registar tokens.

R-06. Aprovação editorial e progresso de produção são estados separados; versões aprovadas são imutáveis.

R-07. Falhas de rede não podem aparentar sucesso; ações assíncronas apresentam estado e retry seguro.

R-08. Operações externas e publicações têm chave de idempotência.

R-09. Timestamps UTC e timezone por workspace; soft-delete com recuperação controlada.

R-10. Conteúdo externo e de IA é dado não confiável; PT-PT inicial com internacionalização preparada.

R-11. Desativar uma conta, retirar atribuição ou reduzir permissões revoga imediatamente acesso de API, pesquisa, realtime e media protegida; URLs assinados existentes são de curta duração e a revogação imediata de URLs já emitidos exige proxy de acesso ou rotação de objetos.

R-12. Uma pessoa não pode elevar os próprios privilégios; convites, mudanças de função e delegações obedecem a um teto de autoridade e segregação de funções.

R-13 (CHG-001). A app tem dois espaços: o **espaço da agência** (casa da equipa da agência) e o **espaço do cliente** (onde se entra a partir da agência). Cada funcionalidade nova declara a que espaço pertence (agência, cliente ou ambos) e o âmbito dos dados que mostra. Nada do espaço da agência é visível a `client_staff` nem ao código de equipa.

R-14 (CHG-001). Isolamento entre clientes nos convites: um convite feito pela agência para um cliente, ou feito pela equipa de um cliente para a sua equipa, dá acesso **só** a esse cliente. A equipa de um cliente nunca vê o painel da agência, a lista de clientes, nem dashboards, métricas, conteúdos, tarefas ou presença de outro cliente. A equipa de um cliente só convida para o seu cliente, nunca staff da agência e nunca acima do seu papel. Uma pessoa da equipa de um cliente pertence a um só cliente (R-03): um convite de cliente para quem já está ativo noutro cliente é cancelado na aceitação, sem erro para quem convidou (para não revelar que o email pertence a outro cliente), e fica no histórico.

### Espaços da agência e do cliente (CHG-001, vinculativo)

**Espaço da agência.** Endereços sem cliente (`/`, `/clientes`, `/caixa`, …). A equipa da agência entra sempre no **Painel da agência** (`/`). Menu: Painel (todos os clientes a que a pessoa tem acesso, lado a lado, com totais e comparação), Clientes (criar, editar, arquivar, atribuir staff), Caixa de entrada de todos os clientes, Equipa da agência (staff, papéis, em que clientes trabalha), Calendário de todos os clientes, Custos da agência, Histórico da agência e Definições da agência. Peças previstas: Alertas dos clientes (agentes falhados, guiões parados, limite de custo, contas sociais expiradas), Carga da equipa da agência por cliente, Pedidos dos clientes numa fila, Modelos da agência (agentes, produção, automações) para novos clientes e Relatórios para enviar a cada cliente.

**Espaço do cliente.** O cliente aberto vive no endereço: `/c/<cliente>/<página>`. Menu operacional (Início, Caixa do cliente, Guiões, Tarefas, Calendário, Teleprompter, Fontes, Referências, Desempenho, Agentes) e **Administração do cliente** (equipa, permissões, histórico e definições desse cliente), que fica sempre dentro do cliente e não no espaço da agência. A equipa da agência vê "← Agência" e um seletor para saltar para outro cliente autorizado.

**Regras.** O endereço nunca é prova de autorização (R-01): cada leitura e escrita volta a verificar identidade, cliente e capacidade no servidor. Um cliente no endereço a que a pessoa não tem acesso, ou que não existe, mostra a mesma mensagem. A equipa de um cliente e o código de equipa entram direto no seu cliente. Links antigos sem cliente redirecionam para o último cliente aberto, mantendo os parâmetros.

## 3. Papéis, equipas e permissões

**Afiliação não é role.** `agency_owner`, `agency_admin`, `agency_manager`, `agency_member` são papéis da organização; `workspace_owner`, `workspace_admin`, `manager`, `contributor`, `reviewer`, `viewer` são papéis do workspace. O mesmo colaborador interno pode ser `manager` no Cliente A e `contributor` no Cliente B. O cliente só gere membros da própria equipa e nunca cria privilégios da agência.

| Ação | Agency Owner | Agency Admin | Agency Staff atribuído | Client Admin | Client Staff |
|---|---|---|---|---|---|
| Criar/arquivar workspaces de clientes | Sim | Configurável | Não | Não | Não |
| Consultar dashboard global de agência | Sim | Sim, com escopo | Só clientes atribuídos | Não | Não |
| Ver conteúdo de workspace | Sim, auditado | Só se autorizado | Só se atribuído | Sim, do próprio cliente | Só autorizado no cliente |
| Convidar colaboradores internos | Sim | Se delegado | Não | Não | Não |
| Convidar membros da equipa do cliente | Sim | Se delegado | Se delegado no cliente | Sim, dentro de limites | Não por defeito |
| Atribuir colaboradores da agência a clientes | Sim | Se delegado | Não | Não | Não |
| Editar/aprovar/publicar | Segundo políticas e grants | Segundo grants | Segundo grants do workspace | Segundo grants do cliente | Segundo grants do cliente |
| Consultar custos globais da agência | Sim | Se delegado | Não por defeito | Não | Não |
| Consultar custos do próprio workspace | Sim | Se delegado | Se autorizado | Se autorizado | Se autorizado |
| Alterar regras de segurança/ownership | Sim | Limitado | Não | Apenas regras delegadas do próprio cliente | Não |

**Matriz de capacidades por especialidade (defaults configuráveis, não autorizações implícitas):**

| Especialidade | Módulos iniciais sugeridos | Ações típicas |
|---|---|---|
| Clipper | Clipping, Biblioteca, Tarefas, Revisão, Desempenho | Criar clips, enviar versões |
| Social Media Manager | Calendário, Publicações, Biblioteca, Desempenho | Preparar posts, agendar; publicar só com grant |
| Videógrafo | Produção, Guiões, Teleprompter, Tarefas | Consultar shot lists, marcar takes |
| Editor | Edição, Biblioteca, Revisão, Tarefas | Submeter versões e correções |
| Estratega | Fontes, Referências, Guiões, Desempenho | Briefings, estratégia, recomendações |
| Copywriter | Fontes, Guiões, Referências, Tarefas | Criar, editar e submeter guiões |
| Gestor de projeto | Dashboard, Tarefas, Calendário, Revisão | Atribuir, acompanhar e desbloquear |
| Diretor criativo | Guiões, Revisão, Referências | Aprovar quando autorizado |
| Gestor de cliente | Dashboard, Calendário, Relatórios, Revisão | Acompanhar entregas e aprovações |

**Política de avaliação:** `allow` só quando identidade ativa ∧ membership ativo ∧ workspace autorizado ∧ grant suficiente ∧ recurso dentro do escopo ∧ ausência de deny explícito; por defeito `deny`. Restrições de projeto e recurso prevalecem sobre a visibilidade genérica do módulo. Cada mutação sensível verifica autorização novamente no servidor; UI só reflete as capacidades devolvidas pela API.

## 4. Estados e ciclo editorial

- Editorial: `draft → in_review → changes_requested → in_review → approved` ou `rejected`; `archived` permitido mediante regras.
- Produção: `not_started → scheduled → recording → recorded → editing → ready → published` ou `cancelled`.
- Revisão de media: `not_submitted → pending → changes_requested/approved/rejected`.
- Publicação: `draft → scheduled → processing → published` ou `failed/cancelled`.
- A aprovação associa-se ao `content_version_id`, não só ao ID do conteúdo; editar versão aprovada cria revisão nova.
- Conteúdos rejeitados não entram por defeito na fila do teleprompter; a aprovação pode ser obrigatória para gravação/publicação por workspace.

## 5. Requisitos funcionais por módulo

Cada requisito abaixo tem ID único, prioridade de entrega (P0 crítico, P1 essencial, P2 evolução), regra funcional e aceitação verificável. Salvo indicação, os requisitos descritos são **incluídos no produto 1.0**.

### M01 — Início / Dashboard

**Rota:** `/c/<cliente>` (Início do cliente) e `/` (Painel da agência, R-04, R-13). **Objetivo:** Visão executiva e operacional por workspace; na agência, a mesma visão para todos os clientes autorizados.

**FR-01-01 [P0]** KPIs com período configurável: fontes recebidas, guiões criados, pendentes de aprovação, aprovados, gravados, publicados, views, engagement, custos e produtividade.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-01-02 [P0]** Widgets configuráveis por função e por workspace; comparação temporal e explicação das métricas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-01-03 [P1]** Minha fila: tarefas, aprovações, gravações, prazos e alertas; clique abre objeto correspondente.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-01-04 [P1]** Calendário editorial compacto e atividade recente com ator e timestamp.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-01-05 [P1]** Ações rápidas criar fonte, guião, projeto e tarefa; cada ação respeita permissões.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-01-06 [P2]** Estados vazios explicativos, loading, erro/retry, filtros persistentes por utilizador.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M02 — Guiões

**Rota proposta:** `/guioes`. **Objetivo:** Editor editorial e origem do conteúdo.

**FR-02-01 [P0]** CRUD de guiões, duplicação, arquivo, recuperação e eliminação com confirmação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-02 [P0]** Editor por blocos ordenados: Hook 1..N, Body, CTA, notas e comentários; autosave com indicador.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-03 [P1]** Campos: título, cliente/workspace, campanha, tema, formato, plataforma, responsável, datas, tags e fontes relacionadas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-04 [P1]** Estados editoriais rascunho, em revisão, alterações pedidas, aprovado, rejeitado; estados de produção independentes.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-05 [P1]** Enviar para revisão, aprovar/rejeitar/pedir alterações com comentário obrigatório na rejeição; bulk actions autorizadas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-06 [P2]** Histórico de versões com diff e restauro, conflitos de edição e autoria.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-07 [P2]** Filtros, pesquisa, ordenação, vistas guardadas, exportação e impressão.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-02-08 [P2]** IA: sugestões de hooks, CTA e reformulação; nunca sobrescrever versão sem confirmação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M03 — Teleprompter

**Rota proposta:** `/teleprompter`. **Objetivo:** Execução de sessões de gravação.

**FR-03-01 [P0]** Fila de gravação por data, campanha e responsável, apenas conteúdos elegíveis; reordenar e saltar blocos.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-02 [P0]** Blocos identificados Hook 1, Hook 2, Body, CTA e personalizados; seleção e repetição de takes.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-03 [P1]** Espelhamento horizontal e vertical independentes; velocidade, fonte, line-height, margens e contraste.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-04 [P1]** Play/pause, scroll manual, fullscreen por gesto, atalhos configuráveis, controlo remoto compatível.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-05 [P1]** Guardado de preferências por utilizador e dispositivo; bloqueio de suspensão quando suportado.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-06 [P2]** Marcar take gravado, adicionar notas e anexar ficheiro, sem alterar estado editorial automaticamente.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-03-07 [P2]** Fallback de fullscreen/wake lock, falhas de gravação visíveis, estado offline e retoma segura.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M04 — Fontes / Notícias

**Rota proposta:** `/fontes`. **Objetivo:** Ingestão, curadoria e triagem.

**FR-04-01 [P0]** CRUD de fontes com URL, título, origem, data, idioma, autor, tags, categoria, resumo e anexo.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-02 [P0]** Adicionar manualmente, por URL, RSS e integrações autorizadas; rastreio de data de ingestão e proveniência.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-03 [P1]** Filtros por categoria, tema, fonte, idioma, data, estado e pesquisa full-text.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-04 [P1]** Estados nova, triagem, selecionada, utilizada, descartada; favoritos, duplicados e expiração.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-05 [P1]** Resumo por IA com referências à fonte, classificação de relevância e ângulos sugeridos.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-06 [P2]** Converter fonte em guião ou ligar múltiplas fontes a um guião; evitar cópias não autorizadas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-04-07 [P2]** Feed personalizado por workspace e utilizador; configurações de tópicos e exclusões.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M05 — Revisão

**Rota proposta:** `/revisao`. **Objetivo:** Aprovação editorial e de media.

**FR-05-01 [P0]** Inbox de revisão com filtros por tipo, responsável, estado, prioridade e deadline.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-02 [P0]** Revisão de guião com comentários contextuais e decisões versionadas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-03 [P1]** Revisão de vídeo com player, comentários por timestamp, anotações e histórico.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-04 [P1]** Aprovar, rejeitar ou pedir alterações com motivo e notificações.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-05 [P1]** Fluxos configuráveis de aprovação por workspace/projeto; responsáveis e prazos.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-06 [P2]** Comparação entre versões e bloqueio de publicação sem aprovação exigida.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-05-07 [P2]** Registo de decisões e auditoria de alterações após aprovação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M06 — Agentes IA

**Rota proposta:** `/agentes`. **Objetivo:** Orquestração e configuração de IA.

**FR-06-01 [P0]** Catálogo de agentes com função, versão, modelo, prompt, ferramentas, permissões e limites.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-02 [P0]** Configuração por workspace: temas, tom, idioma, formatos, referências, restrições e metas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-03 [P1]** Execução manual/agendada, progresso, logs, erros, retry e cancelamento.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-04 [P1]** Versionamento de prompts/configurações, testes antes de ativar, rollback e auditoria.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-05 [P1]** Custos, tokens, latência e qualidade por execução/agente.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-06 [P2]** Aprovação humana configurável antes de criar guião ou publicar resultado; bloqueio de dados sensíveis.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-06-07 [P2]** Biblioteca de templates de agentes, duplicação entre workspaces sem copiar dados privados.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M07 — Referências

**Rota proposta:** `/referencias`. **Objetivo:** Biblioteca de inspiração e benchmarking.

**FR-07-01 [P0]** Guardar referências por URL, upload ou captura autorizada; metadados e autoria.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-07-02 [P0]** Classificação por formato, estilo, narrativa, hook, duração, idioma e tags.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-07-03 [P1]** Filtros, favoritos, coleções e pesquisa.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-07-04 [P1]** Transcrição e análise de estrutura quando tecnicamente e legalmente permitido.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-07-05 [P1]** Ligar referências a fontes e guiões; manter atribuição e URL original.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-07-06 [P2]** Indicadores de desempenho apenas quando obtidos por API ou fonte autorizada, com timestamp.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M08 — Biblioteca

**Rota proposta:** `/biblioteca`. **Objetivo:** Gestão de ativos produzidos.

**FR-08-01 [P0]** Upload de vídeo, áudio, imagens, thumbnails, legendas e documentos com progresso e retry.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-08-02 [P0]** Pastas/coleções lógicas por campanha, projeto, formato e estado; pesquisa e tags.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-08-03 [P1]** Pré-visualização, download, links temporários e permissões de partilha.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-08-04 [P1]** Versionamento, substituição, histórico e associação a guião/take/publicação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-08-05 [P1]** Controlo de tipos, tamanho, antivírus quando aplicável, quotas e retenção.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-08-06 [P2]** Eliminação reversível, gestão de órfãos e custos de armazenamento.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M09 — Desempenho

**Rota proposta:** `/desempenho`. **Objetivo:** Medição de resultados e aprendizagem.

**FR-09-01 [P0]** Conectar contas de plataformas com OAuth quando suportado e gerir sincronização.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-02 [P0]** Métricas por conteúdo e período: views, alcance, interações, retenção, seguidores e conversões disponíveis.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-03 [P1]** Definições consistentes por plataforma; mostrar indisponibilidade e data da última atualização.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-04 [P1]** Comparação de conteúdos, hooks, temas, formatos, campanhas e responsáveis.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-05 [P1]** Rankings, gráficos, exportação e relatórios programados.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-06 [P2]** Atribuir métricas ao conteúdo publicado e ao guião original; evitar dupla contagem.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-09-07 [P2]** Erros de integração, token expirado e sincronização parcial com retry.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M10 — Custos

**Rota proposta:** `/custos`. **Objetivo:** Visibilidade financeira da produção.

**FR-10-01 [P0]** Consumo de IA por agente, modelo, execução e workspace.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-10-02 [P0]** Armazenamento, processamento e integrações com custos rastreáveis.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-10-03 [P1]** Custos manuais opcionais por produção, freelancer e projeto; moeda base configurável.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-10-04 [P1]** Orçamentos, limites rígidos/soft, alertas e autorização para ultrapassar quota.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-10-05 [P1]** Custo por guião, vídeo e publicação; tendência mensal e exportação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-10-06 [P2]** Diferenciar custo estimado de custo confirmado e guardar taxa de câmbio utilizada.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M11 — Calendário / Produção

**Rota proposta:** `/calendario`. **Objetivo:** Planeamento transversal.

**FR-11-01 [P0]** Calendário editorial por dia, semana e mês; drag and drop com validação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-11-02 [P0]** Tarefas, gravações, revisões, publicações, responsáveis, deadlines e dependências.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-11-03 [P1]** Vistas por equipa, plataforma, campanha e estado; conflitos e atrasos destacados.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-11-04 [P1]** Templates de produção, checklist por conteúdo e notificações.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-11-05 [P1]** Links para guiões, ficheiros, revisões e publicações.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M12 — Publicação

**Rota proposta:** `/publicacoes`. **Objetivo:** Distribuição e rastreio.

**FR-12-01 [P0]** Preparar legendas, hashtags, thumbnail, plataformas e datas por variante.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-12-02 [P0]** Publicação manual com registo de URL e timestamp; agendamento por API quando autorizado.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-12-03 [P1]** Fila com estados agendado, a publicar, publicado, falhou, cancelado.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-12-04 [P1]** Retry idempotente para evitar posts duplicados; falhas e limites de API visíveis.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-12-05 [P1]** Validação de aprovação e requisitos de formato antes de agendar.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-12-06 [P2]** Permissões de publicação separadas de edição e aprovação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M13 — Equipa

**Rota proposta:** `/equipa`. **Objetivo:** Utilizadores, papéis e acesso.

**FR-13-01 [P0]** Convidar por email com expiração, aceitar/recusar, reenviar e revogar convite.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-13-02 [P0]** Funções Owner, Admin, Editor, Reviewer, Viewer com permissões por recurso e ação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-13-03 [P1]** Múltiplos workspaces por utilizador, papéis independentes e mudança de contexto segura.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-13-04 [P1]** Desativar membro, transferir propriedade, impedir remoção do último Owner.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-13-05 [P1]** Auditoria de convites, alterações de papéis e ações críticas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-13-06 [P2]** Gestão de grupos/equipas e atribuição de tarefas, sem permissões implícitas.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M14 — Perfil

**Rota proposta:** `/perfil`. **Objetivo:** Identidade e preferências individuais.

**FR-14-01 [P0]** Nome, avatar, email verificado, password reset e MFA quando disponível.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-14-02 [P0]** Idioma, timezone, tema, notificações e preferências do teleprompter.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-14-03 [P1]** Sessões/dispositivos ativos, terminar sessões e histórico de segurança.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-14-04 [P1]** Lista de workspaces e seleção de workspace preferido.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-14-05 [P1]** Exportação dos próprios dados e pedido de eliminação conforme política.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M15 — Settings

**Rota proposta:** `/settings`. **Objetivo:** Configuração do workspace.

**FR-15-01 [P0]** Geral: nome, logótipo, idioma, timezone, moeda e branding.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-02 [P0]** Conteúdo: categorias, formatos, estados, templates, regras de aprovação e checklists.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-03 [P1]** Integrações: conectar, testar, renovar, revogar e ver saúde de cada integração.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-04 [P1]** IA: prompts, modelos, limites, permissões e política de aprovação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-05 [P1]** Notificações: canais, eventos e preferências organizacionais.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-06 [P2]** Segurança: MFA obrigatória opcional, políticas de sessão, logs, exportação e retenção.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-07 [P2]** Dados: importação/exportação, soft-delete, recuperação e política de eliminação.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-15-08 [P2]** Administração de workspace: transferir propriedade, arquivar e eliminar com confirmação reforçada.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

### M16 — Pesquisa e notificações

**Rota proposta:** `/pesquisa; /notificacoes`. **Objetivo:** Serviços globais.

**FR-16-01 [P0]** Pesquisa global com controlo de acesso em todas as entidades, sugestões e resultados agrupados.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-16-02 [P0]** Atalho de teclado, pesquisa por título/tag/ID e estado vazio.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-16-03 [P1]** Inbox de notificações, marcar como lida, deep links e preferências.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-16-04 [P1]** Menções, atribuições, aprovações, falhas de automação e integrações.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

**FR-16-05 [P1]** Evitar notificação de dados de outros workspaces e impedir vazamento em resultados.

**Aceitação:** dado um utilizador autorizado no workspace A, a operação produz o estado/resultado descrito, persiste após refresh, apresenta erro recuperável quando a dependência falha e não revela nem modifica dados do workspace B.

## 5A. Requisitos adicionais — equipas duplas e operação multidisciplinar

Os requisitos seguintes complementam e, em caso de conflito, prevalecem sobre os requisitos genéricos de Equipa, Perfil, Settings, Dashboard, Calendário e Biblioteca descritos acima.

**TEAM-01 [P0] — Identidade única.** Um utilizador entra uma vez e tem um `auth_user_id` estável.

**Aceitação:** login da agência com acesso aos clientes A e B alterna entre ambos sem novo login; logout invalida a sessão; conta do cliente A não vê B.

**TEAM-02 [P0] — Dois diretórios de equipa.** `/agency/team` lista staff interno; `/w/[workspace]/settings/team` lista membros do cliente e colaboradores da agência atribuídos, identificados com etiquetas distintas.

**Aceitação:** Client Admin só pode convidar e gerir `client_staff` do seu cliente, não consegue editar `agency_staff` nem elevar autoridade.

**TEAM-03 [P0] — Atribuições da agência.** Agency Owner/Admin delegado atribui membros internos a um ou vários clientes com papel e grants específicos por cliente.

**Aceitação:** remover atribuição a B retira B do seletor, dashboard, API, pesquisa, notificações e ficheiros, mantendo A intacto.

**TEAM-04 [P0] — Restrição de membros do cliente.** Convites client-side ficam vinculados ao workspace emissor e não podem aceitar outro workspace por alteração de payload.

**Aceitação:** testes negativos com URL, API, websocket, search e storage devolvem acesso negado em B.

**TEAM-05 [P0] — Matriz de permissões configurável.** Suportar permissões `module.action` e escopos `workspace/project/assigned_only`; modelos por profissão são apenas sugestões.

**Aceitação:** um editor só altera itens atribuídos quando `assigned_only`; pode consultar módulo sem editar quando grant read-only.

**TEAM-06 [P0] — Tarefas e responsáveis.** Cada tarefa tem workspace, projeto, responsável, criador, prioridade, estado, deadline, dependências, comentários e histórico.

**Aceitação:** não é possível atribuir tarefa a utilizador sem acesso ao projeto; mudança de responsável notifica ambos; tarefa concluída permanece auditável.

**TEAM-07 [P1] — Dashboard por âmbito.** Agency Staff tem vista `Os meus clientes` e `As minhas tarefas`; Client Staff entra diretamente no cliente.

**Aceitação:** agregados globais nunca incluem clientes não autorizados; filtros persistem por utilizador e não vazam caches entre clientes.

**TEAM-08 [P1] — Equipas funcionais e capacidade.** Criar equipas de Produção, Pós-produção, Clipping, Estratégia, Social e Copy; gerir carga por responsável, estado e prazo.

**Aceitação:** capacidade apresenta tarefas pendentes por pessoa/cliente e respeita acesso a projetos privados.

**TEAM-09 [P1] — Workflow adaptável por cliente.** Definir etapas, aprovadores, SLA e ações automáticas por tipo de conteúdo, incluindo clipping e vídeo longo.

**Aceitação:** fluxo de Cliente A não altera Cliente B; transições não autorizadas são rejeitadas; histórico imutável.

**TEAM-10 [P1] — Aprovações sem conflito.** Aprovação pode exigir diretor criativo, cliente ou ambos; política opcional impede autoaprovação.

**Aceitação:** decisão guarda versão, ator, função e timestamp; nova versão exige nova aprovação quando configurado.

**TEAM-11 [P1] — Freelancer/guest.** Acesso temporário limitado a projetos ou tarefas, com expiração e revogação.

**Aceitação:** após expirar, não acede a conteúdo, uploads nem downloads; histórico mantém autoria.

**TEAM-12 [P1] — Notificações direcionadas.** Atribuições, menções, aprovações, alterações e prazos notificam apenas utilizadores autorizados.

**Aceitação:** remover membership impede novas notificações e invalida deep links anteriores.

**TEAM-13 [P1] — Separação de settings.** `/agency/settings` controla políticas globais e clientes; `/w/[workspace]/settings` controla opções delegadas do cliente; `/profile` controla preferências pessoais.

**Aceitação:** Client Admin não altera política global ou permissões superiores.

**TEAM-14 [P1] — Produção e edição.** Sessões, shot lists, ficheiros brutos, versões de edição, clips e entregas são associados a tarefas e conteúdos.

**Aceitação:** videógrafo entrega material → editor recebe tarefa → envia versão → reviewer aprova → social manager agenda; todas as transições auditáveis.

**TEAM-15 [P1] — Transferência e offboarding.** Remover um membro solicita reatribuição de tarefas pendentes e mantém versões e comentários.

**Aceitação:** sem tarefas órfãs invisíveis; propriedade de conteúdo permanece no workspace.

**TEAM-16 [P0] — Segurança e testes de autorização.** Testar matriz de agência vs cliente em leitura, escrita, exportação, RPC, realtime, storage, search e jobs.

**Aceitação:** nenhuma combinação de identidade/token/ID externo permite acesso cruzado ou elevação de privilégios.

### Casos-limite obrigatórios

- Staff interno com dois clientes e papéis distintos; suspensão apenas num deles.
- Client Admin tenta convidar um colaborador da agência e tenta atribuir papel Owner global.
- Dois membros com o mesmo cargo profissional mas permissões diferentes.
- Utilizador interno sem clientes atribuídos: dashboard vazio, sem acesso a conteúdo.
- Transferência de tarefas de membro removido e manutenção de histórico.
- Recurso partilhado por link: acesso exige autorização atual, mesmo após expiração/revogação do membership.
- Mudança de workspace durante upload, job de IA ou publicação: o job mantém o workspace original e valida autorização no momento da submissão.

## 6. Fluxos end-to-end obrigatórios

**FL-01 Onboarding:** criar conta → verificar email → criar workspace → escolher timezone/moeda → convidar equipa → aceitar convite → entrar com função correta.

**Aceitação:** convites expirados/revogados falham; um utilizador de B não vê A.

**FL-02 Curadoria editorial:** adicionar fonte → classificar → associar referência → criar guião → editar hooks/body/CTA → submeter → comentar → pedir alterações → nova versão → aprovar.

**Aceitação:** comentários e histórico preservados; aprovação refere a versão correta.

**FL-03 Produção:** guião aprovado → calendarizar → abrir fila → teleprompter → gravar múltiplos takes → associar media → revisão de vídeo → aprovado.

**Aceitação:** trocar data não perde seleção nem associa take ao guião errado.

**FL-04 Publicação:** vídeo aprovado → preparar variantes → validar conta e permissões → agendar/publicar → registar URL/ID externo → sincronizar métricas.

**Aceitação:** retry não publica duplicado e falha de API não marca como publicado.

**FL-05 IA:** fonte → agente gera proposta → revisão humana → criar versão de guião → registar custo e proveniência.

**Aceitação:** IA não publica nem aprova automaticamente sem política explícita; falha/cancelamento não gera conteúdo parcial aprovado.

**FL-06 Multi-workspace:** membro de A e B alterna contexto → pesquisa, dashboard, notificações, ficheiros, analytics e custos refletem apenas workspace selecionado.

**Aceitação:** testes negativos com ID manipulado, chamadas diretas e canais realtime.

**FL-07 Offboarding:** remover membro → revogar sessões/permissões → preservar autoria e audit log → bloquear uploads e downloads protegidos.

**Aceitação:** URLs temporárias respeitam expiração; acesso API recusado após revogação.

**FL-08 Recuperação:** falha de rede durante edição → estado de erro → recuperação do rascunho e retry → ausência de duplicados.

**Aceitação:** versão aprovada não é silenciosamente sobrescrita.

## 7. Modelo de dados lógico proposto

| Entidade | Campos principais | Relações / regras |
|---|---|---|
| users / auth.users | id, email, name, avatar, locale | Identidade global via Supabase Auth |
| organizations | id, name, owner_id, status | Agência operadora; uma organização possui vários clientes |
| agency_memberships | organization_id, user_id, agency_role, status | Staff interno, único por organização/utilizador |
| workspaces | id, organization_id, slug, name, timezone, currency, status | Cada workspace pertence à agência; slug único por organização |
| workspace_access | workspace_id, user_id, affiliation_type, workspace_role, status | Atribuições de staff interno e memberships do cliente; origem validada |
| permission_grants | principal_id, workspace_id, project_id, resource_scope, permission, effect | Permissões explícitas, escopo e negações |
| functional_teams / team_members | workspace_id, team_id, user_id, specialization | Organização de trabalho, não concede acesso automaticamente |
| workspace_members | workspace_id, user_id, role, status | Compatibilidade/migração para workspace_access; evitar duas fontes de verdade |
| invitations | organization_id, workspace_id, invited_as, email, role, expires_at, accepted_at | Token hash; convites da agência e do cliente com políticas distintas |
| projects | id, workspace_id, name, status, owner_id | Campanhas e séries |
| content_items | id, workspace_id, project_id, title, editorial_status, production_status | Entidade canónica |
| content_versions | id, content_id, version, blocks_json, author_id, created_at | Imutável após submissão |
| sources | id, workspace_id, url, title, type, category, status, published_at | Dedup por URL normalizado por workspace |
| references | id, workspace_id, url, creator, tags, notes | Externas, com proveniência |
| content_sources | content_id, source_id | N:N no mesmo workspace |
| review_requests / decisions | version_id, reviewer_id, status, reason, at | Histórico imutável |
| comments | workspace_id, target_type/id, timestamp_ms, body, resolved_at | ACL do alvo |
| recording_sessions / takes | content_id, block_id, take_number, notes, asset_id | Sessões de gravação |
| assets / asset_versions | workspace_id, storage_key, type, size, checksum | Bucket privado; links assinados |
| publications | content_id, platform, external_id, status, scheduled_at | Idempotência e URL externa |
| metric_snapshots | publication_id, captured_at, metrics_json | Origem e timestamp |
| integrations | workspace_id, provider, scopes, health | Segredos server-side encriptados |
| agents / agent_runs | workspace_id, config_version, status, cost, output | Logs, quotas e aprovação |
| tasks / notifications | workspace_id, assignee, target_id, status | Deep links autorizados |
| cost_entries / budgets | workspace_id, category, amount, currency, estimated | Agregação por período |
| audit_events | workspace_id, actor_id, action, entity_id, before/after_ref, at | Append-only; retenção |

Índices obrigatórios: `(workspace_id, created_at)`, `(workspace_id, status)`, `(workspace_id, project_id)` e índices de pesquisa; todas as FKs de negócio validam pertença ao mesmo workspace. `workspace_id` não é alterável depois de criado o registo sem migração privilegiada.

## 8. API, serviços e arquitetura

- Next.js App Router com server-side auth guard; Supabase Auth para utilizadores, Postgres/RLS para autorização, Storage privado para media e Realtime restrito.
- Camada de serviço por domínio (workspaces, sources, scripts, reviews, production, media, publications, metrics, agents, billing-costs); validação de inputs no servidor com schemas versionados.
- Mutations sensíveis via server actions ou endpoints com autenticação, autorização, rate limiting, audit log e idempotency key.
- Jobs assíncronos para ingestão, IA, transcrição, thumbnails, publicação e métricas; queue com retry exponencial, dead-letter e observabilidade.
- Segredos de integrações e service-role nunca no bundle do browser; apenas chaves publishable públicas no cliente e sempre protegidas por RLS.
- Search index com filtro obrigatório de workspace e ACL; cache keys incluem user_id e workspace_id; invalidar cache na mudança de workspace.
- Storage por workspace e asset ID, sem confiar no path fornecido pelo cliente; signed URLs com expiração curta.
- API versionada para integrações, paginação cursor-based, filtros, ordenação e limites documentados.
- Exportação assíncrona para volumes elevados; ficheiros exportados com expiração e permissão por workspace.

## 9. Migração do código existente

**MIG-01** Inventariar SQL, tabelas, views, RLS, RPCs `studio_whoami` e `guiao_update` no Supabase real antes de qualquer migração; backup e staging obrigatórios.

**MIG-02** Criar workspaces/memberships e associar registos atuais `client_id='numeiro'` ao workspace legado sem perder IDs.

**MIG-03** Substituir `DEFAULT_CLIENT` em `src/lib/supabase.ts`, `src/lib/data.ts` e `src/components/use-guioes.ts` por contexto autenticado; bloquear acesso sem membership.

**MIG-04** Migrar códigos de equipa/localStorage para Supabase Auth e sessões geridas; período de transição controlado, revogação e logout.

**MIG-05** Migrar `Guiao` para content_item + content_versions, mantendo compatibilidade de leitura temporária e mapeamento `aprovado/rejeitado`, `validado`, `gravado`.

**MIG-06** Migrar `Idea` para sources, removendo `take_numeiro` em favor de `editorial_angle` genérico; adicionar workspace_id e RLS.

**MIG-07** Criar rotas reais para módulos existentes no menu e novas páginas `/fontes`, `/equipa`, `/perfil`, `/settings`, `/calendario`, `/publicacoes`. Redirecionar `/ideias` → `/fontes` de forma permanente quando pronto.

**MIG-08** Implementar pesquisa real em `app-search.tsx`, corrigir links `#`, perfil demo, loading infinito e erros silenciosos do teleprompter.

**MIG-09** Introduzir feature flags por workspace para migração progressiva, dual-read limitado e plano de rollback testado.

**MIG-10** Remover RPCs e credenciais legadas só depois de validação e reconciliação de dados.

## 10. Requisitos não funcionais e segurança

- **Disponibilidade alvo:** 99,9% mensal após lançamento, dependente de fornecedores; monitorização e alertas para incidentes.
- **Performance alvo:** p75 LCP ≤ 2,5 s em desktop em condições de referência; ações simples p95 ≤ 800 ms no backend excluindo IA/uploads; paginação em listas.
- **Acessibilidade:** WCAG 2.2 AA nas páginas críticas, teclado completo, focus states, labels e contraste.
- **Compatibilidade:** Chrome, Safari, Firefox e Edge recentes; mobile responsivo, teleprompter testado em iOS/Android.
- **Proteção:** HTTPS, CSP, CSRF quando aplicável, XSS-safe rendering, validação de URLs, rate limiting, MFA para admins configurável, segredo em vault, rotação de tokens.
- **Privacidade:** consentimento e termos das integrações, retenção configurável, exportação e eliminação; avaliação jurídica conforme jurisdições dos clientes.
- **Observabilidade:** logs estruturados com correlation ID, erros client/server, métricas de filas, sync lag, quotas e dashboards de saúde.
- **Recuperação:** backups automatizados e restore testado; RPO alvo 24h e RTO alvo 8h, a validar com infraestrutura real.
- **Dados:** migrations versionadas, constraints, índices, jobs idempotentes, reconciliador de estados e integridade referencial.

## 11. Matriz de testes e aceitação de release

| ID | Teste | Resultado obrigatório |
|---|---|---|
| QA-01 | Abrir cada rota por menu, URL direta e refresh | Sem 404/links inertes |
| QA-02 | User A tentar ler/alterar workspace B por URL/API/RPC/realtime/storage | 403/sem dados |
| QA-03 | Convite expirado, sessão revogada, membro removido | Acesso negado imediatamente conforme política |
| QA-04 | Criar/editar/submeter/aprovar guião e editar após aprovação | Nova versão e aprovação anterior preservada |
| QA-05 | Fontes duplicadas e URLs inválidos | Mensagem e deduplicação previsível |
| QA-06 | Teleprompter: troca de data, espelho, atalhos, sessão interrompida | Estado correto e recuperação |
| QA-07 | Revisão com comentários timestamp e múltiplas versões | Decisões vinculadas à versão |
| QA-08 | Upload grande e interrupção de rede | Retry sem corrupção/duplicação |
| QA-09 | Publicar/agendar e simular timeout do provider | Sem publicação duplicada |
| QA-10 | Integração OAuth expirada | Erro visível e reconexão |
| QA-11 | Agente IA falha ou excede orçamento | Sem aprovação falsa, custo registado |
| QA-12 | Pesquisa de A com termo exclusivo de B | Nenhum resultado de B |
| QA-13 | Mudança de role durante sessão ativa | Nova autorização efetiva |
| QA-14 | Utilização mobile/tablet e teclado | Fluxos principais acessíveis |
| QA-15 | Backup e restauro de amostra | Integridade e RPO/RTO medidos |
| QA-16 (CHG-002) | Abrir cada rota com conta de agência, conta de cliente e código de equipa, com tempo real ligado, e forçar a falha de um widget e de um pedido | Sem ecrã de erro do browser; widget com erro isolado e "Tentar de novo"; zero erros na consola nas rotas principais |

## 12. Backlog por dependências e entregáveis

**Fase A — Fundação e segurança:** inventário SQL/RLS, auth individual, organizations/workspaces, membership, autorização, testes de isolamento, design system e CI. **Saída:** multi-tenant seguro.

**Fase B — Núcleo editorial:** fontes, guiões, versões, revisão, teleprompter, pesquisa, notificações e dashboard real. **Saída:** ciclo editorial completo.

**Fase C — Produção e colaboração:** calendário, tarefas, gravação, assets, revisão de vídeo, equipas e permissões. **Saída:** pipeline de produção rastreável.

**Fase D — Distribuição e inteligência:** contas sociais, publicações, métricas, IA, agentes, referências, custos e relatórios. **Saída:** ciclo fechado com dados reais.

**Fase E — Robustez e lançamento:** performance tuning, testes de carga, acessibilidade, incident response, restore drill, importação de dados e UAT multi-cliente. **Saída:** release 1.0.

Não estimar datas/custos sem inventário SQL, desenho aprovado, equipa disponível e escolha de fornecedores. Cada etapa tem dependências técnicas e deve manter testes verdes.

## 13. Definition of Done por requisito

1. UX aprovada em desktop e mobile, incluindo empty/loading/error/permission denied.
2. Validação de input, autorização server-side e RLS demonstradas.
3. Persistência e recuperação testadas, incluindo refresh, concorrência e retry.
4. Eventos auditáveis e métricas/erros observáveis.
5. Testes unitários, integração e E2E relevantes adicionados ao CI.
6. Documentação de API, migration e comportamento atualizada.
7. Critério de aceitação do FR demonstrado por teste e aceite em staging.

## 14. Decisões pendentes antes da implementação

- Um workspace equivale sempre a um cliente/criador ou pode conter várias marcas e canais? **Default proposto:** um workspace por cliente, múltiplos canais/projetos dentro dele.
- A equipa da agência precisa de acesso transversal? **Default:** membership explícito em cada workspace; nunca super-admin implícito na UI.
- Quais plataformas publicar diretamente na v1? **Default:** publicação manual universal e APIs oficiais apenas onde permissões forem aprovadas.
- Quais métricas são indispensáveis por plataforma? **Default:** mostrar apenas as obtidas legalmente e com timestamp.
- Aprovação do próprio guião permitida? **Default:** segregação opcional por workspace.
- Armazenamento e processamento de vídeo: Supabase Storage versus storage especializado, conforme volume real e custos. **Resolvido (CHG-003, ING-01):** bruto em Google Drive sem prazo; trabalho, proxies e finais em object storage S3-compatível (proposta Cloudflare R2).
- Limites de IA e quotas: por workspace e por agente, com alertas e bloqueio configuráveis.
- Política de retenção e localização de dados: validar requisitos contratuais e regulatórios dos clientes.

## 15. Inventário de ficheiros que requerem intervenção inicial

`src/lib/types.ts`, `src/lib/supabase.ts`, `src/lib/data.ts`, `src/components/use-guioes.ts`, `src/components/session-provider.tsx`, `src/components/app-shared.tsx`, `src/components/app-sidebar.tsx`, `src/components/app-search.tsx`, `src/app/guioes/page.tsx`, `src/app/teleprompter/page.tsx`, `src/app/ideias/page.tsx`, `src/app/desempenho/page.tsx`, `src/app/page.tsx`, `package.json`, documentação e migrações SQL (não presentes no ZIP). A lista é ponto de partida, não inventário exaustivo de dependências.

## 16. Adenda de migração e implementação da arquitetura Agency + Client

1. Criar `organizations`, `agency_memberships`, `workspace_access`, `permission_grants` e `functional_teams` com constraints e RLS; migrar membership antigo em transação e sem eliminar dados.
2. Migrar `DEFAULT_CLIENT = "numeiro"` para workspace real com `organization_id`; não confiar em `client_id` vindo do frontend.
3. Substituir códigos partilhados por Supabase Auth individual e convites por email; bloquear acesso legado após migração validada.
4. Implementar middleware de autenticação, resolução do contexto e serviço central de autorização com testes de negação.
5. Criar layout de agência (`/agency/...`) e layout do cliente (`/w/[slug]/...`), incluindo seletor apenas para utilizadores autorizados.
6. Atualizar todas as consultas e RPCs, incluindo `fetchIdeas`, para filtrar workspace e aplicar RLS; rever cache, storage e realtime.
7. Construir diretórios de equipas separados, atribuições internas, gestão de papéis e convites client-side com teto de autoridade.
8. Integrar tarefas, produção, clipping e aprovações com o conteúdo canónico e histórico.
9. Adicionar testes E2E para dois clientes e duas equipas, incluindo ataques de alteração de IDs e remoção de permissões durante sessões ativas.
10. Migrar clientes piloto com rollback, backups e reconciliação de contagens antes de ativar em produção.

**Critério de release:** demonstrar em staging, com dados reais de teste, (a) um colaborador da agência a alternar entre dois clientes, (b) uma equipa do cliente a trabalhar apenas no seu workspace, (c) gestão de tarefas e aprovação entre especialidades, e (d) tentativas de acesso cruzado bloqueadas em UI, API, RLS e storage.

---

# PARTE II — Consolidação Viral Engine, decisões estratégicas e especificação operacional

## 17. Fontes, precedência e rastreabilidade

**Fontes consolidadas:** (A) PRD Viral Engine (web app) v1.0, 28-10-2026, 24 páginas; (B) ClipStudio PRD v1.0; (C) ClipStudio PRD v1.1 Agency + Client; (D) inspeção estática do repositório `clipstudio-main` fornecido. O documento A descreve um caso operacional concreto (Numeiro, 30 guiões, três hooks, 90 variações), não uma regra universal para todos os workspaces. B/C descrevem a plataforma multi-cliente. A versão 2.0 preserva ambos: **plataforma multi-workspace configurável + template operacional Viral Engine**.

**Precedência:** segurança e isolamento multi-tenant > políticas organizacionais > configuração de workspace > templates de workflow > preferências pessoais. Os números e prazos do PRD Viral Engine são metas piloto, não compromissos universais. Estimativas de custos, capacidades de APIs, modelos LLM e datas devem ser revalidadas antes de implementação. A execução real do motor Python, as políticas RLS de produção e integrações não foram verificadas no ZIP; marcar `A VALIDAR`.

| Fonte Viral Engine | Decisão de consolidação | Referência |
|---|---|---|
| Produção diária 30 guiões, 3 hooks, 90 vídeos | Preservar como **preset do workspace Numeiro**, editável; outros clientes definem metas próprias | PDF §§1,3,5 |
| Repórter, Curioso, Filósofo, Analista, Aprendiz, Estratega, Hook Smith, Guionista, Crítico, Editor | Preservar catálogo de agentes e pipeline versionado, configurável por workspace | PDF §§6,10 |
| Execuções diárias, reposição, falhas, custos e logs | Módulo de **Execuções** de primeira classe, não apenas secção em Agentes | PDF FR-19–23 |
| Pedido do talento por voz/texto, substituição de guiões, repetir vencedor | Integrar no ciclo editorial com eventos e permissões | PDF §§5–6 |
| Teleprompter iPad, Bluetooth, exportação TXT, retoma | Preservar; corrigir marcação de gravado com confirmação explícita | PDF FR-10–15 |
| 3 variações lado a lado, timeline FCPXML, worker externo | Pipeline de pós-produção assíncrono; não prometer renderização até validação do worker | PDF §§6,8,11 |
| Conta por plataforma e múltiplas contas por influencer | Modelo `social_accounts` e `publications` por conta, sem confundir conta com workspace | PDF §16.3 |
| Sala de agentes em tempo real | Vista opcional sobre eventos persistidos, não substitui logs operacionais | PDF §16.1 |
| Custos estimados e calendário | Tratar como baseline histórico e pressupostos a atualizar | PDF §§14–15 |

## 18. Objetivo operacional e indicadores

A aplicação gere a cadeia **Descoberta → Estratégia → Guião → Aprovação → Planeamento → Gravação → Ingestão → Clipping/Edição → QA → Publicação → Análise → Aprendizagem**. Cada conteúdo tem um identificador canónico e ligações a todas as suas variantes, tarefas, ficheiros, contas sociais e resultados. KPI primário: percentagem de conteúdos entregues dentro do prazo e aprovados sem retrabalho; secundários: tempo de ciclo, taxa de revisão, throughput, backlog, custo por peça publicada, alcance relativo à mediana por conta e taxa de utilização da equipa. Métricas devem indicar fonte, período, timezone e qualidade dos dados.

## 19. Novas capacidades estratégicas para reduzir fricção

### 19.1 Inbox universal e triagem

**FR-17-01 [P0]** Inbox unificada por utilizador com tarefas, aprovações, menções, erros de automação e decisões pendentes, deduplicada por evento.

**Aceitação:** abrir um item navega para recurso e contexto certos; marcar lido não aprova conteúdo; filtros por workspace, urgência e tipo persistem.

**FR-17-02 [P1]** Caixa de entrada por workspace com triagem de novas fontes, pedidos do talento, feedback do cliente e material entregue.

**Aceitação:** item tem responsável, SLA e estado; não fica sem dono.

### 19.2 Brief único e conteúdo canónico

**FR-17-03 [P0]** Todo o conteúdo pode ter briefing estruturado: objetivo, audiência, tese, formato, duração, plataformas, CTA, referências, restrições, dono e deadline.

**Aceitação:** versões e aprovações referenciam o briefing em vigor.

**FR-17-04 [P0]** Relação um-para-muitos: conteúdo → hooks → takes → variantes → assets → publicações por conta → métricas.

**Aceitação:** uma publicação em três contas não triplica o número de guiões; cada resultado mantém atribuição inequívoca.

### 19.3 Handoffs e bloqueios

**FR-17-05 [P0]** Transições configuráveis de workflow geram tarefas e notificações idempotentes, com owner, prazo e pré-requisitos.

**Aceitação:** uma transição repetida não cria tarefas duplicadas; cada bloqueio mostra causa e próximo responsável.

**FR-17-06 [P1]** Regras de escalonamento por SLA e fila de exceções (sem responsável, atraso, erro de upload, publicação falhada).

**Aceitação:** escalonamento não concede permissões nem publica automaticamente.

### 19.4 Operação de alto volume

**FR-17-07 [P1]** Operações em lote: atribuir, categorizar, aprovar quando permitido, exportar e reagendar; pré-visualização de impacto e confirmação para ações destrutivas.

**Aceitação:** resultado individual por item, falhas parciais recuperáveis.

**FR-17-08 [P1]** Gestão de capacidade por pessoa e equipa: disponibilidade, estimativas, WIP limits e redistribuição com histórico.

**Aceitação:** alerta de sobrecarga não bloqueia trabalho sem política explícita.

**FR-17-09 [P1]** Templates de projetos, campanhas, séries e checklists; clonagem segura sem copiar tokens, memberships ou dados privados.

**Aceitação:** clone pertence exclusivamente ao workspace de destino.

### 19.5 Aprendizagem e qualidade

**FR-17-10 [P1]** Taxonomia de motivos de rejeição por guião e vídeo; dashboards de retrabalho por etapa.

**Aceitação:** alterações alimentam relatórios, sem mudar automaticamente prompts sem aprovação.

**FR-17-11 [P1]** Experimentos de hooks/formatos com hipótese, variantes, contas, janela de medição e critérios de decisão; alertar sobre amostras insuficientes.

**Aceitação:** nunca declarar causalidade a partir de comparações observacionais simples.

**FR-17-12 [P1]** Motor “repetir vencedor” cria proposta de continuação/variação ligada à publicação original, com aprovação editorial.

**Aceitação:** não publica sozinho.

### 19.6 Continuidade e fiabilidade

**FR-17-13 [P0]** Auto-save com indicador persistido, proteção contra alterações concorrentes e recuperação de rascunhos.

**Aceitação:** conflito apresenta diff/versão; nunca sobrescreve silenciosamente.

**FR-17-14 [P0]** Jobs duráveis com idempotency key, retries exponenciais, timeout, dead-letter, cancelamento e reprocessamento autorizado.

**Aceitação:** refresh não perde job; duplicar pedido não duplica resultados/custos sem aviso.

**FR-17-15 [P0]** Observabilidade com logs estruturados, correlação por workspace/run/content, alertas e dashboard de saúde.

**Aceitação:** segredos e dados pessoais sensíveis são removidos dos logs.

**FR-17-16 [P1]** Centro de integrações com estado da ligação, última sincronização, limites e permissões OAuth; reconexão e revogação.

**Aceitação:** uma conta expirada não causa publicação silenciosamente perdida.

## 20. Preset operacional Viral Engine / Numeiro

**Template, não hardcode.** Workspace define `target_scripts_per_day=30`, `hooks_per_script=3`, `target_variants_per_day=90`, `scheduled_run=18:00 Asia/Dubai`, `deadline=20:00`, `topup_limit=1`, `manual_generate_range=1..40`. São defaults retirados do PRD original e podem mudar por workspace. Definir capacidade real e custos antes de ativar 90 renders/dia. A conta do talento pode sugerir tema por texto/voz; a geração devolve propostas sujeitas a aprovação. O talento pode rejeitar guião com motivo; a substituição é uma nova execução associada ao original.

**Pipeline de agentes:** Aprendiz/Analista/Curioso/Repórter/Filósofo → Estratega (slots) → Hook Smith → Guionista → Crítico → Editor. Cada passo tem `agent_version`, `prompt_version`, `model`, `input_hash`, `output_ref`, `cost`, `duration`, `status`, `error`, `run_id`. Os modelos mencionados no PRD original são configurações históricas, não garantia de disponibilidade. Validação de factos, fontes e citações obrigatória; uma citação não verificada não entra num guião factual. Regras de qualidade (ex. três hooks distintos, nota mínima) são presets configuráveis e auditáveis, não regras universais.

**Execuções:** agendadas, manuais, reposição, regenerar guião, regenerar hook e reprocessar vídeo. Job orchestration fora de funções HTTP curtas. `run` possui `workspace_id`, `requested_by`, `source`, `trigger`, `schedule_id`, `target`, `progress`, `step`, `started_at`, `finished_at`, `cost`, `error_code` e eventos. Botão “Gerar agora” exige grant e budget. Concorrência: política por workspace e tipo de job; locks transacionais e idempotência. Reposição só uma vez por ciclo configurado, com contabilização clara do número de aprovados.

**Teleprompter:** hook 1/2/3 e corpo separados; blocos Hook/Body/CTA personalizados; espelho horizontal e vertical independentes; fullscreen, velocidade 1–10, letra 32–96px, comandos Bluetooth e exportação TXT. A regra original de marcar gravado ao ultrapassar 80% de scroll pode produzir falsos positivos: registar `viewed_80_percent` como telemetria, mas exigir ação “Marcar como gravado” ou confirmação no avanço; opção de auto-marcação apenas por política explícita do workspace. Não gravados passam para o dia seguinte sem perder ligação à sessão original.

**Pós-produção:** ingestão de sessão multi-câmara e áudio com checksums, metadados e armazenamento externo escalável; segmentação por guião, seleção de takes, render de três variantes, legendas, capas, revisão lado a lado e exportação MP4/FCPXML (quando tecnicamente suportado). Render no worker separado; pré-visualização e estado assíncrono na web. Suporte a correção humana no Premiere/DaVinci. O vídeo bruto não deve ser armazenado por defeito no bucket de assets finais; retenção e localização por cliente.

**Sala de agentes:** vista visual de agentes a trabalhar baseada exclusivamente em eventos persistidos; inclui modo acessível de tabela, estados, tempos, custos e falhas. Não inventar mensagens ou progresso.

**Contador de reserva:** medir guiões gravados e vídeos aprovados ainda não publicados em dias de stock, por conta e por formato, com base na cadência configurada.

## 21. Social accounts e publicação multi-canal

Um workspace pode gerir N criadores e cada criador N contas em Instagram, TikTok, YouTube, X ou outras. Entidades: `creators`, `social_accounts`, `content_items`, `content_variants`, `publication_targets`, `publications`, `metric_snapshots`. Uma peça pode ser publicada várias vezes em contas diferentes com legendas, capas, horários, estados e URLs próprios.

**FR-21-01 [P0]** permissões e credenciais são por conta.

**FR-21-02 [P0]** não publicar sem aprovação humana do asset/versão e do destino.

**FR-21-03 [P1]** importação manual e sync via API autorizada.

**FR-21-04 [P1]** atribuição de métricas por `publication_id`, janela e origem.

**Aceitação comum:** contas de clientes diferentes nunca se misturam; falhas por destino são isoladas e repetíveis sem posts duplicados.

## 22. Segurança, isolamento e governança reforçados

- `agency_staff` e `client_staff` são afiliações; especialidade não concede acesso. Cliente só acede ao seu workspace; equipa da agência vê apenas workspaces atribuídos, salvo owner com privilégio global auditado.
- Espaços (R-13, R-14): o espaço da agência e o espaço do cliente são separados; o cliente no endereço (`/c/<cliente>`) não autoriza nada; testes obrigatórios por funcionalidade: convite da agência ao cliente, convite do cliente à sua equipa, cliente A contra cliente B, equipa do cliente contra o painel da agência, cliente inexistente igual a cliente sem acesso.
- RLS e autorização no servidor em cada operação, incluindo RPCs, jobs, webhooks, exports, search, storage, signed URLs e canais realtime. Testar `deny` por defeito e troca de IDs.
- Contas sociais OAuth com tokens cifrados e rotação; segredos em secret manager, nunca no browser ou logs. Revogação e expiração de sessão; convite com validade e prevenção de self-escalation.
- Aprovação em duas fases configurável (editorial e publicação); ações irreversíveis exigem confirmação e auditoria. Controlo de versões e imutabilidade de versões aprovadas.
- Dados e backups com retenção por workspace, exportação e eliminação conforme obrigações legais. Localização de dados e conformidade RGPD/PDPL dependem de avaliação jurídica real; não presumir conformidade automática por escolher Frankfurt.
- Segregação de ambientes dev/staging/prod, migrações reversíveis, backups testados e feature flags por workspace. Proibir dados de clientes reais em testes automatizados sem anonimização.

## 23. Modelo de dados adicional e eventos

Acrescentar às entidades da Parte I: `creators`, `social_accounts`, `content_briefs`, `content_items`, `content_versions`, `hooks`, `takes`, `content_variants`, `publication_targets`, `metric_snapshots`, `agent_definitions`, `agent_versions`, `agent_runs`, `agent_events`, `run_steps`, `job_attempts`, `media_ingests`, `asset_versions`, `review_annotations`, `approval_policies`, `workflow_templates`, `workflow_instances`, `workflow_transitions`, `inbox_items`, `notification_preferences`, `capacity_plans`, `experiments`, `integration_connections`, `integration_syncs`, `workspace_budgets`, `audit_logs`. Reutilizar tabelas atuais por migração com mapping, não criar duplicados paralelos sem estratégia. Chaves de domínio `workspace_id` + FK; constraints de pertença cruzada e índices por `workspace_id`, `status`, `created_at`; índices únicos para idempotência e `external_platform_id` quando aplicável. Proibir cascades destrutivas sobre logs e publicações históricas.

**Eventos de domínio:** `source.approved`, `script.submitted`, `script.approved`, `script.rejected`, `recording.confirmed`, `asset.uploaded`, `variant.ready`, `review.changes_requested`, `review.approved`, `publication.scheduled`, `publication.published`, `publication.failed`, `metrics.synced`, `run.failed`. Outbox transacional para publicar eventos; consumidores idempotentes; esquema versionado e dead-letter para falhas.

## 24. Fluxos E2E detalhados e testes adicionais

| ID | Cenário | Critério de aceitação |
|---|---|---|
| E2E-01 | Agência atribui editor a clientes A/B | Mesmo login alterna workspaces; vê apenas recursos atribuídos e as suas tarefas globais |
| E2E-02 | Cliente A tenta abrir URL/API/storage de B | 403/404 sem leakage de nomes, contagens ou metadados; RLS nega |
| E2E-03 | Cliente A convida editor próprio | Editor entra apenas em A; não vê seletor global; não consegue convidar agência |
| E2E-04 | Fonte → briefing → guião → revisão → gravação | Versões, responsáveis, timestamps, notificações e estados coerentes |
| E2E-05 | Rejeitar guião e pedir substituto | Rejeição sai da fila ativa; substituto ligado ao original; sem duplicação de runs |
| E2E-06 | 30 guiões × 3 hooks | Preset gera slots com contagem correta e custo real registado; falhas parciais visíveis |
| E2E-07 | Teleprompter em iPad e comando | Scroll/espelho H/V, atalhos, retoma e confirmação de gravação funcionam |
| E2E-08 | Sessão multi-câmara → 3 variantes | Upload validado, worker monitorizado, ficheiros e versões rastreáveis |
| E2E-09 | Revisão de vídeo e correção | Timestamp, comentário, nova versão, aprovação anterior não reutilizada |
| E2E-10 | Uma variante → três contas | Três destinos e métricas independentes; aprovação por destino; idempotência |
| E2E-11 | Revogar membro em sessão ativa | API, storage, search e realtime negam novos acessos imediatamente |
| E2E-12 | Falha de integração/worker | Retry com backoff, alerta, sem falso sucesso nem duplicados |
| E2E-13 | Corrida falha após 17/30 | 17 persistidos, 13 pendentes, reprocessamento controlado, custos contabilizados |
| E2E-14 | Duas pessoas editam guião | Conflito visível, versões preservadas, nenhuma perda silenciosa |
| E2E-15 | Exportação/remoção de cliente | Export autorizado, retenção legal, isolamento e trilho de auditoria |

## 25. NFRs, qualidade e critérios de lançamento

**Metas propostas para validar em staging:** p95 de navegação principal ≤ 2,5s em dispositivos-alvo; ações interativas com feedback ≤ 1s; atualização de progresso ≤ 10s quando online; teleprompter fluido no iPad de referência; WCAG 2.2 AA; zero vulnerabilidades críticas abertas; zero testes de isolamento falhados; backups e restore ensaiados; alertas de job e integração ativos; E2E críticos 100% verdes. 99,5% de disponibilidade é **objetivo de serviço**, não garantia automática do fornecedor. Definir SLO e janela de medição. Nenhuma rota morta, botão decorativo ou placeholder enganador em produção. Funcionalidade ainda indisponível deve estar escondida ou explicitamente marcada como não disponível.

**R-15 (CHG-002) — Falhas contidas, nunca o ecrã de erro do browser.** Nenhuma página pode cair no erro genérico do browser ou do Next ("This page couldn't load"). Obrigatório:
- Limites de erro em três níveis: a app (`app/error`), cada espaço (agência e cliente, `app/c/[ws]/error`) e o global (`app/global-error`). Cada widget de um painel tem o seu limite: um widget que falha mostra "não carregou" com "Tentar de novo" e não leva a página consigo.
- Mensagens de falha em PT-PT, com "Tentar de novo" e caminho de volta, sem detalhes técnicos para o utilizador; o erro vai para os registos com referência.
- Infraestrutura partilhada no browser passa por um único gestor: canais de tempo real (um canal por nome, partilhado e com contagem de ouvintes), e o mesmo padrão para qualquer recurso que o cliente Supabase ou o browser devolva por nome. Abrir canais fora do gestor é bloqueado pelo CI.
- Falhas de rede ou pedidos interrompidos nunca terminam a sessão nem apagam estado; só uma resposta explícita do servidor (código revogado, sessão inválida) o faz.
- **Gate de release:** CI em cada PR com guardas de execução, lint, tipos, testes unitários e build; E2E com **sessão de conta real** (agência e cliente), não só com o código de equipa, porque os caminhos com conta (tempo real, painel da agência, permissões) são diferentes; verificação no browser com sessão antes de dar como feito qualquer mudança de navegação ou de dados ao vivo; zero erros na consola nas rotas principais.

## 26. Plano de entrega por dependências (escopo completo, sem cortes funcionais)

**W0 — Inventário e contratos:** validar SQL/RLS/RPC, motor Python, contas sociais, formatos de media, serviços externos, custos e capacidades; congelar taxonomias e eventos.

**W1 — Fundação:** auth, agency/client memberships, workspaces, políticas, RLS, storage, migração e testes de isolamento.

**W2 — Conteúdo:** fontes, referências, briefs, guiões, versões, aprovações, teleprompter, pedidos do talento.

**W3 — Operações:** tarefas, produção, calendário, workload, inbox, templates e handoffs.

**W4 — IA e jobs:** catálogo de agentes, presets, runs duráveis, custos, observabilidade, sala de agentes.

**W5 — Media:** ingestão, clipping, edição, worker, variantes, biblioteca, revisão e exportações.

**W6 — Distribuição e aprendizagem:** contas, calendário, publicação com aprovação, métricas, experimentos, repetir vencedor.

**Sequência revista (CHG-003):** a ordem de entrega a partir de W5/W6 está em §44; a medição de desempenho (parte do W6) passa para antes da media (W5). O âmbito de cada workstream não muda.

**W7 — Hardening e rollout:** testes E2E, acessibilidade, desempenho, segurança, backup/restore, migração piloto e rollout gradual.

Cada workstream entrega migração + API + UI + autorização + logs + testes + documentação; não declarar módulo concluído só porque a página existe. Entrega de W5 depende de worker real validado; W6 depende de API/plataforma autorizada, com fallback manual explicitamente testado.

## 27. Decisões em aberto e pressupostos

1. Confirmar repositório e acesso ao motor Python, SQL migrations, funções RPC e RLS reais. **A VALIDAR**.
2. Definir serviço de render, capacidade por dia, custo por minuto, formatos, retenção e armazenamento bruto. **A VALIDAR**.
3. Confirmar integrações e direitos de acesso às APIs sociais e ao Metricool. **Decidido (CHG-003, R-19):** só APIs oficiais; Metricool fora do plano. Aprovações em §43.
4. Decidir se um cliente pode ter múltiplos criadores e subequipas; **proposta: sim**.
5. Confirmar quem pode aprovar editorialmente e publicar por workspace; **decidido (CHG-003, PUB-06):** quem tiver a capacidade, atribuível por papel ou pessoa.
6. Confirmar política de gravação do teleprompter; **proposta: confirmação explícita**.
7. Revalidar metas, deadlines e orçamento do piloto Numeiro; os números originais são referência histórica, não promessa operacional.
8. Confirmar idiomas e timezones: **proposta PT-PT inicial, timezone por workspace, armazenamento UTC**.

## 28. Definition of Ready / Done e controlo de alterações

**Ready:** requisito com ID, owner, fluxo, protótipo, dados, permissões, dependências, erros, critérios de aceitação e testes; decisões abertas resolvidas ou documentadas.

**Done:** migração aplicada em staging, RLS testada, API validada, UI funcional desktop/iPad/mobile, acessibilidade, logs, testes unitários/integrados/E2E, documentação atualizada e aprovação de produto. Mudanças ao PRD exigem entrada em `CHANGELOG`, impacto nos módulos, riscos e aprovação do owner; agentes não podem alterar silenciosamente regras de negócio. A implementação segue `AGENTS.md` (entregue separadamente), com este PRD como fonte funcional.

# PARTE III — Administração avançada, equipa em tempo real e evolução controlada (v2.1)

## 29. Princípio de produto: Content Operations OS

**Decisão:** o ClipStudio é o sistema central de operações de conteúdo e clipping para organizações/agências e workspaces de criadores, não uma ferramenta isolada de geração. Todo o conteúdo tem identidade canónica e todo o trabalho tem responsável, estado, contexto, deadline e trilho de auditoria. A arquitetura suporta agência multi-cliente, equipa exclusiva do cliente, convidados temporários e múltiplas contas sociais por criador. Regras de acesso nunca são deduzidas do título profissional.

### 29.1 Padrão para incorporar pedidos novos

Qualquer pedido, incluindo um botão ou novo separador, recebe `change_id`, owner, objetivo, utilizadores, workspaces afetados, impacto em permissões, dados, estados, automações, notificações, APIs, UI, custos, privacidade, migração e rollback. Requisito sem matriz de acesso, estados de erro e teste negativo entre clientes **não está Ready**. Pedido aprovado gera requisito versionado, critérios de aceitação e tarefas técnicas; nenhum developer implementa apenas a parte visual. Manter `docs/CHANGELOG.md`, `docs/decisions/ADR-*.md`, `docs/feature-registry.md`, `docs/access-matrix.md` e `docs/workflow-registry.md` atualizados na mesma alteração.

## 30. Centro de Acessos e Permissões (CAP)

**CAP-01 [P0] Registo central de capacidades.** Cada feature/ação/API/job tem `feature_key` estável, módulo, descrição, risco, ações possíveis, escopos suportados, flag de disponibilidade, dono e versão. Uma feature não entra em produção sem registo; ocultar no menu não é autorização.

**Aceitação:** nova funcionalidade registada aparece automaticamente no inventário de administração e nos testes de autorização.

**CAP-02 [P0] Duas matrizes administrativas.** Vistas `pessoas × capacidades` e `funções × capacidades`, com pesquisa, filtros por agência/cliente/equipa/projeto, ações em lote, exportação, resumo de diferenças e preview antes de guardar.

**Aceitação:** Owner autorizado encontra todas as capacidades, sabe quem tem acesso e altera permissões sem editar código.

**CAP-03 [P0] Papéis e exceções.** Templates por profissão (clipper, editor, SMM, videógrafo, estratega, copywriter) são pontos de partida; papéis customizados versionados e grants explícitos por pessoa, equipa, projeto ou recurso. A decisão é `deny-by-default`; `explicit deny` prevalece sobre allow; restrições de tenant, expiração, estado da conta e segregação de funções nunca podem ser ultrapassadas por grant local. `owner` é papel protegido e exige fluxo de transferência.

**Aceitação:** dois editores com o mesmo cargo podem ter permissões distintas; cliente não pode conceder a si mesmo escopo de agência.

**CAP-04 [P0] Permissões granulares.** Exemplos: `scripts.read/create/edit/submit/approve/delete`, `clipping.create/export`, `media.upload/download/share`, `review.comment/approve`, `publishing.schedule/publish`, `analytics.read`, `costs.read`, `team.invite/manage`, `permissions.manage`, `agents.configure/run`, `integrations.manage`. Separar leitura, edição, aprovação, publicação, download, exportação e gestão.

**Aceitação:** utilizador autorizado a editar não recebe automaticamente poder de publicar ou aprovar.

**CAP-05 [P0] Avaliação centralizada e explicável.** Função `authorize(actor, action, resource, context)` partilhada por APIs, jobs e camada de acesso a dados; RLS e storage como segunda linha. UI usa apenas `can()` para visibilidade/disabled, nunca como barreira única. Ecrã `Porque tem acesso?` apresenta papel/grant/escopo/expiração; simulador `Ver como utilizador` é somente leitura e não impersonation real.

**Aceitação:** acesso negado por URL, API, Realtime, pesquisa, download e job mesmo que UI esteja desatualizada.

**CAP-06 [P0] Gestão de ciclo de vida.** Convites com validade, aceitação, suspensão, remoção, acessos temporários com expiração, revisões periódicas de acessos, reatribuição de tarefas e revogação de tokens/sessões quando viável. URLs assinados previamente emitidos têm limites explícitos; para revogação imediata de ficheiros sensíveis usar proxy/rotação.

**Aceitação:** membro removido perde novos acessos imediatamente, mantendo autoria e logs.

**CAP-07 [P1] Controlo de mudanças sensíveis.** Preview do impacto (número de utilizadores/recursos), confirmação reforçada para publicação, finanças, integrações e permissões, aprovação por segunda pessoa quando configurada, trilho antes/depois, reversão segura e alertas de grants excessivos.

**Aceitação:** alterações são atribuíveis, recuperáveis e não escalam privilégios.

**CAP-08 [P1] Interface multi-cliente.** Administração da agência vê clientes autorizados e grants por cliente; administradores do cliente só veem o seu workspace e apenas podem delegar subconjunto permitido pela agência. Convidados podem receber acesso a uma peça/revisão com prazo e sem listar projetos.

**Aceitação:** nenhuma listagem ou contagem revela nomes de outros clientes.

**CAP-09 [P1] Disponibilidade ≠ autorização.** Feature flags controlam rollout/planos/experiências; permissões controlam acesso a ações e dados. Uma flag ligada não concede acesso.

**Aceitação:** feature off bloqueia operações relevantes com erro explícito, mesmo se a permissão existir.

### 30.1 Modelo lógico proposto (validar contra SQL real)

`feature_registry(key,module,actions,risk,owner,version)`, `role_templates`, `role_versions`, `role_permissions`, `principal_grants(principal_type,principal_id,action,scope_type,scope_id,effect,expires_at,granted_by)`, `policy_decisions` (amostrado e sem dados sensíveis), `access_reviews`, `permission_change_requests`, `feature_flags`. Índices e RLS por tenant; proibir chaves de autorização exclusivamente client-side. A semântica de precedência e de herança deve ser formalizada em testes determinísticos antes de implementar UI.

## 31. Equipa, presença e centro operacional

**OPS-01 [P0] Diretório e contadores.** Lista de colaboradores por agência, workspace, equipa e projeto; totais de membros, convidados, ativos, online, disponíveis, em tarefa, ausentes e bloqueados. Contagens deduplicadas por utilizador; visibilidade autorizada.

**Aceitação:** utilizador com dois separadores abertos conta uma vez.

**OPS-02 [P0] Estados distintos.** `online` = ligação Presence; `active` = atividade recente com timeout e consentimento; `working` = tarefa explicitamente iniciada; `available/busy/away/do-not-disturb` = estado manual ou calendário autorizado. Não equiparar online a produtividade nem usar presença como controlo laboral.

**Aceitação:** desconexão e idle atualizam presença sem encerrar tarefa nem fabricar horas trabalhadas.

**OPS-03 [P0] Minha área de trabalho.** Inbox universal de tarefas, menções, aprovações, bloqueios e pedidos; filtros por cliente, prioridade e prazo; `acknowledge`, snooze, delegar e concluir, sempre com autorização.

**Aceitação:** o utilizador vê apenas itens autorizados, mesmo em agregação multi-cliente.

**OPS-04 [P1] Quem trabalha em quê.** Cartões por membro com tarefa atual voluntariamente iniciada, projeto, cliente, estado, bloqueio, deadline e última atualização; ocultar detalhes privados de workspaces não autorizados.

**Aceitação:** agência consegue identificar responsáveis e bloqueios; cliente A não vê tarefas de B.

**OPS-05 [P1] Capacidade e workload.** Disponibilidade declarada, férias, capacidade semanal, estimativa vs. esforço real opcional, WIP limits, backlog, distribuição de tarefas, previsão de entregas e gargalos. Não inferir produtividade a partir de presença.

**Aceitação:** sobrecarga é sinalizada com base em esforço/capacidade configurados e sem atribuições duplicadas.

**OPS-06 [P1] Planeamento e handoffs.** Workflow templates por formato/cliente, checklists de passagem, dependências, SLAs, escalonamentos, responsáveis substitutos e autoatribuição com aprovação onde necessário.

**Aceitação:** conclusão de edição gera revisão uma vez (idempotência); falha/retry não duplica tarefas.

**OPS-07 [P1] Colaboração e revisão.** Comentários com menções, timestamps, comparação de versões, aprovações, decisões e evidências, incluindo acesso externo restrito por recurso.

**Aceitação:** comentário não concede acesso ao asset; aprovação aplica-se à versão exata.

**OPS-08 [P1] Auditoria de operações.** Histórico de alterações e decisões, relatórios de throughput, lead time, cycle time, tempo em espera, retrabalho, taxa de aprovação, clips por origem e atrasos por etapa. Métricas de equipa só são apresentadas com contexto e regras de privacidade definidas.

**OPS-09 [P2] Automação inteligente.** Sugestões de atribuição por especialidade/capacidade, previsão de bloqueios, briefings automáticos de turno, recomendações de repetição de vencedores e alertas de qualidade. IA nunca altera permissões nem publica autonomamente.

**OPS-10 [P1] Presença segura.** Supabase Realtime Presence com canais por workspace e RLS; atualização limitada para estado pouco frequente; Broadcast para cursores/colaboração intensiva. Indicador de atividade opcional e minimização de dados.

**Aceitação:** utilizador sem acesso ao workspace não consegue subscrever o seu canal de presença.

## 32. Mecanismos adicionais para escalar clipping e conteúdo

**SCALE-01 [P1] Content lineage:** de live/vlog original → timestamp de momento → clip → versão → aprovação → destino social → métricas e receita atribuível quando houver dados.

**SCALE-02 [P1] Ingestão em lote:** upload resumível, deduplicação por hash, filas, quotas, estado por ficheiro e reprocessamento seletivo; links para bruto em storage apropriado.

**SCALE-03 [P1] Clip factory:** deteção de momentos, transcrição pesquisável, criação de múltiplos formatos e variações, legendas e exportação; revisão humana antes de publicar.

**SCALE-04 [P1] Publishing command center:** calendário multi-conta, prevenção de duplicados, validação de formatos/direitos, estados por destino, reconexão de tokens e fallback manual.

**SCALE-05 [P1] Quality gates:** checklist por cliente, guidelines de marca, verificação factual, áudio/legendas/formatos, direitos de música e consentimentos quando relevantes.

**SCALE-06 [P1] Learning loop:** experimentos de hook, comparação por janela e conta, proveniência de métricas, limitações de atribuição, recomendações com evidência.

**SCALE-07 [P2] Templates de operação:** duplicar configurações de workflow, papéis e checklists para novo cliente sem copiar dados, segredos ou acessos existentes.

**SCALE-08 [P2] Portal de cliente:** aprovação externa, estado de entregas, relatórios e pedidos de conteúdo, sem acesso à administração da agência.

## 33. Protocolo obrigatório de mudança (Feature Change Protocol)

1. **Intake:** descrever problema e resultado esperado; atribuir ID e owner.
2. **Impact analysis:** inventariar espaço (agência, cliente ou ambos, R-13), impacto em aprovações das plataformas (scopes novos, ecrã de consentimento, UX de publicação TikTok; PLAT-04), módulos, workspaces, funções, grants, dados, UI, API, RLS, storage, realtime, jobs, eventos, analytics, custos, privacidade e rollback.
3. **Design:** atualizar PRD, registo de capacidades, matriz de acesso, state machine, esquema e ADR quando houver decisão arquitetural.
4. **Ready gate:** exemplos positivos e negativos (incluindo client A vs B, agência vs cliente, role vs grant individual, sessão revogada, múltiplos separadores, retry).
5. **Build:** implementar vertical slice completo, sem placeholders, atrás de flag quando apropriado.
6. **Verify:** testes unitários de políticas, integração, E2E com 2 clientes, acessibilidade, observabilidade, falhas e migração.
7. **Release:** aprovação do owner, changelog, rollout, métricas de sucesso e plano de reversão.
8. **Post-release:** medir uso, erros, retrabalho, custo e efeitos secundários.

**GATE:** se qualquer etapa faltar, estado `NOT READY` ou `NOT DONE`; não declarar concluído.

**Registo de estado (CHG-004, vinculativo).** O estado de cada requisito com ID vive num único sítio do repositório, `docs/status.md`: uma linha por ID com estado (`feito`, `parcial`, `por começar`, `bloqueado`, `adiado`), o que falta, evidência (PR, testes) e data da última verificação com conta real (R-15). Regras:
- Cada tarefa começa pelos *pendentes abertos* do registo e diz o que acontece a cada `parcial` ou `bloqueado` deixado pela tarefa anterior (fechar já, ou manter com dono e motivo). Não se abre âmbito novo sem isso.
- Cada PR que mexe na app atualiza as linhas dos IDs que toca; o CI recusa o PR se não o fizer, e recusa o registo se faltar um ID do PRD, se houver estados inválidos ou se `parcial`/`bloqueado`/`adiado` não disserem o que falta.
- Uma alteração ao PRD que acrescente ou retire IDs atualiza o registo no mesmo PR (os IDs novos entram como `por começar`).
- Saltar ou adiar algo por decisão do owner fica registado como `adiado`, com a decisão e a data; nunca fica em silêncio.
- `feito` exige evidência; com UI, exige também verificação com conta real.
- Uma revisão automática diária, numa sessão independente, confere o registo contra o código, a base de dados e os PRs e entrega ao owner o que foi feito, o que falta, o que está pendente dele e a ordem recomendada.
- O repositório é a memória do projeto: nenhuma sessão depende do histórico de conversa para saber o que está pendente.

## 34. Casos de aceitação críticos para administração e presença

- Agency editor autorizado em A e B alterna com o mesmo login; permissões de A não se aplicam a B.
- Client editor de A tenta API, URL, busca, storage e Realtime de B: sempre negado e sem fuga de metadados.
- Conceder `scripts.edit` a uma pessoa não concede `scripts.approve`, `publishing.publish` nem acesso a custos.
- Remover grant individual em sessão aberta impede a operação seguinte; alterações sensíveis ficam no audit log.
- Feature nova sem chave registada falha em CI; capacidade aparece no painel depois de registada.
- Client Admin tenta criar Agency Owner ou alterar políticas globais: negado.
- Duas sessões/dispositivos do mesmo utilizador contam uma pessoa online; offline não apaga trabalho iniciado.
- Tarefa marcada `working` mantém-se até conclusão/pausa explícita, mesmo após desconexão.
- Agregação de workload global nunca revela projetos privados a membros sem acesso.
- Auto-handoff após retry cria exatamente uma tarefa de revisão e preserva a versão aprovada.

## 35. Benchmark e pressupostos

Referências externas consultadas em 2026-10-28: ClickUp (custom roles, workload), Linear (roles, membros e iniciativas), Frame.io (review, versioning e permissões por recurso), Supabase (Realtime Presence e autorização). São inspirações de produto, não funcionalidades já implementadas. Métricas, capacidades de fornecedor, quotas e custos requerem validação técnica e contratual antes de compromisso. Esta adenda **não** altera automaticamente a infraestrutura ou as permissões existentes; exige migrações e testes.

## 36. Registo de alterações

- **CHG-004 — 2026-10-29:** registo de estado por requisito (`docs/status.md`) validado no CI, regra de início e fim de tarefa, adiamentos registados e revisão automática diária, em §33.
- **CHG-003 — 2026-10-29:** Parte IV (§37-§44): R-16 origem sistema/externo, R-17 hipérbole de persona (decisão de produto, fora do âmbito factual do AGENTS §7), R-18 linhagem gravada no momento, R-19 só APIs oficiais; vista de negócio da agência (BIZ-01..09); ingestão, armazenamento (decide §14) e linha de edição (ING-01..04, EDL-01..06); centro de desempenho (PERF-01..09); variantes, estilos e republicação (VAR-01..07); publicação automática e calendário (PUB-01..06); aprovações das plataformas (PLAT-01..04); sequência de entrega revista (§44, medição antes de media). §26, §27, §14 e §33 com remissões. Origem: inbox de ideias IDEA-001..007.
- **CHG-002 — 2026-10-29:** R-15 (falhas contidas, gestor único de canais, sessões que não caem por falhas de rede, gate de release com CI e E2E com conta real) em §25; QA-16 em §11. Origem: incidente de `/c/numeiro` a cair no erro do browser.
- **CHG-001 — 2026-10-29:** espaço da agência e espaço do cliente (R-13), isolamento dos convites e cliente único (R-14), cliente no endereço, menu da agência e peças previstas; M01 com Painel da agência; §22 e §33 atualizados.
- **v2.1 — 2026-10-28:** adicionados Centro de Acessos e Permissões, catálogo central de capacidades, grants individuais, simulador de acesso, equipa/presença/workload, protocolos de mudança, operação em escala e testes de isolamento.

# PARTE IV — Linha de produção, medição e distribuição em escala (CHG-003)

Esta parte acrescenta requisitos decididos pelo Tomás a 29/10/2026 a partir da inbox de ideias (IDEA-001 a IDEA-007). Não remove nada das Partes I a III; em caso de conflito com elas, prevalece esta parte nos pontos explicitamente marcados como decisão. Números marcados **[pressuposto]** são pontos de partida a calibrar com dados próprios, não metas contratuais. Os volumes do Numeiro (30 guiões, 3 hooks, ~90 vídeos/dia) continuam a ser **preset do workspace**, nunca regra global (AGENTS §7).

## 37. Regras transversais novas

R-16 (CHG-003). **Origem de cada publicação.** Toda a publicação importada ou publicada tem origem `sistema` (saiu de uma versão aprovada no ClipStudio, publicada pelo publicador ou à mão a partir de um render nosso, ou upload do telemóvel que passou pelo pacote de edição) ou `externo` (cliente, outro videógrafo, publicado fora do sistema). A classificação é automática (publicador = sistema; importada que corresponde a um render nosso por impressão digital de vídeo/áudio, legenda e duração = sistema; resto = externo) e pode ser corrigida à mão com auditoria. Vistas da agência, KPIs de entrega e alavancas "o que replicar" usam só `sistema` por defeito (filtro "Só o que fizemos"); `externo` é medido e serve de comparação.

R-17 (CHG-003, decisão de produto). **Hipérbole de persona.** Frases de persona sobre o próprio criador (ex.: "o homem mais rico de Portugal", "o filho do Jeff Bezos") são permitidas em títulos e sobreposições, **apenas** a partir de uma lista de frases-persona aprovada por workspace, versionada e auditada. São hipérbole de personagem, não afirmação factual, e ficam fora do âmbito "factual" do AGENTS §7. Continuam bloqueadas: afirmações falsas que atribuam crimes, doenças ou atos a terceiros identificados; notícias inventadas sobre acontecimentos reais; números apresentados como dados verificados; promessas de ganhos financeiros. Pessoas reais famosas só aparecem em frases da lista aprovada. Frases-persona que envolvam outra pessoa (ex.: parceira) exigem consentimento registado dessa pessoa.

R-18 (CHG-003). **Linhagem gravada no momento.** Cada vídeo publicado guarda, no momento da publicação, a ligação ao conteúdo canónico e as suas etiquetas (§40). A linhagem não é inferida depois. Sem linhagem não há medição de hooks, estilos nem republicações.

R-19 (CHG-003, decisão). **Só APIs oficiais** para métricas e publicação (Instagram Graph API, TikTok API for Business e Content Posting API, YouTube Analytics e Data API). Ferramentas de terceiros (ex.: Metricool) ficam fora do plano; no máximo verificação manual pontual. Atrasos de dados são aceites (Instagram até 48 h; TikTok Business API até ao dia anterior UTC).

## 38. Vista de negócio da agência (BIZ)

Complementa R-04, M01 e o Painel da agência (CHG-001). Espaço: agência.

**BIZ-01 [P0] Métrica norte: atingimento de entrega.** Vídeos publicados no prazo ÷ vídeos contratados no período, por cliente e total. Meta [pressuposto] 95% no mês; alerta abaixo de 90% no dia. Atrasos causados pelo cliente (aprovação, gravação) marcados à parte.

**BIZ-02 [P0] Faixa "Precisa da tua atenção".** No máximo 5 cartões por gravidade, com ação direta. Operacionais: entrega do dia em risco; itens parados acima do p70 do tempo de ciclo da etapa (aviso a partir do p50); aprovação do cliente parada há mais de 48 h; possível supressão (mediana de views 7 d < 60% da dos 30 d anteriores, ou % de posts perto de zero a duplicar); saúde do cliente a cair. Financeiros: margem de entrega < 50%; custo de IA por vídeo +25% sem subida de volume; fatura vencida > 15 dias; renovação ≤ 30 dias com saúde amarela/vermelha; cliente > 20% do MRR durante 3+ meses (mostrado como tendência). Limiares [pressuposto].

**BIZ-03 [P0] KPIs e tabela por cliente.** Operacionais: atingimento, aprovação à primeira, tempo de aprovação do cliente, índice de desempenho (§40). Financeiros: MRR/AGI, margem de entrega, clientes em risco. Tabela por cliente ordenada de causa (produção do dia, itens parados, aprovações) para resultado (desempenho, MRR, custo, margem).

**BIZ-04 [P0] Dois níveis de acesso na mesma vista.** Operacional: staff da agência vê só os clientes atribuídos. Financeiro/administrativo (contratos, margens, custos, permissões, auditoria): dono e quem tiver a capacidade. Cada KPI e coluna tem capability key; o servidor constrói a resposta por pessoa e omite campos financeiros (nunca só esconder no browser). Staff sem acesso financeiro não vê **nenhum total financeiro** (com poucos clientes deduz-se um valor por subtração).

**BIZ-05 [P1] Contratos por cliente.** Valor, moeda original (EUR/AED), volume contratado (guiões, vídeos, plataformas), data de renovação, estado de pagamento. Totais numa moeda base com alternância EUR/AED, taxa e data de conversão visíveis. Registo interno, não faturação (não colide com §0).

**BIZ-06 [P1] Custos e margem por cliente.** Custo de IA por execução já existe (W4); acrescenta custo humano e ferramentas com regra de repartição; margem de entrega, custo por vídeo publicado e por 1.000 views.

**BIZ-07 [P1] Pré-visualizar como papel.** "Ver como papel X no cliente Y": só leitura, avaliado no servidor com as capacidades do papel, faixa persistente "Pré-visualização como…", auditado com o dono como ator. Não existe "entrar como pessoa Z" (impersonação) neste âmbito. Concretiza o simulador de acesso de CAP-05.

**BIZ-08 [P1] Cargos como modelos de permissões.** Mantêm-se os papéis de §3 (nomes PT-PT na UI). Ao convidar escolhe-se o cargo (Editor, Clipper, Copywriter, SMM, Videógrafo…), que pré-preenche grants típicos ajustáveis por pessoa (CAP-03). Sem papéis personalizados por agora.

**BIZ-09 [P2] Saúde do cliente.** Score 0-100 (entrega 30, aprovações/resposta do cliente 20, resultados 20, sentimento 15, comercial 15 [pressuposto]); verde ≥ 75, vermelho < 50; só ativo com ~6 meses de histórico.

## 39. Ingestão, armazenamento e linha de edição (ING, EDL)

Complementa §8, M05, M08, SCALE-02, SCALE-03 e decide o ponto em aberto de §14 sobre armazenamento. Espaço: cliente.

**ING-01 [P0] Armazenamento fora da app (decisão).** A app guarda só metadados, miniaturas e links assinados. **Bruto** em Google Drive da agência, sem prazo (arquivo pesquisável). **Cópias de trabalho, proxies e finais** em object storage S3-compatível (proposta: Cloudflare R2) com retenção: proxies e variantes rejeitadas apagadas ao fim de 7-14 dias [pressuposto]; finais aprovados guardados. Bucket e prefixo por workspace; acesso por URL assinada e curta.

**ING-02 [P0] Entrada da câmara (Sony FX3).** Recomendado gravar XAVC HS 4K 100 Mbps 4:2:2 10-bit (~45 GB/h por câmara) com proxy HD em simultâneo. O proxy sobe primeiro e arranca transcrição, cortes e revisão; o 4K sobe depois e só entra no render final (o reframe 9:16 precisa do 4K). Entrada por pasta Drive vigiada ou upload direto retomável.

**ING-03 [P0] Um ficheiro longo por câmara por sessão.** O sistema corta por guião usando os tempos do teleprompter (início, avanço e confirmação "Gravaste?" por guião) e a transcrição com tempos por palavra alinhada com o texto de cada guião; identifica hook 1/2/3, corpo e repetições; sincroniza câmaras pelo áudio. Aceita também um ficheiro por guião com o ID no nome.

**ING-04 [P1] Modo rápido pelo telemóvel.** Upload pela app (PWA), retomável, para o object storage; cópia para o arquivo Drive. Pode vir sem guião: o sistema cria a identidade de conteúdo, transcreve, sugere hook e frases e corre o mesmo pacote. Normaliza à entrada: frame rate variável → constante, HDR → SDR, orientação e áudio.

**EDL-01 [P0] Pacote de edição automático.** Quando a gravação de um guião entra, um job durável e idempotente gera o pacote definido no preset do workspace. Por defeito: 3 masters (um por hook, corpo montado uma vez, legendas queimadas); split screen imagem + frase-persona; split screen com vídeo de atenção + frase diferente; estilo S13 "Faixa de estatuto" (§41).

**EDL-02 [P0] Revisão em lote.** Tudo entra numa fila com proxy 720p e notas do QC; aprovar, pedir alteração ou rejeitar por variante; aprovação presa à versão exata (AGENTS §2.6, §2.7). Interface pensada para ≤ 30 s por variante [pressuposto].

**EDL-03 [P0] QC técnico em código antes de qualquer revisão por IA.** Texto dentro do retângulo seguro comum (x 60-960, y 210-1600 em 1080×1920), loudness, frames pretos ou congelados, duração, resolução, fps; distinção visual por pHash face à fonte e às irmãs (condição necessária, não suficiente).

**EDL-04 [P1] Vídeos de atenção.** Biblioteca própria ou licenciada de loops (filmados pela agência ou stock licenciado); não usar gameplay de terceiros (risco de direitos). Estilo testável no piloto contra os outros.

**EDL-05 [P1] Pós-produção multi-agente v2 (IDEA-002).** Ondas em paralelo (ingest em código; corte, cor, criativo, revisão do texto; produtor; design, som, packaging; QC; painel de personas e compliance). Acrescenta: notas do painel guardadas por vídeo e calibradas contra resultados reais a 24 h/72 h/7 d (personas que não preveem são revistas ou removidas); máximo 2 reruns, orçamento por vídeo, idempotência e dead-letter; custo por agente e por vídeo; memória de revisões do cliente (cada revisão vira regra que o produtor lê); routing de modelos por tarefa. O "All pass" passa a "pronto para revisão humana", nunca entrega direta.

**EDL-06 [P1] Piloto.** ~100 renders, 4 estilos, ~40 publicados em 3-4 semanas. Avança se [pressuposto]: custo de render ≤ 0,05 USD/variante; QC à primeira ≥ 90%; ≥ 50% aprovadas sem edição; ≤ 30 s de revisão por variante; mediana das publicadas ≥ 0,5× a mediana da conta; zero alertas de saúde da conta.

## 40. Centro de desempenho (PERF)

Complementa M09, FR-17-04, §21, SCALE-06. Espaços: cliente e agência.

**PERF-01 [P0] Hierarquia.** Cliente → criador/marca → conta (plataforma; camada A principal, B clips oficial, C trial, D parceiro) → publicação → conteúdo canónico (guião, hook, variante, geração).

**PERF-02 [P0] Etiquetas obrigatórias à publicação (R-18).** Formato/máquina, tema, hook (texto e mecanismo: contra, número, ego, confissão, segredo, pergunta), estilo de edição, frase-persona, imagem/ativo, duração, tipo de fonte (guião, fonte longa, telemóvel, lifestyle), geração (original ou republicação N), conta e camada, hora local, origem (R-16).

**PERF-03 [P0] Fotografias por idade.** Métricas às 1 h, 24 h, 72 h, 7 d e 30 d; comparação sempre na mesma idade; "vencedor" medido às 72 h.

**PERF-04 [P0] Índice normalizado.** Views ÷ mediana móvel de 30 dias da própria conta. Nunca somar nem comparar views absolutas entre plataformas; no YouTube usar `engagedViews`.

**PERF-05 [P0] Métricas por família.** Alcance (views, reach, % não seguidores/For You); hook (IG `reels_skip_rate`, view rate > 3 s, retenção inicial); retenção (% médio visto, % até ao fim); ressonância (partilhas, guardados e comentários por 1.000 views); crescimento (seguidores por 1.000 views; no Instagram só por conta/dia); saúde da conta (mediana a cair, % posts perto de zero, % For You a cair, estado da conta registado à mão); eficiência (custo por vídeo, por 1.000 views).

**PERF-06 [P0] Vistas.** Por conta; por plataforma; por criador; por conteúdo (o mesmo conteúdo nas 3 plataformas); por hook (os 3 hooks sobre o mesmo corpo como experiência natural); por estilo, tema, formato e frase-persona; por geração; por camada (inclui canibalização entre contas).

**PERF-07 [P1] Alavancas "o que replicar".** Índice mediano por atributo, só mostrado com amostra mínima de 10-20 publicações [pressuposto]; o motor (Aprendiz/Estratega) lê e propõe o mix da semana, sempre com aprovação humana (AGENTS §7). Relatório semanal: top 10, piores 10, hooks vencedores por plataforma, estilos a cortar.

**PERF-08 [P0] Ligar contas.** Botão ou link "Ligar conta" por workspace: a pessoa entra na plataforma e aceita as permissões; nunca se pedem palavras-passe. Tokens cifrados por workspace e conta, renovação automática, alerta e "religar" quando expiram (AGENTS §8). Pré-requisitos: Instagram profissional; TikTok Business ou Creator; YouTube com acesso ao canal certo. Ao ligar: escolher camada, importar o histórico disponível (publicações antigas entram como `externo` até haver correspondência).

**PERF-09 [P0] Correções de dados imediatas.** Recolher `shares`; guardar várias leituras por publicação; ligar cada publicação ao conteúdo canónico.

## 41. Variantes, estilos e republicação (VAR)

Complementa SCALE-01, SCALE-03, SCALE-05, SCALE-06.

**VAR-01 [P0] Receita de variante.** Uma variante só conta como nova se mudar pelo menos 2 de 5 elementos: segmento, tese do título, ativo de contexto, narração/comentário, estrutura. Layout, cor, letra e troca de imagem sem nova tese contam zero (o YouTube penaliza "template-based changes" desde 01/10/2026; o Instagram não conta bordos, legendas nem marca d'água como originalidade). Variantes irmãs para a mesma plataforma diferem em ≥ 2 elementos entre si.

**VAR-02 [P0] Catálogo de estilos por workspace.** Ponto de partida para o Numeiro (1080×1920, retângulo seguro comum): S01 Prova, S02 Gancho visual, S03 Manchete, S04 Contraponto, S05 Responde ao comentário, S06 Número, S07 Narrador, S08 Reação, S09 Top 3 narrado, S10 Série, S11 Carrossel, S12 Cortes de contexto, S13 Faixa de estatuto (foto de estatuto em cima, faixa vermelha em pincelada na junção com título amarelo em negrito e contorno preto, vídeo de lifestyle em baixo). Cada estilo é um template versionado com especificação de layout, nível de transformação e plataforma preferida.

**VAR-03 [P0] Motor frase-imagem.** A imagem é a prova, o título a afirmação, o clip a voz. Entradas: transcrição e afirmações do clip, bíblia de estilo do workspace, biblioteca de imagens etiquetada (cena, emoção, classe, direitos, pessoas e consentimento, validade, usos por conta). Tensões: estatuto + número, contradição, curiosidade, identidade, desafio, pergunta. **Títulos curtos e secos** (decisão): afirmação comprimida, sem "diz que" (ex.: "40 mil € no voo foi barato."), alvo 3-7 palavras, uma linha sempre que possível [pressuposto]. Frases-persona segundo R-17. Deduplicação semântica, par tese-imagem único por conta, limite de reutilização de imagem e de estrutura de frase por conta.

**VAR-04 [P0] Verificador antes da revisão humana.** Classifica cada título: persona (lista aprovada, R-17), opinião atribuída, facto (exige fonte datada), terceiro identificado (revisão com marca jurídica), afirmações com validade (expiram). Verifica PT-PT. Contas de clips podem ter idioma próprio (ex.: PT-BR) se o workspace o definir.

**VAR-05 [P1] Republicação de vencedores.** Candidatos: índice ≥ 2-3× às 72 h/7 d [pressuposto]; classificados perene, ligado a notícia ou afirmação datada (os dois últimos exigem revalidação). Regras por plataforma [pressuposto]: Instagram sem idênticos, intervalo ≥ 30 dias, ≤ 15% de republicações em 30 dias; TikTok idêntico com cautela, ≥ 21 dias, ≤ 20%; YouTube Shorts sem idênticos, ≥ 30 dias, ≤ 10%. Regra de paragem: prever a geração seguinte como última × 0,55 e não agendar se ficar abaixo da mediana da conta. Instagram Trial Reels como teste quando disponível.

**VAR-06 [P1] Fontes longas e lifestyle.** Para escalar, o pacote aceita fontes longas (diretos, versões estendidas) e imagens de lifestyle/eventos como fonte de segmentos, não só guiões.

**VAR-07 [P2] Distribuição por camadas.** Contas principais não crescem em volume por variantes; crescimento por contas oficiais de clips identificadas por ângulo, Trial Reels e, por decisão futura, rede contratada de clippers com teto de orçamento, licença revogável, aprovação por submissão e obrigação de remoção. Nunca contas que se façam passar por fãs independentes (políticas de comportamento enganador). Temas de risco bloqueados antes de chegarem a contas de terceiros.

## 42. Publicação automática e calendário (PUB)

Complementa M11, M12, FR-12-01..04, SCALE-04, R-08.

**PUB-01 [P0] Publicador.** Cada versão aprovada recebe conta, plataforma e hora; um job durável publica pela API oficial, guarda o ID da publicação (liga a PERF) e nunca duplica após retry (R-08). Estado por destino e alerta em falha. Aprovar em lote = autorizar a publicação agendada (AGENTS §2.7).

**PUB-02 [P0] Limites das APIs como restrições do agendador** (verificados 2026-10-29): Instagram 100 publicações por API por conta em 24 h móveis; TikTok ~15/dia por conta de criador, partilhado entre apps, e só público depois da auditoria do Content Posting API; YouTube 100 uploads/dia por projeto por defeito. O agendador lê o limite em tempo real; o excedente nunca falha em silêncio.

**PUB-03 [P0] Modo assistido.** Para o que excede o limite da API (ou antes de uma aprovação): pacote de publicação (vídeo final, legenda, hashtags, hora) numa fila no telemóvel; quem publica toca, publica e confirma; a publicação é ligada pela importação de métricas e conta como `sistema`. Decisão: **TikTok com a mesma cadência do Instagram e YouTube**, usando automático até ao limite e assistido no resto.

**PUB-04 [P0] Calendário de publicações.** Publicações no calendário de M11 por conta e plataforma; arrastar para mudar; conflitos visíveis (variantes do mesmo corpo nunca na mesma conta no mesmo dia; quotas de republicação; limites de API).

**PUB-05 [P1] Republicação agendada.** Às 72 h/7 d, vencedores geram propostas no calendário a +30, +40 e +50 dias (intervalos de VAR-05), com o tipo de versão (igual onde permitido, ou com camada nova). Entram como "republicação proposta" na revisão em lote; se uma geração ficar abaixo do previsto, as seguintes são canceladas sozinhas.

**PUB-06 [P0] Quem aprova.** Quem tiver a capacidade: `publishing.approve` (originais) e `publishing.republish.approve` (republicações), atribuíveis por papel ou pessoa (CAP-03/04). Sem pessoa fixa.

## 43. Aprovações das plataformas (PLAT)

**PLAT-01 [P0] Pré-requisitos, já.** Domínio próprio da app antes de qualquer submissão (mudar domínio, redirect URI, nome ou logo depois obriga a nova verificação na Google); páginas públicas de política de privacidade (dados Meta, TikTok e Google), termos e eliminação de dados; Business Verification da empresa na Meta; apps registadas no TikTok for Developers e na Google Cloud com domínio verificado.

**PLAT-02 [P0] Fase A, só leitura.** Submeter quando "ligar conta + importar métricas + ver no dashboard" funcionar em produção: Instagram `instagram_business_basic` + `instagram_business_manage_insights`; TikTok Login Kit e dados de conta/vídeo Business; YouTube `youtube.readonly` + `yt-analytics.readonly`.

**PLAT-03 [P0] Fase B, publicação.** Submeter quando aprovar → agendar → publicar funcionar: `instagram_business_content_publish`; TikTok `video.publish` e auditoria do Content Posting API (ecrã de publicação com nome do criador, escolha de privacidade, conteúdo comercial, consentimento de música); `youtube.upload`. Até lá, TikTok em modo assistido (PUB-03).

**PLAT-04 [P0] Quando voltar a pedir.** Código e ecrãs novos com as mesmas permissões: não. Meta: permissões novas → App Review; Data Use Checkup anual; app inativa volta a review. Google: scopes novos → verificação; mudar nome, logo, redirect URI, homepage ou link de privacidade → verificação da marca. TikTok: mudanças à configuração da app aprovada (produtos, scopes, URLs) → nova review. Novas permissões testam-se numa app/projeto de teste separado e só se ativam depois de aprovadas (feature flag, CAP-09).

## 44. Sequência de entrega (altera §26 na ordem, não no âmbito)

A medição passa para antes da media. Ordem: (0) PLAT-01 em paralelo, fora do código; (1) BIZ operacional, BIZ-07, BIZ-08 e páginas públicas; (2) PERF base (ligar contas, importação, fotografias, origem, etiquetas) e submissão da fase A; (3) ING-01..04; (4) EDL-01..04 e piloto EDL-06 com os estilos base; (5) PUB-01..04 e submissão da fase B; (6) PERF completo e BIZ financeiro; (7) EDL-05, VAR-03..07 e PUB-05. Cada passo é aditivo (expandir/contrair), com módulos novos atrás de flag e testes de isolamento de §22.

**Decisões de §14 e §27 resolvidas por esta parte:** armazenamento (ING-01); integrações (R-19, só APIs oficiais); quem aprova publicação (PUB-06); política de gravação continua com confirmação explícita. Em aberto: entidade legal para a Business Verification e domínio definitivo; plano/espaço Google Workspace para o arquivo de bruto; formato de gravação atual da FX3; lista de contas sociais por plataforma e tipo.
