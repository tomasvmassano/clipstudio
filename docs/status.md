# Registo de estado dos requisitos

Fonte única do que está feito, parcial, por começar, bloqueado ou adiado (CHG-004). Uma linha por ID do PRD.
Cada PR que mexe na app atualiza as linhas dos IDs que toca; o CI (`scripts/status/check.py`) valida contra o PRD.
O resumo e os pendentes abertos são gerados: `python3 scripts/status/check.py --fix`. "Verificado" é a data da última verificação com conta real (R-15).

<!-- resumo:inicio -->

## Resumo

| Estado | Requisitos |
|---|---|
| feito | 23 |
| parcial | 145 |
| por começar | 89 |
| bloqueado | 3 |
| adiado | 3 |
| **total** | **263** |

## Pendentes abertos (bloqueados primeiro, depois por prioridade)

| ID | P | Estado | O que falta | Título |
|---|---|---|---|---|
| PLAT-01 | P0 | bloqueado | precisa do Tomás: domínio próprio, páginas públicas, Business Verification Meta, registo das apps | Pré-requisitos, já |
| PLAT-02 | P0 | bloqueado | depende de PLAT-01 e de ligar contas + métricas em produção (PERF-08) | Fase A, só leitura |
| PLAT-03 | P0 | bloqueado | depende de PLAT-01 e do publicador (PUB-01) | Fase B, publicação |
| FR-01-02 | P0 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Widgets configuráveis por função e por workspace; comparação temporal e explicaç |
| FR-02-01 | P0 | parcial | sem eliminação definitiva com confirmação (só arquivo) | CRUD de guiões, duplicação, arquivo, recuperação e eliminação com confirmação. |
| FR-03-01 | P0 | parcial | verificação com conta real (R-15) | Fila de gravação por data, campanha e responsável, apenas conteúdos elegíveis; r |
| FR-03-02 | P0 | parcial | sem blocos personalizados | Blocos identificados Hook 1, Hook 2, Body, CTA e personalizados; seleção e repet |
| FR-04-01 | P0 | parcial | sem anexo; edição dos campos da fonte não confirmada | CRUD de fontes com URL, título, origem, data, idioma, autor, tags, categoria, re |
| FR-04-02 | P0 | parcial | sem RSS nem integrações | Adicionar manualmente, por URL, RSS e integrações autorizadas; rastreio de data  |
| FR-06-01 | P0 | parcial | prompt, versão por agente, permissões e limites não constam do catálogo | Catálogo de agentes com função, versão, modelo, prompt, ferramentas, permissões  |
| FR-07-01 | P0 | parcial | sem upload nem captura | Guardar referências por URL, upload ou captura autorizada; metadados e autoria. |
| FR-07-02 | P0 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Classificação por formato, estilo, narrativa, hook, duração, idioma e tags. |
| FR-09-02 | P0 | parcial | só views, likes, comentários, partilhas por scraping; sem alcance, retenção, seguidores, conversões | Métricas por conteúdo e período: views, alcance, interações, retenção, seguidore |
| FR-10-01 | P0 | parcial | sem módulo Custos; worker por alojar | Consumo de IA por agente, modelo, execução e workspace. |
| FR-11-01 | P0 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Calendário editorial por dia, semana e mês; drag and drop com validação. |
| FR-11-02 | P0 | parcial | sem revisões nem publicações no calendário | Tarefas, gravações, revisões, publicações, responsáveis, deadlines e dependência |
| FR-14-01 | P0 | parcial | recuperação por email depende do SMTP do Supabase (limitado) até haver domínio (FR-13-01 adiado); verificação com a conta real do Tomás em produção | Nome, avatar, email verificado, password reset e MFA quando disponível. |
| FR-14-02 | P0 | parcial | notificações pessoais e idioma (só PT-PT); preferências do teleprompter já existiam | Idioma, timezone, tema, notificações e preferências do teleprompter. |
| FR-15-01 | P0 | parcial | sem idioma configurável (só PT-PT) | Geral: nome, logótipo, idioma, timezone, moeda e branding. |
| FR-15-02 | P0 | parcial | sem categorias, estados e regras de aprovação configuráveis | Conteúdo: categorias, formatos, estados, templates, regras de aprovação e checkl |
| TEAM-05 | P0 | parcial | âmbitos projeto e assigned_only não aplicados; sem modelos por profissão | Matriz de permissões configurável |
| TEAM-06 | P0 | parcial | tarefa sem projeto (não existem projetos) | Tarefas e responsáveis |
| TEAM-16 | P0 | parcial | faltam exportação, storage de media, pesquisa e realtime com contas reais | Segurança e testes de autorização |
| FR-17-01 | P0 | parcial | sem decisões pendentes além de aprovações; deduplicação por evento não demonstrada na inbox | Inbox unificada por utilizador com tarefas, aprovações, menções, erros de automa |
| FR-17-04 | P0 | parcial | sem variantes, assets e publicações por conta ligadas | Relação um-para-muitos: conteúdo → hooks → takes → variantes → assets → publicaç |
| FR-17-05 | P0 | parcial | sem pré-requisitos nas transições | Transições configuráveis de workflow geram tarefas e notificações idempotentes,  |
| FR-17-13 | P0 | parcial | sem recuperação de rascunhos após falha | Auto-save com indicador persistido, proteção contra alterações concorrentes e re |
| FR-17-14 | P0 | parcial | worker por alojar | Jobs duráveis com idempotency key, retries exponenciais, timeout, dead-letter, c |
| FR-17-15 | P0 | parcial | sem alertas nem dashboard de saúde | Observabilidade com logs estruturados, correlação por workspace/run/content, ale |
| CAP-01 | P0 | parcial | registo sem descrição, dono, versão, ações e flag de disponibilidade | Registo central de capacidades |
| CAP-02 | P0 | parcial | sem filtros por equipa/projeto, ações em lote, exportação, diff e preview antes de guardar | Duas matrizes administrativas |
| CAP-03 | P0 | parcial | sem papéis personalizados versionados nem modelos por profissão; grants só por pessoa | Papéis e exceções |
| CAP-04 | P0 | parcial | capacidades de clipping, media, review, publishing, integrations sem uso | Permissões granulares |
| CAP-05 | P0 | parcial | sem simulador "Ver como utilizador"; authorize() só por workspace, sem recurso | Avaliação centralizada e explicável |
| CAP-06 | P0 | parcial | sem revisões periódicas de acessos nem revogação de sessões | Gestão de ciclo de vida |
| OPS-01 | P0 | parcial | sem contadores online, disponíveis, em tarefa, ausentes; sem equipa e projeto | Diretório e contadores |
| OPS-03 | P0 | parcial | sem acknowledge, snooze e delegar | Minha área de trabalho |
| ING-03 | P0 | parcial | sem ingestão do ficheiro da câmara, transcrição com tempos por palavra e sincronização pelo áudio | Um ficheiro longo por câmara por sessão |
| EDL-01 | P0 | parcial | job do pacote de edição (precisa de ingestão ING-01..03, render e worker alojado) | Pacote de edição automático |
| EDL-03 | P0 | parcial | ligar ao job do pacote e guardar o relatório por variante na app (EDL-02); calibrar limites no piloto | QC técnico em código antes de qualquer revisão por IA |
| PERF-09 | P0 | parcial | só uma leitura por publicação; ligação ao conteúdo por inferência | Correções de dados imediatas |
| VAR-02 | P0 | parcial | layouts de S01 a S12 (equipa criativa); render real dos estilos | Catálogo de estilos por workspace |
| FR-01-03 | P1 | parcial | sem "Minha fila" no Início; gravações e alertas fora da fila | Minha fila: tarefas, aprovações, gravações, prazos e alertas; clique abre objeto |
| FR-01-04 | P1 | parcial | sem calendário compacto no Início | Calendário editorial compacto e atividade recente com ator e timestamp. |
| FR-02-03 | P1 | parcial | título próprio (usa o tema); verificação com conta real (R-15) | Campos: título, cliente/workspace, campanha, tema, formato, plataforma, responsá |
| FR-02-05 | P1 | parcial | sem ações em lote | Enviar para revisão, aprovar/rejeitar/pedir alterações com comentário obrigatóri |
| FR-03-03 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Espelhamento horizontal e vertical independentes; velocidade, fonte, line-height |
| FR-03-04 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Play/pause, scroll manual, fullscreen por gesto, atalhos configuráveis, controlo |
| FR-03-05 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Guardado de preferências por utilizador e dispositivo; bloqueio de suspensão qua |
| FR-04-03 | P1 | parcial | sem filtros por categoria, tema, idioma e data; pesquisa simples, não full-text | Filtros por categoria, tema, fonte, idioma, data, estado e pesquisa full-text. |
| FR-04-04 | P1 | parcial | sem favoritos | Estados nova, triagem, selecionada, utilizada, descartada; favoritos, duplicados |
| FR-04-05 | P1 | parcial | sem resumo, relevância e ângulos para fontes adicionadas na app; motor (Repórter) por alojar | Resumo por IA com referências à fonte, classificação de relevância e ângulos sug |
| FR-05-04 | P1 | parcial | só guiões; notificações dependem de automação configurada | Aprovar, rejeitar ou pedir alterações com motivo e notificações. |
| FR-05-05 | P1 | parcial | sem fluxos de aprovação configuráveis (só regras de tarefas por evento) | Fluxos configuráveis de aprovação por workspace/projeto; responsáveis e prazos. |
| FR-06-03 | P1 | parcial | worker por alojar: nada corre em produção | Execução manual/agendada, progresso, logs, erros, retry e cancelamento. |
| FR-06-04 | P1 | parcial | sem teste antes de ativar; prompts no código do motor, não versionados na app | Versionamento de prompts/configurações, testes antes de ativar, rollback e audit |
| FR-06-05 | P1 | parcial | sem latência e qualidade por execução; worker por alojar | Custos, tokens, latência e qualidade por execução/agente. |
| FR-07-03 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Filtros, favoritos, coleções e pesquisa. |
| FR-07-04 | P1 | parcial | só para reels recolhidos pelo motor; referências por link sem transcrição | Transcrição e análise de estrutura quando tecnicamente e legalmente permitido. |
| FR-09-03 | P1 | parcial | sem definições por plataforma nem indisponibilidade; só Instagram | Definições consistentes por plataforma; mostrar indisponibilidade e data da últi |
| FR-09-04 | P1 | parcial | sem comparação por hooks, temas, campanhas e responsáveis | Comparação de conteúdos, hooks, temas, formatos, campanhas e responsáveis. |
| FR-09-05 | P1 | parcial | sem exportação nem relatórios programados | Rankings, gráficos, exportação e relatórios programados. |
| FR-10-03 | P1 | parcial | sem custos manuais; só moeda do cliente | Custos manuais opcionais por produção, freelancer e projeto; moeda base configur |
| FR-10-04 | P1 | parcial | sem orçamentos, limite soft, alertas nem autorização para ultrapassar | Orçamentos, limites rígidos/soft, alertas e autorização para ultrapassar quota. |
| FR-11-03 | P1 | parcial | sem vistas por equipa, plataforma, campanha; sem deteção de conflitos | Vistas por equipa, plataforma, campanha e estado; conflitos e atrasos destacados |
| FR-11-04 | P1 | parcial | sem notificações de prazo (só de atribuição) | Templates de produção, checklist por conteúdo e notificações. |
| FR-11-05 | P1 | parcial | sem ficheiros, revisões nem publicações ligadas | Links para guiões, ficheiros, revisões e publicações. |
| FR-13-03 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Múltiplos workspaces por utilizador, papéis independentes e mudança de contexto  |
| FR-13-04 | P1 | parcial | sem transferência de propriedade | Desativar membro, transferir propriedade, impedir remoção do último Owner. |
| FR-13-05 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Auditoria de convites, alterações de papéis e ações críticas. |
| FR-14-03 | P1 | parcial | lista de sessões e dispositivos individuais | Sessões/dispositivos ativos, terminar sessões e histórico de segurança. |
| FR-15-04 | P1 | parcial | sem política de aprovação de IA nas definições | IA: prompts, modelos, limites, permissões e política de aprovação. |
| FR-16-03 | P1 | parcial | sem preferências de notificação; deep links não confirmados para todos os tipos | Inbox de notificações, marcar como lida, deep links e preferências. |
| FR-16-04 | P1 | parcial | sem notificações de integrações | Menções, atribuições, aprovações, falhas de automação e integrações. |
| FR-16-05 | P1 | parcial | pesquisa inexistente, por isso não testada | Evitar notificação de dados de outros workspaces e impedir vazamento em resultad |
| TEAM-07 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Dashboard por âmbito |
| TEAM-08 | P1 | parcial | sem equipas funcionais | Equipas funcionais e capacidade |
| TEAM-09 | P1 | parcial | sem etapas, aprovadores e SLA por tipo de conteúdo | Workflow adaptável por cliente |
| TEAM-11 | P1 | parcial | sem acesso limitado a projetos/tarefas para convidados | Freelancer/guest |
| TEAM-12 | P1 | parcial | sem notificações de prazos e alterações | Notificações direcionadas |
| TEAM-13 | P1 | parcial | sem definições da agência nem /perfil | Separação de settings |
| TEAM-14 | P1 | parcial | sem ficheiros brutos, versões de edição, clips e entregas | Produção e edição |
| TEAM-15 | P1 | parcial | sair da equipa não pede reatribuição | Transferência e offboarding |
| FR-17-02 | P1 | parcial | sem feedback do cliente nem material entregue | Caixa de entrada por workspace com triagem de novas fontes, pedidos do talento,  |
| FR-17-06 | P1 | parcial | sem SLA nem escalonamento; fila de exceções só com sem responsável e erro de automação | Regras de escalonamento por SLA e fila de exceções (sem responsável, atraso, err |
| FR-17-08 | P1 | parcial | sem disponibilidade, estimativas e redistribuição | Gestão de capacidade por pessoa e equipa: disponibilidade, estimativas, WIP limi |
| FR-17-09 | P1 | parcial | sem projetos, campanhas e séries | Templates de projetos, campanhas, séries e checklists; clonagem segura sem copia |
| FR-21-03 | P1 | parcial | importação só por scraping (não API autorizada) | importação manual e sync via API autorizada. |
| CAP-07 | P1 | parcial | sem preview de impacto, segunda aprovação nem alertas de grants excessivos | Controlo de mudanças sensíveis |
| CAP-08 | P1 | parcial | convidados com acesso a uma peça por fazer | Interface multi-cliente |
| OPS-05 | P1 | parcial | sem disponibilidade, férias, capacidade semanal e previsão | Capacidade e workload |
| OPS-06 | P1 | parcial | sem SLA, escalonamento e substitutos | Planeamento e handoffs |
| OPS-07 | P1 | parcial | sem timestamps, comparação de versões e acesso externo | Colaboração e revisão |
| OPS-08 | P1 | parcial | sem relatórios de throughput, lead/cycle time e retrabalho | Auditoria de operações |
| SCALE-05 | P1 | parcial | sem guidelines de marca, verificação factual, áudio, direitos | Quality gates: |
| FR-01-06 | P2 | parcial | filtros persistentes por utilizador por fazer | Estados vazios explicativos, loading, erro/retry, filtros persistentes por utili |
| FR-02-06 | P2 | parcial | sem diff visual entre versões | Histórico de versões com diff e restauro, conflitos de edição e autoria. |
| FR-02-07 | P2 | parcial | sem pesquisa, ordenação, vistas guardadas nem impressão | Filtros, pesquisa, ordenação, vistas guardadas, exportação e impressão. |
| FR-03-06 | P2 | parcial | sem anexar ficheiro ao take | Marcar take gravado, adicionar notas e anexar ficheiro, sem alterar estado edito |
| FR-03-07 | P2 | parcial | não abre sem rede | Fallback de fullscreen/wake lock, falhas de gravação visíveis, estado offline e  |
| FR-04-06 | P2 | parcial | sem controlo de cópias não autorizadas | Converter fonte em guião ou ligar múltiplas fontes a um guião; evitar cópias não |
| FR-04-07 | P2 | parcial | sem feed por utilizador nem exclusões | Feed personalizado por workspace e utilizador; configurações de tópicos e exclus |
| FR-05-06 | P2 | parcial | sem comparação entre versões; bloqueio de publicação sem publicação | Comparação entre versões e bloqueio de publicação sem aprovação exigida. |
| FR-05-07 | P2 | parcial | só guiões (sem vídeo) | Registo de decisões e auditoria de alterações após aprovação. |
| FR-06-06 | P2 | parcial | aprovação não configurável; sem bloqueio de dados sensíveis | Aprovação humana configurável antes de criar guião ou publicar resultado; bloque |
| FR-06-07 | P2 | parcial | sem biblioteca de templates de agentes | Biblioteca de templates de agentes, duplicação entre workspaces sem copiar dados |
| FR-07-06 | P2 | parcial | métricas vêm de scraping, não de API oficial (conflito com R-19) | Indicadores de desempenho apenas quando obtidos por API ou fonte autorizada, com |
| FR-09-06 | P2 | parcial | ligação guião-publicação por inferência do motor (Aprendiz), sem regra contra dupla contagem | Atribuir métricas ao conteúdo publicado e ao guião original; evitar dupla contag |
| FR-10-06 | P2 | parcial | sem distinção estimado/confirmado; câmbio fixo na tabela de preços | Diferenciar custo estimado de custo confirmado e guardar taxa de câmbio utilizad |
| FR-13-06 | P2 | parcial | sem grupos/equipas | Gestão de grupos/equipas e atribuição de tarefas, sem permissões implícitas. |
| FR-15-06 | P2 | parcial | sem MFA, políticas de sessão, exportação e retenção | Segurança: MFA obrigatória opcional, políticas de sessão, logs, exportação e ret |
| FR-15-07 | P2 | parcial | sem importação/exportação nem política de eliminação | Dados: importação/exportação, soft-delete, recuperação e política de eliminação. |
| FR-15-08 | P2 | parcial | sem transferir propriedade nem eliminar | Administração de workspace: transferir propriedade, arquivar e eliminar com conf |
| SCALE-07 | P2 | parcial | papéis não copiados | Templates de operação: |
| R-01 | — | parcial | caminho do código de equipa (legacy_can) sem identidade individual; storage de media e pesquisa por fazer | Toda a leitura/escrita de dados de negócio deve ser autorizada no servidor com b |
| R-02 | — | parcial | pesquisa e storage de media inexistentes; tabelas legadas usam client_id texto em vez de workspace_id | Todas as tabelas de negócio multi-tenant têm workspace_id, FK e RLS; storage, pe |
| R-04 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Dashboard global da agência agrega apenas workspaces autorizados; o cliente vê a |
| R-05 | — | parcial | tentativas negadas só no log da base (RAISE LOG), não em audit_events | Todas as ações críticas são auditáveis com ator, afiliação, âmbito, recurso, dat |
| R-07 | — | parcial | sem padrão comum de retry em todas as ações; media e publicação por fazer | Falhas de rede não podem aparentar sucesso; ações assíncronas apresentam estado  |
| R-08 | — | parcial | sem operações externas nem publicações com chave de idempotência (só jobs internos) | Operações externas e publicações têm chave de idempotência. |
| R-09 | — | parcial | soft-delete só em guiões, referências e clientes; sem política de eliminação | Timestamps UTC e timezone por workspace; soft-delete com recuperação controlada. |
| R-10 | — | parcial | internacionalização não preparada (strings fixas em PT-PT); tratamento de conteúdo de IA como não confiável não testado | Conteúdo externo e de IA é dado não confiável; PT-PT inicial com internacionaliz |
| R-11 | — | parcial | sessões não são revogadas; pesquisa e media protegida inexistentes | Desativar uma conta, retirar atribuição ou reduzir permissões revoga imediatamen |
| FL-01 | — | parcial | convites sem email; fluxo completo com contas reais não testado | criar conta → verificar email → criar workspace → escolher timezone/moeda → conv |
| FL-02 | — | parcial | sem comentários no guião | adicionar fonte → classificar → associar referência → criar guião → editar hooks |
| FL-03 | — | parcial | sem associar media nem revisão de vídeo | guião aprovado → calendarizar → abrir fila → teleprompter → gravar múltiplos tak |
| FL-05 | — | parcial | worker por alojar | fonte → agente gera proposta → revisão humana → criar versão de guião → registar |
| FL-06 | — | parcial | pesquisa e ficheiros inexistentes; custos por cliente só nos agentes | membro de A e B alterna contexto → pesquisa, dashboard, notificações, ficheiros, |
| FL-07 | — | parcial | sem revogação de sessões; uploads/downloads inexistentes | remover membro → revogar sessões/permissões → preservar autoria e audit log → bl |
| FL-08 | — | parcial | sem recuperação de rascunho local após falha | falha de rede durante edição → estado de erro → recuperação do rascunho e retry  |
| MIG-01 | — | parcial | sem staging; backup não documentado | Inventariar SQL, tabelas, views, RLS, RPCs studio_whoami e guiao_update no Supab |
| MIG-04 | — | parcial | código de equipa partilhado ainda ativo, sem expiração nem limite de tentativas | Migrar códigos de equipa/localStorage para Supabase Auth e sessões geridas; perí |
| MIG-05 | — | parcial | sem entidade content_item separada (guioes continua tabela principal) | Migrar Guiao para content_item + content_versions, mantendo compatibilidade de l |
| MIG-06 | — | parcial | ideas não migrada para sources; take_numeiro mantido, sem editorial_angle | Migrar Idea para sources, removendo take_numeiro em favor de editorial_angle gen |
| MIG-07 | — | parcial | faltam /perfil e /publicacoes | Criar rotas reais para módulos existentes no menu e novas páginas /fontes, /equi |
| MIG-08 | — | parcial | sem pesquisa real | Implementar pesquisa real em app-search.tsx, corrigir links #, perfil demo, load |
| MIG-09 | — | parcial | dual-read e plano de rollback testado por módulo; verificação com conta real (R-15) | Introduzir feature flags por workspace para migração progressiva, dual-read limi |
| MIG-10 | — | parcial | RPCs e token legado (studio_whoami, legacy_can, studio_tokens) ainda ativos | Remover RPCs e credenciais legadas só depois de validação e reconciliação de dad |
| QA-01 | — | parcial | E2E versionados cobrem rotas por URL direta e refresh; falta abrir cada rota pelo menu | Abrir cada rota por menu, URL direta e refresh |
| QA-02 | — | parcial | storage de media e realtime por cliente sem E2E dedicado | User A tentar ler/alterar workspace B por URL/API/RPC/realtime/storage |
| QA-03 | — | parcial | sessão revogada não testada | Convite expirado, sessão revogada, membro removido |
| QA-04 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Criar/editar/submeter/aprovar guião e editar após aprovação |
| QA-06 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Teleprompter: troca de data, espelho, atalhos, sessão interrompida |
| QA-11 | — | parcial | testado só em Postgres local e mock; worker por alojar | Agente IA falha ou excede orçamento |
| QA-13 | — | parcial | sem teste com sessão ativa real | Mudança de role durante sessão ativa |
| QA-14 | — | parcial | sem auditoria de acessibilidade nem teclado nos fluxos principais | Utilização mobile/tablet e teclado |
| QA-16 | — | parcial | falta o mesmo com cada papel de cliente (viewer, reviewer) e telemóvel | Abrir cada rota com conta de agência, conta de cliente e código de equipa, com t |
| R-15 | — | parcial | E2E com conta real no CI por fazer (ADR-0019 pendente) | Nenhuma página pode cair no erro genérico do browser ou do Next ("This page coul |

<!-- resumo:fim -->


## Regras globais

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-01 | parcial | caminho do código de equipa (legacy_can) sem identidade individual; storage de media e pesquisa por fazer | authorize() em w1_identity_core, w1_data_access_cutover; w1_isolation 38/38; ADR-0001 | — |
| R-02 | parcial | pesquisa e storage de media inexistentes; tabelas legadas usam client_id texto em vez de workspace_id | RLS por authorize(); bucket branding; canais agents:<ws>; w4_engine_isolation 23/23; W4-03 | — |
| R-03 | feito |  | W1-11 cliente único, w1_invite_isolation 23/23; workspace_access por papel; w1_clients 55/55 | — |
| R-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | agency_dashboard só clientes autorizados; w1_dashboard 38/38; W1-10, ADR-0017 (sem sessão real no painel) | — |
| R-05 | parcial | tentativas negadas só no log da base (RAISE LOG), não em audit_events | audit_events append-only; /historico W1-09; w1_audit 16/16; limitação W1 no CHANGELOG | — |
| R-06 | feito |  | content_versions imutáveis, approved_version_id, estados separados; w2_content 47/47; ADR-0002 | — |
| R-07 | parcial | sem padrão comum de retry em todas as ações; media e publicação por fazer | error boundaries W1-12; autosave com conflito W2-02; takes offline W2-05; ADR-0019 | — |
| R-08 | parcial | sem operações externas nem publicações com chave de idempotência (só jobs internos) | agent_jobs idempotency, eventos de tarefas, takes offline sem duplicar; w4_agents, w3_tasks | — |
| R-09 | parcial | soft-delete só em guiões, referências e clientes; sem política de eliminação | timestamptz + fuso por cliente (W1-07); arquivo/recuperar em W2-02, W1-06 | — |
| R-10 | parcial | internacionalização não preparada (strings fixas em PT-PT); tratamento de conteúdo de IA como não confiável não testado | UI PT-PT; definicoes diz "único idioma por agora"; guiões do motor entram em revisão | — |
| R-11 | parcial | sessões não são revogadas; pesquisa e media protegida inexistentes | authorize() a cada pedido; member_update/member_remove; w1_team 21/21, w3_tasks (perde acesso) | — |
| R-12 | feito |  | grant_set sem auto-elevação e teto; invite_member com teto; w1_permissions 35/35, w1_team, w1_agency_team 24/24 | — |
| R-13 | feito |  | W1-11 espaços agência/cliente, ADR-0018; w1_invite_isolation 23/23; e2e/isolation.spec.ts e routes.spec.ts no CI | 2026-10-29 (E2E) |
| R-14 | feito |  | w1_invite_isolation 23/23; W1-13 staff de cliente não entra na agência; w1_agency_team 24/24; e2e/isolation.spec.ts no CI | 2026-10-29 (E2E) |

## M01 — Início / Dashboard

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-01-01 | feito |  | W1-10 _dashboard_kpis; w1_dashboard 38/38; E2E 16/16; sessão real em /c/numeiro | 2026-10-29 |
| FR-01-02 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | dashboard_widgets/dashboard_layouts, Personalizar, ⓘ; w1_dashboard 38/38; W1-10 | — |
| FR-01-03 | parcial | sem "Minha fila" no Início; gravações e alertas fora da fila | /caixa (inbox) W3-01 com tarefas e aprovações; w3_tasks 53/53 | — |
| FR-01-04 | parcial | sem calendário compacto no Início | panel.activity no Início (W1-10); calendário só em /calendario | — |
| FR-01-05 | por começar | sem ações rápidas no Início | não encontrado em src/app/c/[ws]/page.tsx | — |
| FR-01-06 | parcial | filtros persistentes por utilizador por fazer | W1-10 indica FR-01-06 parcial; route-error, widget-boundary, dashboard-skeleton | — |

## M02 — Guiões

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-02-01 | parcial | sem eliminação definitiva com confirmação (só arquivo) | content_create/duplicate, arquivar/recuperar; w2_content 47/47; W2-02 | — |
| FR-02-02 | feito |  | editor por blocos com autosave e indicador W2-02; content_save; comentários no cartão do guião (W2-06 content_comments (bloco, frase citada, versão, respostas, resolver), /c/[ws]/revisao; w2_review_comments 33/33; e2e/review.spec.ts 3/3; ADR-0025) | 2026-10-29 (E2E) |
| FR-02-03 | parcial | título próprio (usa o tema); verificação com conta real (R-15) | guioes: título, cliente, tema, formato, data; fontes ligadas (content_sources); campanha, responsável, plataformas, etiquetas (content_meta_set, projects; W2-07, ADR-0029); w2_content_meta 30/30; e2e/content-meta.spec.ts | — |
| FR-02-04 | feito |  | editorial_status e production_status independentes; w2_content 47/47, w3_calendar 39/39 | — |
| FR-02-05 | parcial | sem ações em lote | content_transition com motivo obrigatório na rejeição; W2-02; w2_content | — |
| FR-02-06 | parcial | sem diff visual entre versões | content_history, content_restore_version, lock_version; guiao-history.tsx; W2-02 | — |
| FR-02-07 | parcial | sem pesquisa, ordenação, vistas guardadas nem impressão | filtros por estado e Exportar .txt em guioes/page.tsx | — |
| FR-02-08 | por começar | sem sugestões de IA no editor | nada no código | — |

## M03 — Teleprompter

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-03-01 | parcial | verificação com conta real (R-15) | recording_session_open, recording_queue_set; w2_teleprompter 52/52; W2-05; filtros por campanha e responsável na fila (W2-07, ADR-0029); e2e/content-meta.spec.ts | — |
| FR-03-02 | parcial | sem blocos personalizados | blocos Hook/Body/CTA e takes (take_create/update); w2_teleprompter 52/52 | — |
| FR-03-03 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | espelho H/V, velocidade, letra, entrelinha, margens, contraste; W2-05; E2E 28/28 (não versionado) | — |
| FR-03-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | play/pause, scroll, ecrã inteiro por duplo toque, atalhos BT; teleprompter/prompter.tsx; W2-05 | — |
| FR-03-05 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | teleprompter_prefs por utilizador e dispositivo, wakeLock; tp_prefs_get/set; w2_teleprompter | — |
| FR-03-06 | parcial | sem anexar ficheiro ao take | takes com notas sem mudar estado editorial; W2-05; limitação W2 | — |
| FR-03-07 | parcial | não abre sem rede | aviso de wake lock, takes offline, retoma noutro dispositivo; W2-05 | — |

## M04 — Fontes / Notícias

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-04-01 | parcial | sem anexo; edição dos campos da fonte não confirmada | ideas + autor, idioma, tags, resumo, categoria; source_create; w2_sources 41/41 | — |
| FR-04-02 | parcial | sem RSS nem integrações | manual e por URL, ingested_via e created_kind; W2-03 | — |
| FR-04-03 | parcial | sem filtros por categoria, tema, idioma e data; pesquisa simples, não full-text | sources_list p_status/p_q; separadores em fontes/page.tsx | — |
| FR-04-04 | parcial | sem favoritos | estados nova..descartada, dedup por url_normalized, expiração; w2_sources 41/41 | — |
| FR-04-05 | parcial | sem resumo, relevância e ângulos para fontes adicionadas na app; motor (Repórter) por alojar | engine/agents/scouts.py gera fontes; limitação W2 "sem resumo por IA" | — |
| FR-04-06 | parcial | sem controlo de cópias não autorizadas | source_to_script, content_link_source (N:N); W2-03 | — |
| FR-04-07 | parcial | sem feed por utilizador nem exclusões | áreas de notícias (news_beats) na configuração dos agentes por cliente; W4-01 | — |

## M05 — Revisão

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-05-01 | feito |  | review_inbox: filtros por estado, responsável, prioridade, prazo e texto (o tipo é só guião até haver media, FR-05-03); W2-06 content_comments (bloco, frase citada, versão, respostas, resolver), /c/[ws]/revisao; w2_review_comments 33/33; e2e/review.spec.ts 3/3; ADR-0025 | 2026-10-29 (E2E) |
| FR-05-02 | feito |  | decisões versionadas em content_transitions; w2_content 47/47; W2-06 content_comments (bloco, frase citada, versão, respostas, resolver), /c/[ws]/revisao; w2_review_comments 33/33; e2e/review.spec.ts 3/3; ADR-0025 | 2026-10-29 (E2E) |
| FR-05-03 | por começar | sem revisão de vídeo | review.comment/approve só planeadas (W5) | — |
| FR-05-04 | parcial | só guiões; notificações dependem de automação configurada | content_transition com motivo; task_rules W3-01 | — |
| FR-05-05 | parcial | sem fluxos de aprovação configuráveis (só regras de tarefas por evento) | task_rule_save W3-01 | — |
| FR-05-06 | parcial | sem comparação entre versões; bloqueio de publicação sem publicação | content_history; approved_version_id | — |
| FR-05-07 | parcial | só guiões (sem vídeo) | content_transitions append-only, validacao_anulada no audit; w1_review_fixes 11/11 | — |

## M06 — Agentes IA

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-06-01 | parcial | prompt, versão por agente, permissões e limites não constam do catálogo | agent_definitions (etapa, modelo, ferramentas, lê/escreve); W4-01 | — |
| FR-06-02 | feito |  | agent_config_versions com language, voice, guardrails, formats, news_beats, metas; w4_agents 44/44 | — |
| FR-06-03 | parcial | worker por alojar: nada corre em produção | agent_jobs, cancel/retry, progresso; w4_worker 30/30; test_worker 19/19 | — |
| FR-06-04 | parcial | sem teste antes de ativar; prompts no código do motor, não versionados na app | agent_config_save/activate (rollback), auditado; w4_agents 44/44 | — |
| FR-06-05 | parcial | sem latência e qualidade por execução; worker por alojar | tokens e custo por chamada (W4-02, W4-02b); agent_tool_prices | — |
| FR-06-06 | parcial | aprovação não configurável; sem bloqueio de dados sensíveis | guiões do worker entram em revisão (worker_save_script); W4-02 | — |
| FR-06-07 | parcial | sem biblioteca de templates de agentes | workspace_create copia formatos e regras sem voz nem dados (W1-06) | — |

## M07 — Referências

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-07-01 | parcial | sem upload nem captura | reference_create por link e a partir de reels; w2_references 36/36 | — |
| FR-07-02 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | classificação formato, estilo, narrativa, hook, duração, idioma, tags; w2_references 36/36; W2-04 | — |
| FR-07-03 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | filtros, favoritos, coleções, pesquisa; references_list; W2-04; E2E 13/13 (não versionado) | — |
| FR-07-04 | parcial | só para reels recolhidos pelo motor; referências por link sem transcrição | script_analysis do motor; references_discover | — |
| FR-07-05 | feito |  | reference_link a guiões e fontes, URL original; w2_references 36/36 | — |
| FR-07-06 | parcial | métricas vêm de scraping, não de API oficial (conflito com R-19) | "scraper · data" na UI; ADR-0005 | — |

## M08 — Biblioteca

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-08-01 | por começar | sem biblioteca de media | media.upload só planeada (W5) | — |
| FR-08-02 | por começar | sem biblioteca de media | nada no código | — |
| FR-08-03 | por começar | sem biblioteca de media | media.download/share só planeadas | — |
| FR-08-04 | por começar | sem biblioteca de media | nada no código | — |
| FR-08-05 | por começar | sem biblioteca de media (só validação do logótipo: tipo e 500 KB) | w1_settings_branding | — |
| FR-08-06 | por começar | sem biblioteca de media | nada no código | — |

## M09 — Desempenho

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-09-01 | por começar | sem OAuth de plataformas | accounts manual; social_accounts.manage planeada (W6) | — |
| FR-09-02 | parcial | só views, likes, comentários, partilhas por scraping; sem alcance, retenção, seguidores, conversões | desempenho RPC, desempenho-3.tsx; publicacoes/reels | — |
| FR-09-03 | parcial | sem definições por plataforma nem indisponibilidade; só Instagram | data da recolha em referências; desempenho por conta | — |
| FR-09-04 | parcial | sem comparação por hooks, temas, campanhas e responsáveis | mix de formatos, Aprendiz no motor; /desempenho | — |
| FR-09-05 | parcial | sem exportação nem relatórios programados | top reels e gráficos em /desempenho | — |
| FR-09-06 | parcial | ligação guião-publicação por inferência do motor (Aprendiz), sem regra contra dupla contagem | publicacoes.guiao_id; engine learn | — |
| FR-09-07 | por começar | sem integrações OAuth | nada no código | — |

## M10 — Custos

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-10-01 | parcial | sem módulo Custos; worker por alojar | custo e tokens por execução em /agentes/configuracao; kpi.costs; W4-02b | — |
| FR-10-02 | por começar | sem custos de armazenamento, processamento e integrações | nada no código | — |
| FR-10-03 | parcial | sem custos manuais; só moeda do cliente | moeda em /definicoes W1-07 | — |
| FR-10-04 | parcial | sem orçamentos, limite soft, alertas nem autorização para ultrapassar | budget_eur_day limite rígido no worker; W4-02 | — |
| FR-10-05 | por começar | sem custo por guião, vídeo ou publicação | nada no código | — |
| FR-10-06 | parcial | sem distinção estimado/confirmado; câmbio fixo na tabela de preços | agent_tool_prices com fonte, data e câmbio BCE; custo desconhecido ≠ 0 | — |

## M11 — Calendário / Produção

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-11-01 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | /calendario dia/semana/mês, arrastar com validação; content_reschedule; w3_calendar 39/39 | — |
| FR-11-02 | parcial | sem revisões nem publicações no calendário | tarefas, gravações, dependências; W3-01, W3-02 | — |
| FR-11-03 | parcial | sem vistas por equipa, plataforma, campanha; sem deteção de conflitos | atrasados a vermelho; limitações W3-02 | — |
| FR-11-04 | parcial | sem notificações de prazo (só de atribuição) | template_apply, content_checklist; w3_templates 35/35; W3-03 | — |
| FR-11-05 | parcial | sem ficheiros, revisões nem publicações ligadas | detalhe do guião com tarefas no calendário (W3-02) | — |

## M12 — Publicação

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-12-01 | por começar | sem módulo de publicação | publishing.* planeadas (W6) | — |
| FR-12-02 | por começar | sem registo de URL publicado nem agendamento | nada no código | — |
| FR-12-03 | por começar | sem fila de publicação | nada no código | — |
| FR-12-04 | por começar | sem publicação | nada no código | — |
| FR-12-05 | por começar | sem publicação | nada no código | — |
| FR-12-06 | por começar | capacidades separadas só registadas, sem uso | feature-registry publishing.schedule/publish | — |

## M13 — Equipa

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-13-01 | adiado | Decisão do Tomás, 29/10: o envio real por email fica para quando houver domínio (por decidir). Falta conta Resend, domínio verificado, RESEND_API_KEY, INVITE_FROM e APP_URL no Vercel; até lá o link é copiado à mão | invite_member, revoke_invitation, accept_invitations, expiração 14 dias; w1_team 21/21; W1-14 link com token, reenviar, recusar, expirados e recusados na lista; w1_invite_delivery 25/25; e2e/invites.spec.ts 5/5; ADR-0023 | 2026-10-29 (E2E) |
| FR-13-02 | feito |  | papéis workspace_owner..viewer + role_capabilities; w1_isolation 38/38, w1_permissions 35/35 | — |
| FR-13-03 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | workspace_access por pessoa, workspace-switcher; W1-03, W1-11 | — |
| FR-13-04 | parcial | sem transferência de propriedade | member_update suspender, último dono protegido (_last_client_owner); w1_clients 55/55 | — |
| FR-13-05 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | audit_events em convites e papéis; /historico; w1_audit 16/16; invitation.sent e invitation.declined (W1-14) | — |
| FR-13-06 | parcial | sem grupos/equipas | atribuição de tarefas com _task_valid_assignee; W3-01 | — |

## M14 — Perfil

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-14-01 | parcial | recuperação por email depende do SMTP do Supabase (limitado) até haver domínio (FR-13-01 adiado); verificação com a conta real do Tomás em produção | W1-15 /perfil: nome, fotografia, email verificado, mudar e recuperar palavra-passe, MFA TOTP aplicado no servidor (_mfa_ok); w1_profile_mfa 24/24; e2e/profile.spec.ts 3/3; ADR-0024 | 2026-10-29 (E2E) |
| FR-14-02 | parcial | notificações pessoais e idioma (só PT-PT); preferências do teleprompter já existiam | preferências do teleprompter e theme-switcher; fuso e tema no perfil (W1-15) | — |
| FR-14-03 | parcial | lista de sessões e dispositivos individuais | terminar sessão em todos os dispositivos e histórico de segurança (W1-15, my_security_log) | — |
| FR-14-04 | feito |  | workspace-switcher; my_context; cliente preferido no perfil, usado ao entrar (W1-15); e2e/profile.spec.ts | 2026-10-29 (E2E) |
| FR-14-05 | por começar | sem exportação nem eliminação dos próprios dados | nada no código | — |

## M15 — Settings

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-15-01 | parcial | sem idioma configurável (só PT-PT) | workspace_update nome, fuso, moeda, logótipo, cor; w1_settings 20/20 | — |
| FR-15-02 | parcial | sem categorias, estados e regras de aprovação configuráveis | só gravar aprovados, templates/checklists; W1-07, W3-03 | — |
| FR-15-03 | por começar | sem integrações | integrations.manage planeada (W6) | — |
| FR-15-04 | parcial | sem política de aprovação de IA nas definições | modelos e limites em /agentes/configuracao (W4-01) | — |
| FR-15-05 | por começar | sem preferências de notificações | notificações só na app | — |
| FR-15-06 | parcial | sem MFA, políticas de sessão, exportação e retenção | /historico (logs) W1-09 | — |
| FR-15-07 | parcial | sem importação/exportação nem política de eliminação | arquivo e recuperação de guiões e clientes | — |
| FR-15-08 | parcial | sem transferir propriedade nem eliminar | workspace_archive com motivo e confirmação; w1_clients 55/55 | — |

## M16 — Pesquisa e notificações

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-16-01 | por começar | sem pesquisa global | app-search.tsx não existe | — |
| FR-16-02 | por começar | sem pesquisa global | nada no código | — |
| FR-16-03 | parcial | sem preferências de notificação; deep links não confirmados para todos os tipos | /caixa, notifications_read; W3-01 | — |
| FR-16-04 | parcial | sem notificações de integrações | menções em task_comment, atribuições, automation_error; W3-01, W4-01 | — |
| FR-16-05 | parcial | pesquisa inexistente, por isso não testada | _viewer_sees/inbox só clientes autorizados; w3_tasks 53/53 | — |

## 5A. Requisitos adicionais — equipas duplas e operação multid

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| TEAM-01 | feito |  | Supabase Auth individual, auth.users; W1-01/W1-03 (código de equipa ainda coexiste) | — |
| TEAM-02 | feito |  | /equipa-agencia e /c/[ws]/equipa com afiliação; w1_agency_team 24/24; sessão real na equipa da agência | 2026-10-29 |
| TEAM-03 | feito |  | agency_staff_assign com papel por cliente + grants; w1_clients 55/55, w1_agency_team 24/24 | — |
| TEAM-04 | feito |  | convite preso ao workspace emissor; w1_invite_isolation 23/23; e2e/isolation.spec.ts no CI | 2026-10-29 (E2E) |
| TEAM-05 | parcial | âmbitos projeto e assigned_only não aplicados; sem modelos por profissão | capabilities module.action; authorize(cap, ws); w1_permissions 35/35 | — |
| TEAM-06 | parcial | tarefa sem projeto (não existem projetos) | tasks com responsável, criador, prioridade, prazo, dependências, comentários; w3_tasks 53/53 | — |
| TEAM-07 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Painel da agência (W1-10/W1-11), /caixa as minhas tarefas; cliente entra direto; w1_dashboard | — |
| TEAM-08 | parcial | sem equipas funcionais | workload por pessoa W3-03; w3_templates 35/35 | — |
| TEAM-09 | parcial | sem etapas, aprovadores e SLA por tipo de conteúdo | task_rules por cliente W3-01 | — |
| TEAM-10 | por começar | sem dupla aprovação nem bloqueio de autoaprovação | nada no código | — |
| TEAM-11 | parcial | sem acesso limitado a projetos/tarefas para convidados | expires_at em workspace_access e permission_grants | — |
| TEAM-12 | parcial | sem notificações de prazos e alterações | _notify só a quem tem acesso; w3_tasks 53/53 | — |
| TEAM-13 | parcial | sem definições da agência nem /perfil | /c/[ws]/definicoes W1-07; /definicoes é só redirecionamento para o cliente | — |
| TEAM-14 | parcial | sem ficheiros brutos, versões de edição, clips e entregas | recording_sessions e takes ligados ao guião (W2-05) | — |
| TEAM-15 | parcial | sair da equipa não pede reatribuição | member_remove com reatribuição de tarefas W1-06; w1_clients 55/55 | — |
| TEAM-16 | parcial | faltam exportação, storage de media, pesquisa e realtime com contas reais | w1_isolation, w1_invite_isolation, w4_engine_isolation (SQL com utilizadores simulados) | — |

## 6. Fluxos end-to-end obrigatórios

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FL-01 | parcial | convites sem email; fluxo completo com contas reais não testado | workspace_create (fuso/moeda), invite_member, accept_invitations; W1-06 | — |
| FL-02 | parcial | sem comentários no guião | fontes, referências, guião, pedir alterações, versões, aprovar; W2-01..04 | — |
| FL-03 | parcial | sem associar media nem revisão de vídeo | agendar, fila, teleprompter, takes; W2-05, W3-02 | — |
| FL-04 | por começar | sem variantes, publicação nem sync por API | nada no código | — |
| FL-05 | parcial | worker por alojar | worker_save_script em revisão, custo por execução; w4_worker 30/30 | — |
| FL-06 | parcial | pesquisa e ficheiros inexistentes; custos por cliente só nos agentes | dashboard, caixa, desempenho por cliente; w1_dashboard | — |
| FL-07 | parcial | sem revogação de sessões; uploads/downloads inexistentes | member_remove preserva autoria e audit; w1_clients | — |
| FL-08 | parcial | sem recuperação de rascunho local após falha | autosave com conflito (lock_version), erro visível; W2-02 | — |

## 9. Migração do código existente

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| MIG-01 | parcial | sem staging; backup não documentado | docs/inventory/supabase.md; migrações exportadas (W0) | — |
| MIG-02 | feito |  | workspace numeiro com IDs mantidos; w1_identity_core, w2_legacy_sync | — |
| MIG-03 | feito |  | DEFAULT_CLIENT já não existe em src; WorkspaceGate e contexto autenticado (W1-03) | — |
| MIG-04 | parcial | código de equipa partilhado ainda ativo, sem expiração nem limite de tentativas | Supabase Auth W1-03; studio_whoami, legacy_can; limitação W1 | — |
| MIG-05 | parcial | sem entidade content_item separada (guioes continua tabela principal) | content_versions + guiao_update compatível; w2_content 47/47 | — |
| MIG-06 | parcial | ideas não migrada para sources; take_numeiro mantido, sem editorial_angle | ideas + workspace e RLS; w2_sources 41/41 | — |
| MIG-07 | parcial | faltam /perfil e /publicacoes | /fontes, /equipa, /definicoes, /calendario; /ideias → /fontes (next.config.ts) | — |
| MIG-08 | parcial | sem pesquisa real | links # removidos, perfil demo removido, erros do teleprompter (W0, W2-02) | — |
| MIG-09 | parcial | dual-read e plano de rollback testado por módulo; verificação com conta real (R-15) | feature_flag_defs, feature_flags, my_flags, flag_set, /funcionalidades (W0, ADR-0031); w0_feature_flags 20/20 | — |
| MIG-10 | parcial | RPCs e token legado (studio_whoami, legacy_can, studio_tokens) ainda ativos | tmp_import removida (20261029101111_w1_drop_tmp_import) | — |

## 11. Matriz de testes e aceitação de release

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| QA-01 | parcial | E2E versionados cobrem rotas por URL direta e refresh; falta abrir cada rota pelo menu | E2E estrutura 15/15 (CHANGELOG W1-11); e2e/routes.spec.ts no CI (ADR-0022) | 2026-10-29 (E2E) |
| QA-02 | parcial | storage de media e realtime por cliente sem E2E dedicado | w1_isolation 38/38, w4_engine_isolation 23/23, w1_settings (bucket); e2e/isolation.spec.ts: UI, REST e RPC de A contra B; corre no CI em cada PR (job db, base descartável) | 2026-10-29 (E2E) |
| QA-03 | parcial | sessão revogada não testada | convite expirado e membro removido em w1_team, w1_clients; corre no CI em cada PR (job db, base descartável) | — |
| QA-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | w2_content 47/47; E2E de escrita 23/23 (W2) | — |
| QA-05 | feito |  | dedup por url_normalized e URL inválido em w2_sources 41/41; corre no CI em cada PR (job db, base descartável) | — |
| QA-06 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | w2_teleprompter 52/52; E2E 28/28 (offline, dois dispositivos, iPad) | — |
| QA-07 | por começar | sem revisão de vídeo | nada no código | — |
| QA-08 | por começar | sem upload de media | nada no código | — |
| QA-09 | por começar | sem publicação | nada no código | — |
| QA-10 | por começar | sem OAuth | nada no código | — |
| QA-11 | parcial | testado só em Postgres local e mock; worker por alojar | w4_worker 30/30, test_worker 19/19 (limite de custo, falha definitiva); corre no CI em cada PR (job db, base descartável) | — |
| QA-12 | por começar | sem pesquisa | nada no código | — |
| QA-13 | parcial | sem teste com sessão ativa real | authorize() por pedido; w1_permissions 35/35; corre no CI em cada PR (job db, base descartável) | — |
| QA-14 | parcial | sem auditoria de acessibilidade nem teclado nos fluxos principais | E2E telemóvel/iPad no Início e teleprompter (W1-10, W2-05) | — |
| QA-15 | por começar | sem teste de backup e restauro | nada no repo | — |
| QA-16 | parcial | falta o mesmo com cada papel de cliente (viewer, reviewer) e telemóvel | quality.yml (guardas); W1-12; ADR-0019; e2e/routes.spec.ts: 19 rotas, dono e cliente, zero erros na consola (CI) | 2026-10-29 (E2E) |

## 19.1 Inbox universal e triagem

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-01 | parcial | sem decisões pendentes além de aprovações; deduplicação por evento não demonstrada na inbox | inbox, notifications; w3_tasks 53/53; W3-01 | — |
| FR-17-02 | parcial | sem feedback do cliente nem material entregue | /fontes Por triar e Pedidos do talento (W2-03) | — |

## 19.2 Brief único e conteúdo canónico

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-03 | feito |  | content_briefs com todos os campos, versionado; brief_save; w2_sources 41/41 | — |
| FR-17-04 | parcial | sem variantes, assets e publicações por conta ligadas | guião → hooks → takes; publicacoes legado; ADR-0002 | — |

## 19.3 Handoffs e bloqueios

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-05 | parcial | sem pré-requisitos nas transições | task_rules e domain_events_handoff idempotentes; w3_tasks 53/53 | — |
| FR-17-06 | parcial | sem SLA nem escalonamento; fila de exceções só com sem responsável e erro de automação | /caixa sem responsável; automation_error (W4-01) | — |

## 19.4 Operação de alto volume

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-07 | por começar | sem operações em lote | limitação W3-01 e W2 | — |
| FR-17-08 | parcial | sem disponibilidade, estimativas e redistribuição | workload, limite de WIP (W3-03) | — |
| FR-17-09 | parcial | sem projetos, campanhas e séries | templates e checklists, template_clone sem responsáveis (W3-03) | — |

## 19.5 Aprendizagem e qualidade

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-10 | por começar | motivo livre, sem taxonomia nem dashboards de retrabalho | rejection_reason texto em guioes | — |
| FR-17-11 | por começar | sem experimentos | nada no código | — |
| FR-17-12 | por começar | sem motor repetir vencedor | nada no código | — |

## 19.6 Continuidade e fiabilidade

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-13 | parcial | sem recuperação de rascunhos após falha | autosave com indicador e lock_version (W2-02) | — |
| FR-17-14 | parcial | worker por alojar | agent_jobs: idempotência, backoff, lease, dead-letter, cancelar; w4_agents 44/44, w4_worker 30/30 | — |
| FR-17-15 | parcial | sem alertas nem dashboard de saúde | correlation_id em audit/transições; agent_job_attempts; estado do worker na UI | — |
| FR-17-16 | por começar | sem centro de integrações | nada no código | — |

## 21. Social accounts e publicação multi-canal

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-21-01 | por começar | sem credenciais por conta social | accounts sem tokens | — |
| FR-21-02 | por começar | sem publicação | nada no código | — |
| FR-21-03 | parcial | importação só por scraping (não API autorizada) | engine/scrape.py; publicacoes | — |
| FR-21-04 | por começar | sem publication_id, janela nem origem | nada no código | — |

## 25. NFRs, qualidade e critérios de lançamento

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-15 | parcial | E2E com conta real no CI por fazer (ADR-0019 pendente) | error.tsx app, c/[ws], global-error, widget-boundary; realtime-hub 9/9; quality.yml; W1-12 | — |

## 30. Centro de Acessos e Permissões (CAP)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| CAP-01 | parcial | registo sem descrição, dono, versão, ações e flag de disponibilidade | tabela capabilities (key, módulo, risco, âmbitos, estado); feature-registry.md | — |
| CAP-02 | parcial | sem filtros por equipa/projeto, ações em lote, exportação, diff e preview antes de guardar | /permissoes por pessoa e por papel; w1_permissions 35/35; W1-08 | — |
| CAP-03 | parcial | sem papéis personalizados versionados nem modelos por profissão; grants só por pessoa | permission_grants allow/deny com prazo, deny prevalece; w1_permissions 35/35 | — |
| CAP-04 | parcial | capacidades de clipping, media, review, publishing, integrations sem uso | capabilities separadas por ação; feature-registry.md | — |
| CAP-05 | parcial | sem simulador "Ver como utilizador"; authorize() só por workspace, sem recurso | authorize(), access_explain "porquê"; w1_permissions 35/35 | — |
| CAP-06 | parcial | sem revisões periódicas de acessos nem revogação de sessões | convites com validade, suspender, remover com reatribuição; w1_clients 55/55 | — |
| CAP-07 | parcial | sem preview de impacto, segunda aprovação nem alertas de grants excessivos | motivo obrigatório, antes/depois no audit (W1-08, W1-09) | — |
| CAP-08 | parcial | convidados com acesso a uma peça por fazer | /clientes e grants por cliente; admin do cliente só o seu; w1_clients 55/55 | — |
| CAP-09 | feito | — | feature-registry.md (regras); flags separadas das capacidades: my_flags não concede acesso, RPCs verificam capacidades (ADR-0031); w0_feature_flags 20/20 | — |

## 31. Equipa, presença e centro operacional

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| OPS-01 | parcial | sem contadores online, disponíveis, em tarefa, ausentes; sem equipa e projeto | /equipa-agencia com estado, último acesso, tarefas abertas (W1-13) | — |
| OPS-02 | por começar | sem presença nem estados manuais | nada no código | — |
| OPS-03 | parcial | sem acknowledge, snooze e delegar | /caixa com filtros por cliente; W3-01 | — |
| OPS-04 | por começar | sem cartões de quem trabalha em quê | nada no código | — |
| OPS-05 | parcial | sem disponibilidade, férias, capacidade semanal e previsão | workload e WIP (W3-03) | — |
| OPS-06 | parcial | sem SLA, escalonamento e substitutos | templates, checklists, dependências (W3-03) | — |
| OPS-07 | parcial | sem timestamps, comparação de versões e acesso externo | comentários com menções nas tarefas (W3-01) | — |
| OPS-08 | parcial | sem relatórios de throughput, lead/cycle time e retrabalho | /historico (W1-09) | — |
| OPS-09 | por começar | sem automação inteligente | nada no código | — |
| OPS-10 | por começar | sem Presence | nada no código | — |

## 32. Mecanismos adicionais para escalar clipping e conteúdo

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| SCALE-01 | por começar | sem linhagem até publicação e métricas | nada além de guião → takes | — |
| SCALE-02 | por começar | sem ingestão em lote | nada no código | — |
| SCALE-03 | por começar | sem clip factory | nada no código | — |
| SCALE-04 | por começar | sem centro de publicação | nada no código | — |
| SCALE-05 | parcial | sem guidelines de marca, verificação factual, áudio, direitos | checklist por cliente (W3-03); rubrica do Crítico no motor | — |
| SCALE-06 | por começar | sem experimentos nem proveniência de métricas | Aprendiz no motor não cobre | — |
| SCALE-07 | parcial | papéis não copiados | workspace_create com estrutura de outro cliente, template_clone (W1-06, W3-03) | — |
| SCALE-08 | por começar | sem portal de cliente | nada no código | — |

## 37. Regras transversais novas

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-16 | por começar | origem sistema/externo inexistente | capacidade performance.origin.override só planeada (feature-registry) | — |
| R-17 | por começar | lista de frases-persona versionada inexistente | persona.manage só planeada; AGENTS §7 | — |
| R-18 | por começar | linhagem no momento da publicação inexistente (sem publicador) | nada no código | — |
| R-19 | adiado | decisão do Tomás 29/10: métricas passam a vir da API oficial no futuro; por agora continua o Apify (engine/scrape.py). Fecha com PERF-08/PLAT-02 | engine/scrape.py ApifyClient; ADR-0005 | — |

## 38. Vista de negócio da agência (BIZ)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| BIZ-01 | por começar | sem contratos nem atingimento de entrega | dashboard.business.read planeada | — |
| BIZ-02 | por começar | sem faixa de atenção | nada no código | — |
| BIZ-03 | por começar | sem KPIs de negócio nem tabela por cliente (Painel da agência só operacional) | agency_dashboard (W1-10) não cobre | — |
| BIZ-04 | por começar | sem vista de negócio | finance.read planeada | — |
| BIZ-05 | por começar | sem contratos | finance.manage planeada | — |
| BIZ-06 | por começar | sem custo humano, ferramentas e margem | só custo de IA por execução (W4) | — |
| BIZ-07 | por começar | sem pré-visualização como papel | access.preview planeada | — |
| BIZ-08 | por começar | sem cargos como modelos (job_title existe mas não pré-preenche grants) | workspace_access.job_title | — |
| BIZ-09 | por começar | sem score de saúde | nada no código | — |

## 39. Ingestão, armazenamento e linha de edição (ING, EDL)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| ING-01 | por começar | sem object storage nem Drive | só bucket branding | — |
| ING-02 | por começar | sem ingestão da câmara | media.ingest planeada | — |
| ING-03 | parcial | sem ingestão do ficheiro da câmara, transcrição com tempos por palavra e sincronização pelo áudio | recording_marks, recording_marks_add, recording_timeline (W5-01, ADR-0026); w5_recording_marks 17/17; e2e/recording-marks.spec.ts 2/2 | — |
| ING-04 | por começar | sem upload pelo telemóvel | nada no código | — |
| EDL-01 | parcial | job do pacote de edição (precisa de ingestão ING-01..03, render e worker alojado) | preset de edição versionado por cliente com o defeito do PRD (edit_presets, edit_preset_save; W5-02, ADR-0027) | — |
| EDL-02 | por começar | sem revisão em lote de variantes | nada no código | — |
| EDL-03 | parcial | ligar ao job do pacote e guardar o relatório por variante na app (EDL-02); calibrar limites no piloto | numeiro-engine #7: engine/qc.py, run.py qc, tests/test_qc.py 11/11 no CI do motor (ADR-0028) | — |
| EDL-04 | por começar | sem biblioteca de vídeos de atenção | nada no código | — |
| EDL-05 | por começar | sem pós-produção multi-agente | nada no código nem no motor | — |
| EDL-06 | por começar | piloto não iniciado | nada no código | — |

## 40. Centro de desempenho (PERF)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PERF-01 | por começar | sem hierarquia criador/conta/camada | accounts sem camada | — |
| PERF-02 | por começar | sem etiquetas à publicação | nada no código | — |
| PERF-03 | por começar | sem fotografias por idade (publicacoes guarda só a última leitura) | publicacoes | — |
| PERF-04 | por começar | sem índice normalizado (só mediana e outliers por scraping) | desempenho RPC bandas | — |
| PERF-05 | por começar | sem métricas por família | nada no código | — |
| PERF-06 | por começar | só vista por conta Instagram | /desempenho por conta | — |
| PERF-07 | por começar | sem alavancas nem relatório semanal | nada no código | — |
| PERF-08 | por começar | sem ligar contas por OAuth | nada no código | — |
| PERF-09 | parcial | só uma leitura por publicação; ligação ao conteúdo por inferência | publicacoes.shares, guiao_id | — |

## 41. Variantes, estilos e republicação (VAR)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| VAR-01 | por começar | sem variantes | nada no código | — |
| VAR-02 | parcial | layouts de S01 a S12 (equipa criativa); render real dos estilos | edit_styles, edit_style_versions, edit_style_save/set_status (W5-02, ADR-0027); w5_edit_styles 34/34; e2e/edit-styles.spec.ts 3/3 | — |
| VAR-03 | por começar | sem motor frase-imagem | nada no código nem no motor | — |
| VAR-04 | por começar | sem verificador de títulos | nada no código | — |
| VAR-05 | por começar | sem republicação | publishing.republish.approve planeada | — |
| VAR-06 | por começar | sem fontes longas no pacote | nada no código | — |
| VAR-07 | por começar | sem distribuição por camadas | nada no código | — |

## 42. Publicação automática e calendário (PUB)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PUB-01 | por começar | sem publicador | nada no código | — |
| PUB-02 | por começar | sem agendador | nada no código | — |
| PUB-03 | adiado | decisão do Tomás 29/10: sem publicação manual, espera pela API oficial (PLAT-03) | — | — |
| PUB-04 | por começar | sem publicações no calendário | limitação W3-02 | — |
| PUB-05 | por começar | sem republicação agendada | nada no código | — |
| PUB-06 | por começar | capacidades só planeadas | publishing.approve planeada | — |

## 43. Aprovações das plataformas (PLAT)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PLAT-01 | bloqueado | precisa do Tomás: domínio próprio, páginas públicas, Business Verification Meta, registo das apps | PRD §44 itens em aberto; produção em clipstudio-jchs.vercel.app | — |
| PLAT-02 | bloqueado | depende de PLAT-01 e de ligar contas + métricas em produção (PERF-08) | nada submetido | — |
| PLAT-03 | bloqueado | depende de PLAT-01 e do publicador (PUB-01) | nada submetido | — |
| PLAT-04 | por começar | sem apps aprovadas a manter | nada submetido | — |
