# Registo de estado dos requisitos

Fonte única do que está feito, parcial, por começar, bloqueado ou adiado (CHG-004). Uma linha por ID do PRD.
Cada PR que mexe na app atualiza as linhas dos IDs que toca; o CI (`scripts/status/check.py`) valida contra o PRD.
O resumo e os pendentes abertos são gerados: `python3 scripts/status/check.py --fix`. "Verificado" é a data da última verificação com conta real (R-15).

<!-- resumo:inicio -->

## Resumo

| Estado | Requisitos |
|---|---|
| feito | 36 |
| parcial | 226 |
| por começar | 51 |
| bloqueado | 3 |
| adiado | 3 |
| **total** | **319** |

## Pendentes abertos (bloqueados primeiro, depois por prioridade)

| ID | P | Estado | O que falta | Título |
|---|---|---|---|---|
| PLAT-01 | P0 | bloqueado | precisa do Tomás: domínio próprio, Business Verification Meta, registo das apps; páginas públicas adiadas pelo Tomás a 2026-11-04 até haver domínio | Pré-requisitos, já |
| PLAT-02 | P0 | bloqueado | depende de PLAT-01 e de ligar contas + métricas em produção (PERF-08) | Fase A, só leitura |
| PLAT-03 | P0 | bloqueado | depende de PLAT-01 e do publicador (PUB-01) | Fase B, publicação |
| FR-01-02 | P0 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Widgets configuráveis por função e por workspace; comparação temporal e explicaç |
| FR-02-01 | P0 | parcial | verificação com sessão real (R-15) da equipa Numeiro | CRUD de guiões, duplicação, arquivo, recuperação e eliminação com confirmação. |
| FR-03-02 | P0 | parcial | verificação com conta real (R-15) | Blocos identificados Hook 1, Hook 2, Body, CTA e personalizados; seleção e repet |
| FR-04-01 | P0 | parcial | sem anexo; edição dos campos da fonte não confirmada | CRUD de fontes com URL, título, origem, data, idioma, autor, tags, categoria, re |
| FR-04-02 | P0 | parcial | sem RSS nem integrações | Adicionar manualmente, por URL, RSS e integrações autorizadas; rastreio de data  |
| FR-06-01 | P0 | parcial | prompt, versão por agente, permissões e limites não constam do catálogo | Catálogo de agentes com função, versão, modelo, prompt, ferramentas, permissões  |
| FR-07-01 | P0 | parcial | sem upload nem captura | Guardar referências por URL, upload ou captura autorizada; metadados e autoria. |
| FR-07-02 | P0 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Classificação por formato, estilo, narrativa, hook, duração, idioma e tags. |
| FR-08-01 | P0 | parcial | verificação com sessão real de um upload grande no R2 (sessão de 2026-11-06) | Upload de vídeo, áudio, imagens, thumbnails, legendas e documentos com progresso |
| FR-08-02 | P0 | parcial | pastas são filtros (campanha, formato, estado, tipo, etiqueta) e pesquisa; verificação com sessão real | Pastas/coleções lógicas por campanha, projeto, formato e estado; pesquisa e tags |
| FR-09-02 | P0 | parcial | só views, likes, comentários, partilhas por scraping; sem alcance, retenção, seguidores, conversões | Métricas por conteúdo e período: views, alcance, interações, retenção, seguidore |
| FR-10-01 | P0 | parcial | verificação com sessão real (R-15) da agência e do cliente (cliente sem Custos) | Consumo de IA por agente, modelo, execução e workspace. |
| FR-11-01 | P0 | parcial | arrastar não verificado em produção; verificação com conta de cliente (R-15); E2E citado não está versionado no repo | Calendário editorial por dia, semana e mês; drag and drop com validação. |
| FR-11-02 | P0 | parcial | verificação com sessão real (R-15) da equipa Numeiro | Tarefas, gravações, revisões, publicações, responsáveis, deadlines e dependência |
| FR-12-02 | P0 | parcial | agendamento por API (PLAT-03/PUB-01); verificação com sessão real (R-15); E2E | Publicação manual com registo de URL e timestamp; agendamento por API quando aut |
| FR-14-01 | P0 | parcial | recuperação por email depende do SMTP do Supabase (limitado) até haver domínio (FR-13-01 adiado); verificação com a conta real do Tomás em produção | Nome, avatar, email verificado, password reset e MFA quando disponível. |
| FR-14-02 | P0 | parcial | idioma só PT-PT; email e resumo pessoais guardados mas sem envio; verificação com sessão real | Idioma, timezone, tema, notificações e preferências do teleprompter. |
| FR-15-01 | P0 | parcial | sem idioma configurável (só PT-PT) | Geral: nome, logótipo, idioma, timezone, moeda e branding. |
| FR-15-02 | P0 | parcial | sem categorias, estados e regras de aprovação configuráveis | Conteúdo: categorias, formatos, estados, templates, regras de aprovação e checkl |
| FR-16-01 | P0 | parcial | verificação com conta real (R-15) dos grupos media, comentários e notificações | Pesquisa global com controlo de acesso em todas as entidades, sugestões e result |
| TEAM-05 | P0 | parcial | âmbitos projeto e assigned_only não aplicados; sem modelos por profissão | Matriz de permissões configurável |
| TEAM-06 | P0 | parcial | tarefa sem projeto (não existem projetos) | Tarefas e responsáveis |
| TEAM-16 | P0 | parcial | faltam exportação, storage de media, pesquisa e realtime com contas reais | Segurança e testes de autorização |
| FR-17-01 | P0 | parcial | filtros guardados no browser; verificação com conta real (R-15) | Inbox unificada por utilizador com tarefas, aprovações, menções, erros de automa |
| FR-17-04 | P0 | parcial | sem variantes, assets e publicações por conta ligadas | Relação um-para-muitos: conteúdo → hooks → takes → variantes → assets → publicaç |
| FR-17-05 | P0 | parcial | verificação com sessão real (R-15) da equipa Numeiro | Transições configuráveis de workflow geram tarefas e notificações idempotentes,  |
| FR-17-13 | P0 | parcial | editar um guião com a conta de cliente (R-15) | Auto-save com indicador persistido, proteção contra alterações concorrentes e re |
| FR-17-14 | P0 | parcial | verificação com carga real (pacote e exports da sessão de 2026-11-06) | Jobs duráveis com idempotency key, retries exponenciais, timeout, dead-letter, c |
| FR-17-15 | P0 | parcial | verificação com sessão real (R-15) do dono da agência; alertas só na app (sem email, FR-13-01 adiado); ver ADR-0058 sobre kinds do worker partilhado | Observabilidade com logs estruturados, correlação por workspace/run/content, ale |
| FR-21-01 | P0 | parcial | OAuth (PLAT-02/03) | permissões e credenciais são por conta. |
| FR-21-02 | P0 | parcial | publicador (PUB-01) tem de voltar a verificar ao publicar | não publicar sem aprovação humana do asset/versão e do destino. |
| CAP-01 | P0 | parcial | registo sem descrição, dono, versão, ações e flag de disponibilidade | Registo central de capacidades |
| CAP-02 | P0 | parcial | sem filtros por equipa/projeto, ações em lote, exportação, diff e preview antes de guardar | Duas matrizes administrativas |
| CAP-03 | P0 | parcial | sem papéis personalizados versionados nem modelos por profissão; grants só por pessoa | Papéis e exceções |
| CAP-04 | P0 | parcial | capacidades de clipping, media, review, publishing, integrations sem uso | Permissões granulares |
| CAP-05 | P0 | parcial | authorize() só por workspace, sem recurso | Avaliação centralizada e explicável |
| CAP-06 | P0 | parcial | sem revisões periódicas de acessos | Gestão de ciclo de vida |
| OPS-01 | P0 | parcial | sem contadores online, disponíveis, em tarefa, ausentes; sem equipa e projeto | Diretório e contadores |
| OPS-02 | P0 | parcial | estado a partir de calendário autorizado; verificação com conta real (R-15) | Estados distintos |
| BIZ-01 | P0 | parcial | filtro de origem (R-16) no cálculo; prazo por vídeo é pressuposto; sem contrato registado no Numeiro | Métrica norte: atingimento de entrega |
| BIZ-02 | P0 | parcial | 3 regras sem dados (saúde a cair, renovação com saúde, posts perto de zero) | Faixa "Precisa da tua atenção" |
| BIZ-03 | P0 | parcial | AGI distinto do MRR (decisão); índice com fotografias por idade (PERF-03); sem contratos nem câmbio registados | KPIs e tabela por cliente |
| ING-01 | P0 | parcial | carregar as gravações da sessão de 2026-11-06; bruto antigo do Drive continua como link | Armazenamento fora da app (decisão) |
| ING-03 | P0 | parcial | verificação com a sessão real (gravação com marcas do teleprompter); ligar edit.package_marks (ADR-0065) | Um ficheiro longo por câmara por sessão |
| EDL-01 | P0 | parcial | verificação com a sessão real de 2026-11-06; deteção de cara para o enquadramento; publicar o worker das janelas pelas marcas e ligar edit.package_marks (W10-17, ADR-0065) | Pacote de edição automático |
| EDL-02 | P0 | parcial | verificação com a sessão real de 2026-11-06 (pacote → exportar todos → rever); versão leve a 540p em vez de 720p (ADR-0052) | Revisão em lote |
| EDL-03 | P0 | parcial | distinct_source só por opção (qc_rules.compare_source); calibrar limites no piloto (EDL-06) | QC técnico em código antes de qualquer revisão por IA |
| EDL-07 | P0 | parcial | ligar edit.ai_visuals, carregar e etiquetar ativos ia-imagem/ia-atencao/ia-musica (a Biblioteca do Numeiro ainda não tem imagens nem áudio); verificação com a sessão real | Documento de edição |
| EDL-08 | P0 | parcial | verificação do Tomás com sessão real a ouvir um vídeo inteiro com o som contínuo (W10-29) | Pré-visualização ao vivo |
| EDL-11 | P0 | parcial | visuais guardados no Supabase Storage ou por link ficam de fora (decisão ADR-0068: a IA só usa R2); verificação com sessão real | Exportar |
| EDL-14 | P0 | parcial | verificação do Tomás com sessão real: editar o corpo num hook e ver nos outros | Corpo partilhado entre hooks (CHG-011) |
| PERF-01 | P0 | parcial | criador/marca é só um campo por conta; verificação com conta real (R-15) | Hierarquia |
| PERF-02 | P0 | parcial | publicador por API (PUB-01); frase-persona não preenchida no registo manual | Etiquetas obrigatórias à publicação (R-18) |
| PERF-03 | P0 | parcial | histórico só desde a primeira captura; 1 h quase nunca existe com scraping diário | Fotografias por idade |
| PERF-04 | P0 | parcial | engagedViews do YouTube (API oficial) | Índice normalizado |
| PERF-05 | P0 | parcial | alcance, retenção, skip rate, seguidores, For You (API oficial); custo por vídeo (BIZ-06) | Métricas por família |
| PERF-06 | P0 | parcial | persona e estilo só com linhagem gravada; canibalização básica | Vistas |
| PERF-09 | P0 | parcial | só uma leitura por publicação; ligação ao conteúdo por inferência | Correções de dados imediatas |
| VAR-01 | P0 | parcial | render das variantes | Receita de variante |
| VAR-02 | P0 | parcial | layouts de S01 a S12 (equipa criativa); render real dos estilos no motor (hoje só no protótipo local); verificação com sessão real | Catálogo de estilos por workspace |
| VAR-04 | P0 | parcial | verificação com sessão real (R-15) depois do deploy do motor; afirmações do corpo não classificadas; idioma por conta de clips | Verificador antes da revisão humana |
| PUB-02 | P0 | parcial | leitura dos limites em tempo real chega com o publicador | Limites das APIs como restrições do agendador |
| PUB-04 | P0 | parcial | quotas de republicação só como aviso; verificação com conta real (R-15) | Calendário de publicações |
| PUB-06 | P0 | parcial | notificações a quem aprova; verificação com conta real (R-15) | Quem aprova |
| GAZE-01 | P0 | parcial | verificação com sessão real no estúdio (iPad a ~2,5 m, R-15) | Coluna do teleprompter ligada à distância |
| GAZE-02 | P0 | parcial | verificação com sessão real no estúdio (R-15) | Linha de foco e modo frase |
| LRN-01 | P0 | parcial | ligar learn.edits; E2E só no CI; verificação com sessão real (R-15) | Motivo em cada edição |
| LRN-02 | P0 | parcial | ligar learn.lessons; verificação com sessão real | Agente "Editor de lições" |
| LRN-03 | P0 | parcial | ligar learn.lessons; verificação com sessão real (R-15) | Aprovação de lições |
| LRN-04 | P0 | parcial | lições da agência aprendidas dos resultados de todos os clientes (hoje só por Propor à agência); verificação com sessão real (R-15) | Dois níveis (decisão) |
| CLIP-01 | P0 | parcial | verificação com sessão real (R-15) e um master real no R2; Drive do cliente como fonte não ligado | Fonte = ficheiro master original |
| CLIP-02 | P0 | parcial | separação de oradores: fornecedor por escolher depois do teste em PT-PT (UNVERIFIED); hoje só tempos por palavra (faster-whisper) | Transcrição com oradores |
| CLIP-03 | P0 | parcial | rubrica e máquinas testadas com episódios reais (piloto CLIP-11); crítica num segundo passo | Agente "Clip Miner": candidatos e ranking |
| CLIP-04 | P0 | parcial | regra final para afirmações sobre terceiros (§46.5, decisão do Tomás); pessoas identificadas só assinaladas | Etiquetas de polémica e portão da dignidade |
| CLIP-05 | P0 | parcial | medir com vídeos reais (contexto perdido, ≤ 30 min por hora de fonte) | Diversidade e cortes limpos |
| CLIP-06 | P0 | parcial | verificação com sessão real com um master real (vista Original vs. cortado no editor) | Preparação do corte |
| CLIP-07 | P0 | parcial | reframe 9:16 com orador ativo (hoje corte ao centro), fontes multi-câmara, verificação com sessão real | Vertical, legendas, estilo e revisão |
| STU-03 | P0 | parcial | verificar com sessão real (cortes curtos por guião → pacote em minutos → notificação agrupada → exportar → rever); disparo pelo agente de estúdio (STU-02) | Pacote de edição por guião |
| FR-01-04 | P1 | parcial | sem calendário compacto no Início | Calendário editorial compacto e atividade recente com ator e timestamp. |
| FR-02-03 | P1 | parcial | título próprio (usa o tema); verificação com conta real (R-15) | Campos: título, cliente/workspace, campanha, tema, formato, plataforma, responsá |
| FR-02-05 | P1 | parcial | verificação com sessão real (R-15) da equipa Numeiro | Enviar para revisão, aprovar/rejeitar/pedir alterações com comentário obrigatóri |
| FR-03-03 | P1 | parcial | verificação com conta de cliente (R-15); E2E citado não está versionado no repo | Espelhamento horizontal e vertical independentes; velocidade, fonte, line-height |
| FR-03-04 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Play/pause, scroll manual, fullscreen por gesto, atalhos configuráveis, controlo |
| FR-03-05 | P1 | parcial | verificação com conta de cliente (R-15); E2E citado não está versionado no repo | Guardado de preferências por utilizador e dispositivo; bloqueio de suspensão qua |
| FR-04-03 | P1 | parcial | sem filtros por categoria, tema, idioma e data; pesquisa simples, não full-text | Filtros por categoria, tema, fonte, idioma, data, estado e pesquisa full-text. |
| FR-04-04 | P1 | parcial | sem favoritos | Estados nova, triagem, selecionada, utilizada, descartada; favoritos, duplicados |
| FR-04-05 | P1 | parcial | sem resumo, relevância e ângulos para fontes adicionadas na app; motor (Repórter) por alojar | Resumo por IA com referências à fonte, classificação de relevância e ângulos sug |
| FR-05-03 | P1 | parcial | verificação com sessão real (R-15) num vídeo guardado e com conta de cliente; vídeos da Drive continuam com o momento escrito à mão e sem desenho (o player da Drive não dá o tempo nem o fotograma) | Revisão de vídeo com player, comentários por timestamp, anotações e histórico. |
| FR-05-04 | P1 | parcial | notificações de guiões dependem de automação configurada; envio fora da app (email) por fazer | Aprovar, rejeitar ou pedir alterações com motivo e notificações. |
| FR-05-05 | P1 | parcial | sem fluxos de aprovação configuráveis (só regras de tarefas por evento) | Fluxos configuráveis de aprovação por workspace/projeto; responsáveis e prazos. |
| FR-06-03 | P1 | parcial | primeira corrida real dos agentes em produção (ainda sem execuções) | Execução manual/agendada, progresso, logs, erros, retry e cancelamento. |
| FR-06-04 | P1 | parcial | sem teste antes de ativar; prompts no código do motor, não versionados na app | Versionamento de prompts/configurações, testes antes de ativar, rollback e audit |
| FR-06-05 | P1 | parcial | sem latência e qualidade por execução | Custos, tokens, latência e qualidade por execução/agente. |
| FR-07-03 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Filtros, favoritos, coleções e pesquisa. |
| FR-07-04 | P1 | parcial | recolha automática depende do APIFY_TOKEN no worker; TikTok só com transcrição colada; verificação com sessão real | Transcrição e análise de estrutura quando tecnicamente e legalmente permitido. |
| FR-08-03 | P1 | parcial | partilha só da versão atual; verificação com sessão real | Pré-visualização, download, links temporários e permissões de partilha. |
| FR-08-04 | P1 | parcial | substituir por versão nova com sessão real; verificação com conta de cliente (R-15) | Versionamento, substituição, histórico e associação a guião/take/publicação. |
| FR-08-05 | P1 | parcial | sem antivírus (decisão em aberto); limite por ficheiro depende do plano Supabase; retenção automática por fazer | Controlo de tipos, tamanho, antivírus quando aplicável, quotas e retenção. |
| FR-09-03 | P1 | parcial | sem definições por plataforma nem indisponibilidade; só Instagram | Definições consistentes por plataforma; mostrar indisponibilidade e data da últi |
| FR-09-04 | P1 | parcial | sem comparação por hooks, temas, campanhas e responsáveis | Comparação de conteúdos, hooks, temas, formatos, campanhas e responsáveis. |
| FR-09-05 | P1 | parcial | sem exportação nem relatórios programados | Rankings, gráficos, exportação e relatórios programados. |
| FR-10-03 | P1 | parcial | sem custos manuais; só moeda do cliente | Custos manuais opcionais por produção, freelancer e projeto; moeda base configur |
| FR-10-04 | P1 | parcial | sem orçamentos, limite soft, alertas nem autorização para ultrapassar | Orçamentos, limites rígidos/soft, alertas e autorização para ultrapassar quota. |
| FR-10-05 | P1 | parcial | custo por vídeo (sem custos de render) | Custo por guião, vídeo e publicação; tendência mensal e exportação. |
| FR-11-03 | P1 | parcial | sem vistas por equipa, plataforma, campanha; sem deteção de conflitos | Vistas por equipa, plataforma, campanha e estado; conflitos e atrasos destacados |
| FR-11-04 | P1 | parcial | ligar a flag notifications.deadlines e verificar com sessão real (R-15) | Templates de produção, checklist por conteúdo e notificações. |
| FR-11-05 | P1 | parcial | sem ficheiros, revisões nem publicações ligadas | Links para guiões, ficheiros, revisões e publicações. |
| FR-13-03 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Múltiplos workspaces por utilizador, papéis independentes e mudança de contexto  |
| FR-13-04 | P1 | parcial | sem transferência de propriedade | Desativar membro, transferir propriedade, impedir remoção do último Owner. |
| FR-13-05 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Auditoria de convites, alterações de papéis e ações críticas. |
| FR-14-03 | P1 | parcial | terminar uma sessão noutro dispositivo do dono e confirmar o JWT recusado (precisa do telemóvel do dono) | Sessões/dispositivos ativos, terminar sessões e histórico de segurança. |
| FR-14-05 | P1 | parcial | política de eliminação | Exportação dos próprios dados e pedido de eliminação conforme política. |
| FR-15-03 | P1 | parcial | ligar e renovar indisponíveis sem OAuth; testar só recolha de métricas e motor | Integrações: conectar, testar, renovar, revogar e ver saúde de cada integração. |
| FR-15-04 | P1 | parcial | sem política de aprovação de IA nas definições | IA: prompts, modelos, limites, permissões e política de aprovação. |
| FR-15-05 | P1 | parcial | envio de email e resumo diário (FR-13-01 adiado); verificação com sessão real | Notificações: canais, eventos e preferências organizacionais. |
| FR-16-03 | P1 | parcial | sem preferências de notificação; deep links não confirmados para todos os tipos | Inbox de notificações, marcar como lida, deep links e preferências. |
| FR-16-04 | P1 | parcial | sem notificações de integrações | Menções, atribuições, aprovações, falhas de automação e integrações. |
| FR-16-05 | P1 | parcial | verificação com conta real (R-15); E2E da pesquisa com dois clientes para os tipos novos | Evitar notificação de dados de outros workspaces e impedir vazamento em resultad |
| TEAM-07 | P1 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Dashboard por âmbito |
| TEAM-08 | P1 | parcial | sem equipas funcionais | Equipas funcionais e capacidade |
| TEAM-09 | P1 | parcial | sem etapas, aprovadores e SLA por tipo de conteúdo | Workflow adaptável por cliente |
| TEAM-10 | P1 | parcial | diretor criativo tratado como lado da agência (decisão); verificação com conta real (R-15) | Aprovações sem conflito |
| TEAM-11 | P1 | parcial | sem acesso limitado a projetos/tarefas para convidados | Freelancer/guest |
| TEAM-12 | P1 | parcial | ligar a flag notifications.deadlines e verificar com sessão real (R-15) | Notificações direcionadas |
| TEAM-13 | P1 | parcial | sem definições da agência nem /perfil | Separação de settings |
| TEAM-14 | P1 | parcial | sem ficheiros brutos, versões de edição, clips e entregas | Produção e edição |
| TEAM-15 | P1 | parcial | sair da equipa não pede reatribuição | Transferência e offboarding |
| FR-17-02 | P1 | parcial | sem feedback do cliente nem material entregue | Caixa de entrada por workspace com triagem de novas fontes, pedidos do talento,  |
| FR-17-06 | P1 | parcial | sem SLA nem escalonamento; fila de exceções com sem responsável, erro de automação e atrasos (W10-14); faltam erro de upload e publicação falhada | Regras de escalonamento por SLA e fila de exceções (sem responsável, atraso, err |
| FR-17-07 | P1 | parcial | seleção só dentro de um dia; verificação com conta real (R-15) | Operações em lote: atribuir, categorizar, aprovar quando permitido, exportar e r |
| FR-17-08 | P1 | parcial | sem disponibilidade, estimativas e redistribuição | Gestão de capacidade por pessoa e equipa: disponibilidade, estimativas, WIP limi |
| FR-17-09 | P1 | parcial | sem projetos, campanhas e séries | Templates de projetos, campanhas, séries e checklists; clonagem segura sem copia |
| FR-17-10 | P1 | parcial | etapa vídeo (sem revisão de media); verificação com conta real (R-15) | Taxonomia de motivos de rejeição por guião e vídeo; dashboards de retrabalho por |
| FR-17-11 | P1 | parcial | dados reais: publicações com índice (depende de PERF-08) | Experimentos de hooks/formatos com hipótese, variantes, contas, janela de mediçã |
| FR-17-12 | P1 | parcial | vencedor sem guião ligado não se repete | Motor “repetir vencedor” cria proposta de continuação/variação ligada à publicaç |
| FR-17-16 | P1 | parcial | OAuth real (PLAT-01..03); Drive, R2 e Resend por ligar | Centro de integrações com estado da ligação, última sincronização, limites e per |
| FR-21-03 | P1 | parcial | importação só por scraping (não API autorizada) | importação manual e sync via API autorizada. |
| FR-21-04 | P1 | parcial | publicador por API (PUB-01) chama _pub_link_lineage; verificação com sessão real | atribuição de métricas por publication_id, janela e origem. |
| CAP-07 | P1 | parcial | sem preview de impacto, segunda aprovação nem alertas de grants excessivos | Controlo de mudanças sensíveis |
| CAP-08 | P1 | parcial | convidados com acesso a uma peça por fazer | Interface multi-cliente |
| OPS-05 | P1 | parcial | sem disponibilidade, férias, capacidade semanal e previsão | Capacidade e workload |
| OPS-06 | P1 | parcial | sem SLA, escalonamento e substitutos | Planeamento e handoffs |
| OPS-07 | P1 | parcial | comparação de versões e acesso externo restrito por recurso | Colaboração e revisão |
| OPS-08 | P1 | parcial | sem relatórios de throughput, lead/cycle time e retrabalho | Auditoria de operações |
| OPS-10 | P1 | parcial | Realtime Presence track e Broadcast para colaboração (decisão); verificação com conta real (R-15) | Presença segura |
| SCALE-03 | P1 | parcial | transcrição pesquisável e múltiplos formatos; ver CLIP-01..07 | Clip factory: |
| SCALE-05 | P1 | parcial | sem guidelines de marca, áudio, direitos; verificação factual só marca (VAR-04), não confirma na fonte | Quality gates: |
| SCALE-06 | P1 | parcial | recomendações só de leitura; limiares por calibrar | Learning loop: |
| BIZ-05 | P1 | parcial | registar o contrato real do Numeiro e o câmbio (dono) e ver MRR/margem | Contratos por cliente |
| BIZ-06 | P1 | parcial | custo de IA só em EUR; verificação com conta real (R-15) | Custos e margem por cliente |
| BIZ-08 | P1 | parcial | verificação com sessão real (convite com cargo) | Cargos como modelos de permissões |
| EDL-10 | P1 | parcial | imagem no palco (EDL-08); verificação com sessão real de cliente (R-15) a usar uma alternativa da IA | Modo guiado |
| EDL-13 | P1 | parcial | verificação com sessão real (pacote com estilo guardado → v1 com o aspeto e a música) | Estilos guardados |
| EDL-15 | P1 | parcial | verificação do Tomás com sessão real (imagens, exportar a partir do quadro) | Vídeos por guião (CHG-011) |
| PERF-07 | P1 | parcial | o motor (Aprendiz/Estratega) ainda não lê as alavancas | Alavancas "o que replicar" |
| REF-01 | P1 | parcial | campo só no espaço do cliente (agência sem biblioteca, REF-07); links curtos do TikTok não resolvidos; verificação com sessão real (R-15) | Colar link |
| REF-02 | P1 | parcial | deploy do worker (numeiro-engine#19) e APIFY_TOKEN no worker (não verificado); verificação com sessão real (R-15) | Dissecção visível |
| REF-03 | P1 | parcial | deploy do worker; calibrar limites de semelhança (pressuposto); verificador factual (VAR-04); verificação com sessão real | Adaptação ao cliente: 3 guiões por link (decisão), cada um com 3 hooks |
| REF-04 | P1 | parcial | topo da fila do teleprompter, modo rápido pelo telemóvel (ING-04), estilo extraído (REF-05); meta de 10 min por medir | Via rápida |
| REF-07 | P1 | parcial | verificação com sessão real da agência e de um cliente | Biblioteca de estilos da agência |
| REF-08 | P1 | parcial | render por parâmetros para chaves diferentes das do motor (REF-05); verificação com sessão real | Importar para um cliente |
| REACT-01 | P1 | parcial | agente diário de descoberta a correr e verificado com sessão real; aprendizagem da descoberta com aceitar/rejeitar | Fontes vigiadas e descoberta de contas |
| REACT-02 | P1 | parcial | recolha diária pelo agente (tarefa agendada) e classificação do tipo de vídeo por frames; verificação com sessão real | Recolha de takes |
| REACT-03 | P1 | parcial | avaliação feita pelo agente em cada corrida; calibração | Avaliação pela IA |
| REACT-04 | P1 | parcial | verificação com sessão de cliente (equipa do Numeiro) depois de ligar a flag para todos; agente diário a correr | Tab Reacts |
| REACT-05 | P1 | parcial | verificação com sessão real; excerto do original no editor | Gravar a partir de um react |
| REACT-06 | P1 | parcial | lições LRN a partir das decisões e relatório de calibração | Aprendizagem |
| REACT-08 | P1 | parcial | verificação em sessão real de cliente (flag reacts.radar só equipa da agência); recolha pela API oficial quando houver OAuth (R-19) | Comentários como fonte de ideias (CHG-010) |
| FR-01-06 | P2 | parcial | filtros persistentes por utilizador por fazer | Estados vazios explicativos, loading, erro/retry, filtros persistentes por utili |
| FR-02-07 | P2 | parcial | sem pesquisa, ordenação, vistas guardadas nem impressão | Filtros, pesquisa, ordenação, vistas guardadas, exportação e impressão. |
| FR-03-06 | P2 | parcial | sem anexar ficheiro ao take | Marcar take gravado, adicionar notas e anexar ficheiro, sem alterar estado edito |
| FR-03-07 | P2 | parcial | não abre sem rede | Fallback de fullscreen/wake lock, falhas de gravação visíveis, estado offline e  |
| FR-04-06 | P2 | parcial | sem controlo de cópias não autorizadas | Converter fonte em guião ou ligar múltiplas fontes a um guião; evitar cópias não |
| FR-04-07 | P2 | parcial | sem feed por utilizador nem exclusões | Feed personalizado por workspace e utilizador; configurações de tópicos e exclus |
| FR-05-06 | P2 | parcial | bloqueio de publicação sem publicador (PUB-01); comparação só de guiões (vídeos não); verificação com conta real (R-15) | Comparação entre versões e bloqueio de publicação sem aprovação exigida. |
| FR-05-07 | P2 | parcial | só guiões (sem vídeo) | Registo de decisões e auditoria de alterações após aprovação. |
| FR-06-06 | P2 | parcial | aprovação não configurável; sem bloqueio de dados sensíveis | Aprovação humana configurável antes de criar guião ou publicar resultado; bloque |
| FR-06-07 | P2 | parcial | sem biblioteca de templates de agentes | Biblioteca de templates de agentes, duplicação entre workspaces sem copiar dados |
| FR-07-06 | P2 | parcial | métricas vêm de scraping, não de API oficial (conflito com R-19) | Indicadores de desempenho apenas quando obtidos por API ou fonte autorizada, com |
| FR-08-06 | P2 | parcial | eliminação automática no fim do prazo e limpeza agendada de órfãos (job com credenciais); custo em euros sem preço por GB | Eliminação reversível, gestão de órfãos e custos de armazenamento. |
| FR-09-06 | P2 | parcial | ligação guião-publicação por inferência do motor (Aprendiz), sem regra contra dupla contagem | Atribuir métricas ao conteúdo publicado e ao guião original; evitar dupla contag |
| FR-10-06 | P2 | parcial | sem distinção estimado/confirmado; câmbio fixo na tabela de preços | Diferenciar custo estimado de custo confirmado e guardar taxa de câmbio utilizad |
| FR-13-06 | P2 | parcial | sem grupos/equipas | Gestão de grupos/equipas e atribuição de tarefas, sem permissões implícitas. |
| FR-15-06 | P2 | parcial | sem MFA, políticas de sessão, exportação e retenção | Segurança: MFA obrigatória opcional, políticas de sessão, logs, exportação e ret |
| FR-15-07 | P2 | parcial | sem importação/exportação nem política de eliminação | Dados: importação/exportação, soft-delete, recuperação e política de eliminação. |
| FR-15-08 | P2 | parcial | sem transferir propriedade nem eliminar | Administração de workspace: transferir propriedade, arquivar e eliminar com conf |
| SCALE-07 | P2 | parcial | papéis não copiados | Templates de operação: |
| SCALE-08 | P2 | parcial | revisão de vídeos pelo cliente; relatórios para enviar; notificar o cliente do que espera por ele; escolher outro mês nas entregas; verificação com sessão real | Portal de cliente: |
| REACT-07 | P2 | parcial | agente diário a renovar links | Agendamento e frescura |
| R-01 | — | parcial | caminho do código de equipa (legacy_can) sem identidade individual; storage de media e pesquisa por fazer | Toda a leitura/escrita de dados de negócio deve ser autorizada no servidor com b |
| R-02 | — | parcial | pesquisa e storage de media inexistentes; tabelas legadas usam client_id texto em vez de workspace_id | Todas as tabelas de negócio multi-tenant têm workspace_id, FK e RLS; storage, pe |
| R-04 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Dashboard global da agência agrega apenas workspaces autorizados; o cliente vê a |
| R-05 | — | parcial | recusas gravadas por um segundo pedido da sessão (melhor-esforço; o RAISE LOG continua a fonte completa); código de equipa (anónimo) não regista; verificação com conta real (R-15) | Todas as ações críticas são auditáveis com ator, afiliação, âmbito, recurso, dat |
| R-07 | — | parcial | sem padrão comum de retry em todas as ações; media e publicação por fazer | Falhas de rede não podem aparentar sucesso; ações assíncronas apresentam estado  |
| R-08 | — | parcial | sem operações externas nem publicações com chave de idempotência (só jobs internos) | Operações externas e publicações têm chave de idempotência. |
| R-09 | — | parcial | soft-delete só em guiões, referências e clientes; sem política de eliminação | Timestamps UTC e timezone por workspace; soft-delete com recuperação controlada. |
| R-10 | — | parcial | internacionalização não preparada (strings fixas em PT-PT); tratamento de conteúdo de IA como não confiável não testado | Conteúdo externo e de IA é dado não confiável; PT-PT inicial com internacionaliz |
| R-11 | — | parcial | canais realtime já abertos e URLs assinados já emitidos valem até ao prazo (proxy/rotação); pesquisa e media protegida por confirmar com contas reais | Desativar uma conta, retirar atribuição ou reduzir permissões revoga imediatamen |
| FL-01 | — | parcial | convites sem email; fluxo completo com contas reais não testado | criar conta → verificar email → criar workspace → escolher timezone/moeda → conv |
| FL-02 | — | parcial | sem comentários no guião | adicionar fonte → classificar → associar referência → criar guião → editar hooks |
| FL-03 | — | parcial | sem associar media nem revisão de vídeo | guião aprovado → calendarizar → abrir fila → teleprompter → gravar múltiplos tak |
| FL-05 | — | parcial | primeira corrida real em produção (fonte → proposta → revisão) | fonte → agente gera proposta → revisão humana → criar versão de guião → registar |
| FL-06 | — | parcial | pesquisa e ficheiros inexistentes; custos por cliente só nos agentes | membro de A e B alterna contexto → pesquisa, dashboard, notificações, ficheiros, |
| FL-07 | — | parcial | uploads/downloads protegidos: URLs assinados já emitidos valem até ao prazo | remover membro → revogar sessões/permissões → preservar autoria e audit log → bl |
| FL-08 | — | parcial | sem recuperação de rascunho local após falha | falha de rede durante edição → estado de erro → recuperação do rascunho e retry  |
| MIG-01 | — | parcial | sem staging; backup não documentado | Inventariar SQL, tabelas, views, RLS, RPCs studio_whoami e guiao_update no Supab |
| MIG-04 | — | parcial | código de equipa partilhado ainda ativo, sem expiração nem limite de tentativas | Migrar códigos de equipa/localStorage para Supabase Auth e sessões geridas; perí |
| MIG-05 | — | parcial | sem entidade content_item separada (guioes continua tabela principal) | Migrar Guiao para content_item + content_versions, mantendo compatibilidade de l |
| MIG-06 | — | parcial | ideas não migrada para sources; take_numeiro mantido, sem editorial_angle | Migrar Idea para sources, removendo take_numeiro em favor de editorial_angle gen |
| MIG-07 | — | parcial | faltam /perfil e /publicacoes | Criar rotas reais para módulos existentes no menu e novas páginas /fontes, /equi |
| MIG-09 | — | parcial | dual-read e plano de rollback testado por módulo; verificação com conta real (R-15) | Introduzir feature flags por workspace para migração progressiva, dual-read limi |
| MIG-10 | — | parcial | RPCs e token legado (studio_whoami, legacy_can, studio_tokens) ainda ativos | Remover RPCs e credenciais legadas só depois de validação e reconciliação de dad |
| QA-02 | — | parcial | storage de media e realtime por cliente sem E2E dedicado | User A tentar ler/alterar workspace B por URL/API/RPC/realtime/storage |
| QA-03 | — | parcial | membro removido e convite expirado com conta real em produção | Convite expirado, sessão revogada, membro removido |
| QA-04 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Criar/editar/submeter/aprovar guião e editar após aprovação |
| QA-06 | — | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | Teleprompter: troca de data, espelho, atalhos, sessão interrompida |
| QA-07 | — | parcial | E2E com várias versões do mesmo vídeo (comentários e desenhos presos a cada versão) | Revisão com comentários timestamp e múltiplas versões |
| QA-11 | — | parcial | falha/orçamento com o worker real em produção | Agente IA falha ou excede orçamento |
| QA-13 | — | parcial | teste com sessão ativa real em produção | Mudança de role durante sessão ativa |
| QA-14 | — | parcial | axe só no estado inicial das rotas (folhas, diálogos e teleprompter a gravar por analisar); moderate/minor e tema claro por auditar; verificação manual em iPad real | Utilização mobile/tablet e teclado |
| QA-15 | — | parcial | RPO e RTO de produção UNVERIFIED (plano, backups, PITR no painel do Supabase); ensaio em staging; cópia fora do Supabase | Backup e restauro de amostra |
| QA-16 | — | parcial | papéis viewer/reviewer do cliente e código de equipa na mesma matriz; forçar falha de widget e de pedido com conta | Abrir cada rota com conta de agência, conta de cliente e código de equipa, com t |
| R-15 | — | parcial | verificação com sessão real (agência e cliente) no preview/produção das mudanças de navegação do W10-05 (folha do menu no telemóvel); E2E com conta real já corre no CI (job e2e) | Nenhuma página pode cair no erro genérico do browser ou do Next ("This page coul |
| R-16 | — | parcial | correspondência por impressão digital com os nossos renders | Origem de cada publicação. |
| R-17 | — | parcial | verificação com sessão real (R-15); lista do Numeiro por preencher | Hipérbole de persona. |
| R-18 | — | parcial | publicador por API (PUB-01); formato de reels.id no TikTok/YouTube por confirmar | Linhagem gravada no momento. |

<!-- resumo:fim -->


## Regras globais

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-01 | parcial | caminho do código de equipa (legacy_can) sem identidade individual; storage de media e pesquisa por fazer | authorize() em w1_identity_core, w1_data_access_cutover; w1_isolation 38/38; ADR-0001 | — |
| R-02 | parcial | pesquisa e storage de media inexistentes; tabelas legadas usam client_id texto em vez de workspace_id | RLS por authorize(); bucket branding; canais agents:<ws>; w4_engine_isolation 23/23; W4-03 | — |
| R-03 | feito |  | W1-11 cliente único, w1_invite_isolation 23/23; workspace_access por papel; w1_clients 55/55 | — |
| R-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | agency_dashboard só clientes autorizados; w1_dashboard 38/38; W1-10, ADR-0017 (sem sessão real no painel) | — |
| R-05 | parcial | recusas gravadas por um segundo pedido da sessão (melhor-esforço; o RAISE LOG continua a fonte completa); código de equipa (anónimo) não regista; verificação com conta real (R-15) | audit_events append-only; /historico W1-09; w1_audit 16/16; limitação W1 no CHANGELOG; W10-16 access.denied em audit_events via audit_denied_record (fetch do cliente Supabase, browser e /api), separador Tentativas recusadas (audit_denials_list); w10_auditoria_negacoes 35/35; denials 27/27; ADR-0066 | — |
| R-06 | feito |  | content_versions imutáveis, approved_version_id, estados separados; w2_content 47/47; ADR-0002 | — |
| R-07 | parcial | sem padrão comum de retry em todas as ações; media e publicação por fazer | error boundaries W1-12; autosave com conflito W2-02; takes offline W2-05; ADR-0019 | — |
| R-08 | parcial | sem operações externas nem publicações com chave de idempotência (só jobs internos) | agent_jobs idempotency, eventos de tarefas, takes offline sem duplicar; w4_agents, w3_tasks | — |
| R-09 | parcial | soft-delete só em guiões, referências e clientes; sem política de eliminação | timestamptz + fuso por cliente (W1-07); arquivo/recuperar em W2-02, W1-06; W5-16: guião eliminado escondido do editor, pacote, revisão e lote; _content_deleted sem oráculo entre clientes (PENDING_w5_auditoria_fix.sql) | — |
| R-10 | parcial | internacionalização não preparada (strings fixas em PT-PT); tratamento de conteúdo de IA como não confiável não testado | UI PT-PT; definicoes diz "único idioma por agora"; guiões do motor entram em revisão | — |
| R-11 | parcial | canais realtime já abertos e URLs assinados já emitidos valem até ao prazo (proxy/rotação); pesquisa e media protegida por confirmar com contas reais | authorize() a cada pedido; member_update/member_remove; w1_team 21/21, w3_tasks (perde acesso); W10-08: sessão terminada recusada no pedido seguinte (_session_alive em _mfa_ok); quem perde o último acesso fica sem sessões; w10_sessoes 44/44 | — |
| R-12 | feito |  | grant_set sem auto-elevação e teto; invite_member com teto; w1_permissions 35/35, w1_team, w1_agency_team 24/24 | — |
| R-13 | feito |  | W1-11 espaços agência/cliente, ADR-0018; w1_invite_isolation 23/23; e2e/isolation.spec.ts e routes.spec.ts no CI | 2026-10-29 (E2E) |
| R-14 | feito |  | w1_invite_isolation 23/23; W1-13 staff de cliente não entra na agência; w1_agency_team 24/24; e2e/isolation.spec.ts no CI | 2026-10-29 (E2E) |

## M01 — Início / Dashboard

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-01-01 | feito |  | W1-10 _dashboard_kpis; w1_dashboard 38/38; E2E 16/16; sessão real em /c/numeiro | 2026-10-29 |
| FR-01-02 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | dashboard_widgets/dashboard_layouts, Personalizar, ⓘ; w1_dashboard 38/38; W1-10; W10-22: Formatos de hoje e Guiões de hoje sem guiões arquivados nem eliminados (src/lib/today-format.ts; today-format 5/5) | — |
| FR-01-03 | feito | — | A minha fila no Início (my_queue, W6, ADR-0034); w6_ops 77/77; e2e/ops.spec.ts; produção 06/11: A minha fila no Início com dados reais (23 aprovações = 23 guiões em revisão na base), 0 erros na consola; produção 06/11 com conta de cliente (flags ops.workspace, busca.global e ops.team_presence ligadas só para o Numeiro (all) a 06/11 19:33 com autorização do Tomás, auditado): A minha fila no Início com zeros corretos para um contributor, 0 erros | 2026-11-06 (agência e cliente, produção) |
| FR-01-04 | parcial | sem calendário compacto no Início | panel.activity no Início (W1-10); calendário só em /calendario | — |
| FR-01-05 | feito | — | ações rápidas na paleta conforme as capacidades (W7, ADR-0035); e2e/busca.spec.ts; produção 06/11: ações rápidas na paleta (Novo guião criado e aberto); produção 06/11 com conta de cliente (contributor): ações rápidas só Novo guião e Nova fonte (sem campanha nem tarefa, que o dono tem), sem seletor de clientes | 2026-11-06 (agência e cliente, produção) |
| FR-01-06 | parcial | filtros persistentes por utilizador por fazer | W1-10 indica FR-01-06 parcial; route-error, widget-boundary, dashboard-skeleton | — |

## M02 — Guiões

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-02-01 | parcial | verificação com sessão real (R-15) da equipa Numeiro | content_create/duplicate, arquivar/recuperar; w2_content 47/47; W2-02; eliminação definitiva como lápide com confirmação e recuperação 30 dias (W9-01, ADR-0051); w9_guioes_eliminar 36/36; migração aplicada em produção 2026-11-06; auditoria W5-16: eliminado não volta pelo editor/pacote/revisão/lote; w5_auditoria_isolamento 86/86 (94 com W5-14) | — |
| FR-02-02 | feito |  | editor por blocos com autosave e indicador W2-02; content_save; comentários no cartão do guião (W2-06 content_comments (bloco, frase citada, versão, respostas, resolver), /c/[ws]/revisao; w2_review_comments 33/33; e2e/review.spec.ts 3/3; ADR-0025) | 2026-10-29 (E2E) |
| FR-02-03 | parcial | título próprio (usa o tema); verificação com conta real (R-15) | guioes: título, cliente, tema, formato, data; fontes ligadas (content_sources); campanha, responsável, plataformas, etiquetas (content_meta_set, projects; W2-07, ADR-0029); w2_content_meta 30/30; e2e/content-meta.spec.ts | — |
| FR-02-04 | feito |  | editorial_status e production_status independentes; w2_content 47/47, w3_calendar 39/39 | — |
| FR-02-05 | parcial | verificação com sessão real (R-15) da equipa Numeiro | content_transition com motivo obrigatório na rejeição; W2-02; w2_content; aprovar em lote os guiões gravados, presos à versão gravada (W9-02); w9_aprovar_gravados 25/25; migração aplicada em produção 2026-11-06 | — |
| FR-02-06 | feito | — | content_history, content_restore_version, lock_version; guiao-history.tsx; W2-02; W10-13: comparar duas versões palavra a palavra (lado a lado e em linha, marcadores −/+), aprovada/gravada/em vigor marcadas, Restaurar esta versão com confirmação pelo content_restore_version (PT409 em conflito) e auditado; w10_diff_versoes 25/25; version-diff 22/22; e2e/diff-versoes.spec.ts; produção 06/11: histórico e comparação lado a lado do guião 22 (gravada/em vigor marcadas); guião TESTE: restaurar v1 com confirmação, working copy reposta e script.version_restored auditado; produção 06/11 com conta de cliente: histórico e comparação do guião 22, Restaurar disponível, sem Aprovar/Rejeitar (contributor), 0 erros | 2026-11-06 (agência e cliente, produção) |
| FR-02-07 | parcial | sem pesquisa, ordenação, vistas guardadas nem impressão | filtros por estado e Exportar .txt em guioes/page.tsx | — |
| FR-02-08 | por começar | sem sugestões de IA no editor | nada no código | — |

## M03 — Teleprompter

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-03-01 | feito | — | recording_session_open, recording_queue_set; w2_teleprompter 52/52; W2-05; filtros por campanha e responsável na fila (W2-07, ADR-0029); e2e/content-meta.spec.ts; produção 03/11: fila de 30/10 com 23 gravados, filtros de campanha e responsável; produção 06/11 com conta de cliente (contributor do Numeiro): fila do teleprompter de hoje com 30 guiões e filtros, 0 erros; W10-25: filtro Só aprovados na fila do teleprompter, guardado no dispositivo (09/11) | 2026-11-06 (agência e cliente, produção) |
| FR-03-02 | parcial | verificação com conta real (R-15) | blocos Hook/Body/CTA e takes (take_create/update); w2_teleprompter 52/52; blocos personalizados ## no corpo (W2-08, ADR-0030); w2_custom_blocks 12/12; e2e/custom-blocks.spec.ts | — |
| FR-03-03 | parcial | verificação com conta de cliente (R-15); E2E citado não está versionado no repo | espelho H/V, velocidade, letra, entrelinha, margens, contraste; W2-05; E2E 28/28 (não versionado); produção 03/11: espelho horizontal ligado sem mexer no vertical | 2026-11-03 (sessão real do dono da agência, produção) |
| FR-03-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | play/pause, scroll, ecrã inteiro por duplo toque, atalhos BT; teleprompter/prompter.tsx; W2-05 | — |
| FR-03-05 | parcial | verificação com conta de cliente (R-15); E2E citado não está versionado no repo | teleprompter_prefs por utilizador e dispositivo, wakeLock; tp_prefs_get/set; w2_teleprompter; produção 03/11: espelho guardado na conta e mantido depois de recarregar (reposto a seguir); chaves do olhar (distance_m, screen_in, column_fit, focus_pct, phrase_mode) validadas em _tp_prefs_clean; w10_teleprompter_olhar 15/15; e2e/teleprompter-gaze.spec.ts guarda e recarrega (W10-11) | 2026-11-03 (sessão real do dono da agência, produção) |
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
| FR-05-03 | parcial | verificação com sessão real (R-15) num vídeo guardado e com conta de cliente; vídeos da Drive continuam com o momento escrito à mão e sem desenho (o player da Drive não dá o tempo nem o fotograma) | W5-04 sobre a biblioteca (W8): media_review_list/detail/comment (t_ms)/decide, /c/[ws]/revisao?ver=videos com player da Drive; w5_media_review 31/31; media-time 18/18; ADR-0043, CHG-006; produção 03/11: separador Vídeos com estado vazio, flag media.library em all no Numeiro; W10-15 desenho no fotograma (caneta, seta, retângulo, círculo, cor, desfazer; rato, caneta e toque) preso ao comentário, vetores normalizados em media_comments.annotation validados em _review_annotation, sobreposição a ±0,5 s e ao clicar, marcas na linha do tempo; w10_anotacoes 49/49; annotation 57/57; E2E review-stored 6/6; ADR-0067 | 2026-11-03 (sessão real do dono da agência, produção) |
| FR-05-04 | parcial | notificações de guiões dependem de automação configurada; envio fora da app (email) por fazer | content_transition com motivo; task_rules W3-01; ; vídeo: media_review_decide com motivo obrigatório (W5-04); vídeo: notificações video_decision/video_comment por trigger, idempotentes, com preferências (W5-05, ADR-0044); w5_media_review_notif 16/16; produção 03/11 (sessão real do dono): preferências mostram os dois tipos novos; link ?asset= abre o painel e mostra erro com Tentar de novo para vídeo inexistente; 0 erros na consola | 2026-11-03 (sessão real do dono da agência, produção) |
| FR-05-05 | parcial | sem fluxos de aprovação configuráveis (só regras de tarefas por evento) | task_rule_save W3-01 | — |
| FR-05-06 | parcial | bloqueio de publicação sem publicador (PUB-01); comparação só de guiões (vídeos não); verificação com conta real (R-15) | content_history; approved_version_id; W10-13: comparação entre versões de guião (diff por palavra, versão aprovada e gravada marcadas); w10_diff_versoes 25/25 | — |
| FR-05-07 | parcial | só guiões (sem vídeo) | content_transitions append-only, validacao_anulada no audit; w1_review_fixes 11/11; W10-13: restauro de versão auditado (script.version_restored com versão de origem e estado antes/depois) e visível no histórico | — |

## M06 — Agentes IA

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-06-01 | parcial | prompt, versão por agente, permissões e limites não constam do catálogo | agent_definitions (etapa, modelo, ferramentas, lê/escreve); W4-01 | — |
| FR-06-02 | feito |  | agent_config_versions com language, voice, guardrails, formats, news_beats, metas; w4_agents 44/44 | — |
| FR-06-03 | parcial | primeira corrida real dos agentes em produção (ainda sem execuções) | agent_jobs, cancel/retry, progresso; w4_worker 30/30; test_worker 19/19; worker numeiro-engine alojado no Railway e ligado à produção (2026-11-05) | — |
| FR-06-04 | parcial | sem teste antes de ativar; prompts no código do motor, não versionados na app | agent_config_save/activate (rollback), auditado; w4_agents 44/44 | — |
| FR-06-05 | parcial | sem latência e qualidade por execução | tokens e custo por chamada (W4-02, W4-02b); agent_tool_prices; worker numeiro-engine alojado no Railway e ligado à produção (2026-11-05) | — |
| FR-06-06 | parcial | aprovação não configurável; sem bloqueio de dados sensíveis | guiões do worker entram em revisão (worker_save_script); W4-02 | — |
| FR-06-07 | parcial | sem biblioteca de templates de agentes | workspace_create copia formatos e regras sem voz nem dados (W1-06) | — |

## M07 — Referências

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-07-01 | parcial | sem upload nem captura | reference_create por link e a partir de reels; w2_references 36/36; colar link de Reel/TikTok com deteção do mesmo vídeo (W10-04) | — |
| FR-07-02 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | classificação formato, estilo, narrativa, hook, duração, idioma, tags; w2_references 36/36; W2-04 | — |
| FR-07-03 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | filtros, favoritos, coleções, pesquisa; references_list; W2-04; E2E 13/13 (não versionado) | — |
| FR-07-04 | parcial | recolha automática depende do APIFY_TOKEN no worker; TikTok só com transcrição colada; verificação com sessão real | script_analysis do motor; references_discover; dissecção de referências por link com transcrição recolhida ou colada (W10-04, ADR-0059) | — |
| FR-07-05 | feito |  | reference_link a guiões e fontes, URL original; w2_references 36/36 | — |
| FR-07-06 | parcial | métricas vêm de scraping, não de API oficial (conflito com R-19) | "scraper · data" na UI; ADR-0005 | — |

## M08 — Biblioteca

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-08-01 | parcial | verificação com sessão real de um upload grande no R2 (sessão de 2026-11-06) | biblioteca /c/[ws]/biblioteca com upload, progresso e retentativa (ADR-0038); w8_media 117; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção; R2 por cliente com envio por partes até 50 GiB e SHA-256 incremental no browser, verificação pelo worker (W5-07, ADR-0047); W10-28: refazer a versão leve de um vídeo pronto (media_proxy_redo, botão na Biblioteca, motor proxy_only; ADR-0076; w10_refazer_versao_leve 19/19); W10-32: som substituto ligado a uma gravação na Biblioteca | — |
| FR-08-02 | parcial | pastas são filtros (campanha, formato, estado, tipo, etiqueta) e pesquisa; verificação com sessão real | filtros e pesquisa em media_library (ADR-0038); W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |
| FR-08-03 | parcial | partilha só da versão atual; verificação com sessão real | pré-visualização 5 min, descarga 2 min, links de partilha 1 h a 7 dias revogáveis e auditados; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |
| FR-08-04 | parcial | substituir por versão nova com sessão real; verificação com conta de cliente (R-15) | versões imutáveis, substituição, histórico, ligação a guião/take/publicação/campanha; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção; produção 06/11: ficha do ativo com versões (v1 atual, SHA-256 conferido), link temporário, ligar a guião e desligar gravado com before/after no audit | 2026-11-06 (agência, produção) |
| FR-08-05 | parcial | sem antivírus (decisão em aberto); limite por ficheiro depende do plano Supabase; retenção automática por fazer | tipos, tamanho e quota por cliente validados no servidor e no bucket; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |
| FR-08-06 | parcial | eliminação automática no fim do prazo e limpeza agendada de órfãos (job com credenciais); custo em euros sem preço por GB | lixo recuperável, órfãos, eliminação definitiva com APAGAR, uso por cliente; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |

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
| FR-10-01 | parcial | verificação com sessão real (R-15) da agência e do cliente (cliente sem Custos) | custo e tokens por execução em /agentes/configuracao; kpi.costs; W4-02b; worker de agentes alojado no Railway desde 2026-11-05; módulo Custos /custos e /c/[ws]/custos (PR #81, ADR-0062, w10_custos 55, costs-format 36); W10-22: decisão do dono 2026-11-09, a equipa do cliente nunca vê custos (_authorize_base recusa costs.* com acesso client_staff; menu, kpi.costs e custo dos agentes escondidos pelo servidor; ADR-0071); w10_decisoes_dono 40/40; w10_custos 55/55; suite SQL 2912/2912; migração 20261109094711_w10_decisoes_dono aplicada em produção a 2026-11-09 | — |
| FR-10-02 | por começar | sem custos de armazenamento, processamento e integrações | nada no código | — |
| FR-10-03 | parcial | sem custos manuais; só moeda do cliente | moeda em /definicoes W1-07 | — |
| FR-10-04 | parcial | sem orçamentos, limite soft, alertas nem autorização para ultrapassar | budget_eur_day limite rígido no worker; W4-02 | — |
| FR-10-05 | parcial | custo por vídeo (sem custos de render) | /c/[ws]/custos por guião e publicação, tendência e CSV (W7, ADR-0037); w7_learn | — |
| FR-10-06 | parcial | sem distinção estimado/confirmado; câmbio fixo na tabela de preços | agent_tool_prices com fonte, data e câmbio BCE; custo desconhecido ≠ 0 | — |

## M11 — Calendário / Produção

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-11-01 | parcial | arrastar não verificado em produção; verificação com conta de cliente (R-15); E2E citado não está versionado no repo | /calendario dia/semana/mês, arrastar com validação; content_reschedule; w3_calendar 39/39; produção 03/11: vistas semana e mês, navegação de mês, guiões e tarefas no dia | 2026-11-03 (sessão real do dono da agência, produção) |
| FR-11-02 | parcial | verificação com sessão real (R-15) da equipa Numeiro | tarefas, gravações, dependências; W3-01, W3-02; calendário com revisões de vídeo e publicações planeadas (W9-03); w9_calendario 14/14; migração aplicada em produção 2026-11-06 | — |
| FR-11-03 | parcial | sem vistas por equipa, plataforma, campanha; sem deteção de conflitos | atrasados a vermelho; limitações W3-02 | — |
| FR-11-04 | parcial | ligar a flag notifications.deadlines e verificar com sessão real (R-15) | template_apply, content_checklist; w3_templates 35/35; W3-03; W10-14 (#83): avisos de prazo 24 h/atraso, guião por aprovar com gravação amanhã, revisão de vídeo atrasada, mudança de prazo; tick pg_cron 15 min; w10_prazos 39/39 | — |
| FR-11-05 | parcial | sem ficheiros, revisões nem publicações ligadas | detalhe do guião com tarefas no calendário (W3-02) | — |

## M12 — Publicação

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-12-01 | por começar | sem módulo de publicação | publishing.* planeadas (W6) | — |
| FR-12-02 | parcial | agendamento por API (PLAT-03/PUB-01); verificação com sessão real (R-15); E2E | registo manual de URL, hora e vídeo aprovado (pub_record_published, W10-03, ADR-0056); w10_publicacao_manual 53/53 | — |
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
| FR-13-05 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | audit_events em convites e papéis; /historico; w1_audit 16/16; invitation.sent e invitation.declined (W1-14); tentativas recusadas no histórico (W10-16, ADR-0066) | — |
| FR-13-06 | parcial | sem grupos/equipas | atribuição de tarefas com _task_valid_assignee; W3-01 | — |

## M14 — Perfil

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-14-01 | parcial | recuperação por email depende do SMTP do Supabase (limitado) até haver domínio (FR-13-01 adiado); verificação com a conta real do Tomás em produção | W1-15 /perfil: nome, fotografia, email verificado, mudar e recuperar palavra-passe, MFA TOTP aplicado no servidor (_mfa_ok); w1_profile_mfa 24/24; e2e/profile.spec.ts 3/3; ADR-0024 | 2026-10-29 (E2E) |
| FR-14-02 | parcial | idioma só PT-PT; email e resumo pessoais guardados mas sem envio; verificação com sessão real | preferências do teleprompter e theme-switcher; fuso e tema no perfil (W1-15); W8: preferências pessoais de notificações e silêncio por cliente no perfil (ADR-0040) | — |
| FR-14-03 | parcial | terminar uma sessão noutro dispositivo do dono e confirmar o JWT recusado (precisa do telemóvel do dono) | terminar sessão em todos os dispositivos e histórico de segurança (W1-15, my_security_log); W10-08: /perfil sessões e dispositivos (my_sessions, session_terminate, sessions_terminate_others, terminar esta sessão); w10_sessoes 44/44; e2e/sessions.spec.ts; ADR-0064; produção 06/11: Sessões e dispositivos mostra a sessão atual com dispositivo e IP reais | 2026-11-06 (agência, produção) |
| FR-14-04 | feito |  | workspace-switcher; my_context; cliente preferido no perfil, usado ao entrar (W1-15); e2e/profile.spec.ts | 2026-10-29 (E2E) |
| FR-14-05 | parcial | política de eliminação | exportar os meus dados em JSON e pedido de eliminação (W7, ADR-0037); w7_learn; e2e/learn.spec.ts | — |

## M15 — Settings

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-15-01 | parcial | sem idioma configurável (só PT-PT) | workspace_update nome, fuso, moeda, logótipo, cor; w1_settings 20/20 | — |
| FR-15-02 | parcial | sem categorias, estados e regras de aprovação configuráveis | só gravar aprovados, templates/checklists; W1-07, W3-03 | — |
| FR-15-03 | parcial | ligar e renovar indisponíveis sem OAuth; testar só recolha de métricas e motor | revogar real com motivo e purga do segredo; testar com histórico; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |
| FR-15-04 | parcial | sem política de aprovação de IA nas definições | modelos e limites em /agentes/configuracao (W4-01) | — |
| FR-15-05 | parcial | envio de email e resumo diário (FR-13-01 adiado); verificação com sessão real | catálogo de eventos, preferências por cliente com obrigatórias, _notify aplica no servidor (ADR-0040); w8_notif 72; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção; W5-05: video_decision e video_comment no catálogo (13 tipos); w8_notif 72/72; W10-14: 5 tipos de prazos no catálogo (grupo Prazos), preferências e obrigatório do cliente aplicam-se; w8_notif 72 | — |
| FR-15-06 | parcial | sem MFA, políticas de sessão, exportação e retenção | /historico (logs) W1-09 | — |
| FR-15-07 | parcial | sem importação/exportação nem política de eliminação | arquivo e recuperação de guiões e clientes | — |
| FR-15-08 | parcial | sem transferir propriedade nem eliminar | workspace_archive com motivo e confirmação; w1_clients 55/55 | — |

## M16 — Pesquisa e notificações

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-16-01 | parcial | verificação com conta real (R-15) dos grupos media, comentários e notificações | search_global com acesso por cliente e entidade (W7, ADR-0035); w7_busca 71/71; e2e/busca.spec.ts; W10-02: media, comentários dos vídeos e notificações próprias na pesquisa (ADR-0054); w10_pesquisa 40/40 | — |
| FR-16-02 | feito | — | paleta Ctrl/Cmd+K com título, #etiqueta e ID, estado vazio (W7, ADR-0035); e2e/busca.spec.ts; produção 03/11: Cmd+K, pesquisa por título no corpo, abrir resultado; 0 erros na consola; produção 06/11 com conta de cliente: pesquisa por título e abrir resultado, 0 erros | 2026-11-06 (agência e cliente, produção) |
| FR-16-03 | parcial | sem preferências de notificação; deep links não confirmados para todos os tipos | /caixa, notifications_read; W3-01; W10-14: tipos de prazos na caixa (alerta/tarefa) com deep link para tarefa, guião ou vídeo | — |
| FR-16-04 | parcial | sem notificações de integrações | menções em task_comment, atribuições, automation_error; W3-01, W4-01 | — |
| FR-16-05 | parcial | verificação com conta real (R-15); E2E da pesquisa com dois clientes para os tipos novos | _viewer_sees/inbox só clientes autorizados; w3_tasks 53/53; pesquisa sem vazamento entre clientes em todos os grupos, incluindo media, comentários e notificações (w7_busca 71/71, w10_pesquisa 40/40; ADR-0035, ADR-0054) | — |

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
| TEAM-10 | parcial | diretor criativo tratado como lado da agência (decisão); verificação com conta real (R-15) | pub_approval_policies (agência, cliente, ambos, sem autoaprovação) (W7, ADR-0036); w7_pub | — |
| TEAM-11 | parcial | sem acesso limitado a projetos/tarefas para convidados | expires_at em workspace_access e permission_grants | — |
| TEAM-12 | parcial | ligar a flag notifications.deadlines e verificar com sessão real (R-15) | _notify só a quem tem acesso; w3_tasks 53/53; W10-14: prazos e mudanças de prazo só a quem tem acesso atual e a capacidade do caso; removido e outro cliente nada; w10_prazos 39/39 | — |
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
| FL-05 | parcial | primeira corrida real em produção (fonte → proposta → revisão) | worker_save_script em revisão, custo por execução; w4_worker 30/30; worker numeiro-engine alojado no Railway e ligado à produção (2026-11-05) | — |
| FL-06 | parcial | pesquisa e ficheiros inexistentes; custos por cliente só nos agentes | dashboard, caixa, desempenho por cliente; w1_dashboard | — |
| FL-07 | parcial | uploads/downloads protegidos: URLs assinados já emitidos valem até ao prazo | member_remove preserva autoria e audit; w1_clients; W10-08: sessões terminadas quando fica sem acesso, auditado (security.sessions_revoked); w10_sessoes | — |
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
| MIG-08 | feito | — | links # removidos, perfil demo removido, erros do teleprompter (W0, W2-02); pesquisa real na paleta Ctrl/Cmd+K (command-palette.tsx, substitui app-search.tsx) com todas as entidades; W7 e W10-02; produção 06/11: Cmd+K pesquisa guiões reais, Enter abre o guião certo no dia certo, ações rápidas criam guião; produção 06/11 com conta de cliente: Cmd+K encontra o guião 22 e Enter abre-o | 2026-11-06 (agência e cliente, produção) |
| MIG-09 | parcial | dual-read e plano de rollback testado por módulo; verificação com conta real (R-15) | feature_flag_defs, feature_flags, my_flags, flag_set, /funcionalidades (W0, ADR-0031); w0_feature_flags 20/20 | — |
| MIG-10 | parcial | RPCs e token legado (studio_whoami, legacy_can, studio_tokens) ainda ativos | tmp_import removida (20261029101111_w1_drop_tmp_import) | — |

## 11. Matriz de testes e aceitação de release

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| QA-01 | feito | — | E2E estrutura 15/15 (CHANGELOG W1-11); e2e/routes.spec.ts no CI (ADR-0022); e2e/menu.spec.ts: cada entrada do menu (cliente: dono e cliente A; agência: dono) abre pelo menu e com refresh, menu esperado = config + my_context + my_flags, entradas em breve sem link (W10-05, PR #86) | 2026-11-06 (E2E com conta real) |
| QA-02 | parcial | storage de media e realtime por cliente sem E2E dedicado | w1_isolation 38/38, w4_engine_isolation 23/23, w1_settings (bucket); e2e/isolation.spec.ts: UI, REST e RPC de A contra B; corre no CI em cada PR (job db, base descartável) | 2026-10-29 (E2E) |
| QA-03 | parcial | membro removido e convite expirado com conta real em produção | convite expirado e membro removido em w1_team, w1_clients; corre no CI em cada PR (job db, base descartável); W10-08: sessão revogada e membro removido dão 42501 com o mesmo JWT (w10_sessoes, e2e/sessions.spec.ts); produção 06/11 com conta de cliente: /c/fly-iaa/guioes mostra Não tens acesso a este cliente, ou ele não existe (sem revelar se existe) | — |
| QA-04 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | w2_content 47/47; E2E de escrita 23/23 (W2) | — |
| QA-05 | feito |  | dedup por url_normalized e URL inválido em w2_sources 41/41; corre no CI em cada PR (job db, base descartável) | — |
| QA-06 | parcial | verificação com conta real (R-15); E2E citado não está versionado no repo | w2_teleprompter 52/52; E2E 28/28 (offline, dois dispositivos, iPad) | — |
| QA-07 | parcial | E2E com várias versões do mesmo vídeo (comentários e desenhos presos a cada versão) | w5_media_review 31/31: decisões presas à versão, versão antiga recusada (W5-04); W10-15: E2E review-stored com comentário por momento, desenho, marca na linha do tempo e sobreposição; cliente B 42501 com e sem desenho | — |
| QA-08 | por começar | sem upload de media | nada no código | — |
| QA-09 | por começar | sem publicação | nada no código | — |
| QA-10 | por começar | sem OAuth | nada no código | — |
| QA-11 | parcial | falha/orçamento com o worker real em produção | w4_worker 30/30, test_worker 19/19 (limite de custo, falha definitiva); corre no CI em cada PR (job db, base descartável); worker numeiro-engine alojado no Railway e ligado à produção (2026-11-05) | — |
| QA-12 | feito | — | w7_busca (termo, etiqueta e IDs exclusivos de B não aparecem para A; p_ws forçado dá 42501); e2e/busca.spec.ts QA-12 | — |
| QA-13 | parcial | teste com sessão ativa real em produção | authorize() por pedido; w1_permissions 35/35; corre no CI em cada PR (job db, base descartável); W10-08: papel reduzido durante a sessão, nova autorização no pedido seguinte (w10_sessoes) | — |
| QA-14 | parcial | axe só no estado inicial das rotas (folhas, diálogos e teleprompter a gravar por analisar); moderate/minor e tema claro por auditar; verificação manual em iPad real | E2E telemóvel/iPad no Início e teleprompter (W1-10, W2-05); e2e/a11y.spec.ts (axe WCAG 2.2 AA, 9 rotas, dono e cliente A, zero serious/critical; teclado no menu, folha de revisão e diálogo) e e2e/viewport.spec.ts (390px e 820px sem scroll horizontal, menu recolhe) (W10-05, PR #86) | 2026-11-06 (E2E com conta real) |
| QA-15 | parcial | RPO e RTO de produção UNVERIFIED (plano, backups, PITR no painel do Supabase); ensaio em staging; cópia fora do Supabase | scripts/backup/drill.sh, job backup no CI, docs/qa/backup-drill-2026-10-30.md (1 006 237 linhas iguais, RTO do ensaio 33,8 s), runbook docs/runbooks/restauro.md (ADR-0042) | — |
| QA-16 | parcial | papéis viewer/reviewer do cliente e código de equipa na mesma matriz; forçar falha de widget e de pedido com conta | quality.yml (guardas); W1-12; ADR-0019; e2e/routes.spec.ts: 19 rotas, dono e cliente, zero erros na consola (CI); W10-05: menu.spec, a11y.spec, viewport.spec (dono e cliente A, telemóvel e iPad, zero erros na consola) | 2026-11-06 (E2E com conta real) |

## 19.1 Inbox universal e triagem

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-01 | parcial | filtros guardados no browser; verificação com conta real (R-15) | my_queue: um item por objeto, decisões além de aprovações (W6, ADR-0034); w6_ops | — |
| FR-17-02 | parcial | sem feedback do cliente nem material entregue | /fontes Por triar e Pedidos do talento (W2-03) | — |

## 19.2 Brief único e conteúdo canónico

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-03 | feito |  | content_briefs com todos os campos, versionado; brief_save; w2_sources 41/41 | — |
| FR-17-04 | parcial | sem variantes, assets e publicações por conta ligadas | guião → hooks → takes; publicacoes legado; ADR-0002 | — |

## 19.3 Handoffs e bloqueios

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-05 | parcial | verificação com sessão real (R-15) da equipa Numeiro | task_rules e domain_events_handoff idempotentes; w3_tasks 53/53; pré-requisitos configuráveis por transição de produção, verificados no servidor (W9-04); w9_prerequisitos 25/25; migração aplicada em produção 2026-11-06 | — |
| FR-17-06 | parcial | sem SLA nem escalonamento; fila de exceções com sem responsável, erro de automação e atrasos (W10-14); faltam erro de upload e publicação falhada | /caixa sem responsável; automation_error (W4-01); W10-14: tarefas e revisões atrasadas como alerta na caixa | — |

## 19.4 Operação de alto volume

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-07 | parcial | seleção só dentro de um dia; verificação com conta real (R-15) | content_bulk com pré-visualização, idempotência e auditoria (W7, ADR-0035); w7_busca | — |
| FR-17-08 | parcial | sem disponibilidade, estimativas e redistribuição | workload, limite de WIP (W3-03) | — |
| FR-17-09 | parcial | sem projetos, campanhas e séries | templates e checklists, template_clone sem responsáveis (W3-03) | — |

## 19.5 Aprendizagem e qualidade

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-10 | parcial | etapa vídeo (sem revisão de media); verificação com conta real (R-15) | rework_reasons, content_transition_reasoned, painel de retrabalho (W7, ADR-0037); w7_learn 101/101; e2e/learn.spec.ts | — |
| FR-17-11 | parcial | dados reais: publicações com índice (depende de PERF-08) | learn_experiments com amostra mínima e critério, índice do centro de desempenho (W7, ADR-0037); w7_learn; produção 06/11: página Experiências e vencedores abre sem erros (estado vazio) | — |
| FR-17-12 | parcial | vencedor sem guião ligado não se repete | learn_repeat_winner cria rascunho ligado (W7, ADR-0037); w7_learn | — |

## 19.6 Continuidade e fiabilidade

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-17-13 | parcial | editar um guião com a conta de cliente (R-15) | autosave com indicador e lock_version (W2-02); rascunho local com recuperação e aviso ao sair (W2-09); e2e/drafts.spec.ts; produção 06/11: autosave com indicador (Alterações por guardar → Guardado), aviso ao sair com alterações por guardar, rascunho recuperado depois de recarregar | 2026-11-06 (agência, produção) |
| FR-17-14 | parcial | verificação com carga real (pacote e exports da sessão de 2026-11-06) | agent_jobs: idempotência, backoff, lease, dead-letter, cancelar; w4_agents 44/44, w4_worker 30/30; media_jobs (lease, heartbeat, backoff, dead, cancelar) e worker de agentes alojados no Railway desde 2026-11-05 | — |
| FR-17-15 | parcial | verificação com sessão real (R-15) do dono da agência; alertas só na app (sem email, FR-13-01 adiado); ver ADR-0058 sobre kinds do worker partilhado | correlation_id em audit/transições; agent_job_attempts; estado do worker na UI; PR W10-01 (painel /saude, ops_health, ops_health_tick pg_cron 5 min, system_health; supabase/tests/w10_saude.sql 38 casos; e2e/saude.spec.ts) | — |
| FR-17-16 | parcial | OAuth real (PLAT-01..03); Drive, R2 e Resend por ligar | centro em /c/[ws]/definicoes/integracoes e /integracoes (ADR-0039); w8_integ 58; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |

## 21. Social accounts e publicação multi-canal

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| FR-21-01 | parcial | OAuth (PLAT-02/03) | social_accounts por conta, credencial só por referência (W7, ADR-0036); w7_pub | — |
| FR-21-02 | parcial | publicador (PUB-01) tem de voltar a verificar ao publicar | só pub_approve leva a aprovada; não há ação de publicar (W7, ADR-0036); w7_pub; registo manual volta a verificar aprovação, versão do guião e vídeo aprovado atual (W10-03); w10_publicacao_manual | — |
| FR-21-03 | parcial | importação só por scraping (não API autorizada) | engine/scrape.py; publicacoes | — |
| FR-21-04 | parcial | publicador por API (PUB-01) chama _pub_link_lineage; verificação com sessão real | correlation_id pub:<id> e lineage_id preparados (W7, ADR-0036); w7_pub; registo manual liga a linhagem pelo correlation_id pub:<id> (W10-03); w10_publicacao_manual | — |

## 25. NFRs, qualidade e critérios de lançamento

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-15 | parcial | verificação com sessão real (agência e cliente) no preview/produção das mudanças de navegação do W10-05 (folha do menu no telemóvel); E2E com conta real já corre no CI (job e2e) | error.tsx app, c/[ws], global-error, widget-boundary; realtime-hub 9/9; quality.yml; W1-12; produção 03/11: 51 rotas (cliente e agência) sem página de erro genérica nem erros na consola, sessão real do dono; W10-05: E2E com conta real no CI abre cada entrada do menu com refresh (agência e cliente), telemóvel e iPad, zero erros na consola | 2026-11-06 (E2E com conta real) |

## 30. Centro de Acessos e Permissões (CAP)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| CAP-01 | parcial | registo sem descrição, dono, versão, ações e flag de disponibilidade | tabela capabilities (key, módulo, risco, âmbitos, estado); feature-registry.md | — |
| CAP-02 | parcial | sem filtros por equipa/projeto, ações em lote, exportação, diff e preview antes de guardar | /permissoes por pessoa e por papel; w1_permissions 35/35; W1-08 | — |
| CAP-03 | parcial | sem papéis personalizados versionados nem modelos por profissão; grants só por pessoa | permission_grants allow/deny com prazo, deny prevalece; w1_permissions 35/35 | — |
| CAP-04 | parcial | capacidades de clipping, media, review, publishing, integrations sem uso | capabilities separadas por ação; feature-registry.md; publishing.publish ativa (W10-03) | — |
| CAP-05 | parcial | authorize() só por workspace, sem recurso | authorize(), access_explain "porquê"; w1_permissions 35/35; simulador Ver como pessoa ou papel (access_simulate, W1-16); w1_access_simulate 11/11; e2e/see-as.spec.ts; produção 03/11: Ver como explica cada capacidade pela origem (papel) | 2026-11-03 (sessão real do dono da agência, produção) |
| CAP-06 | parcial | sem revisões periódicas de acessos | convites com validade, suspender, remover com reatribuição; w1_clients 55/55; W10-08: revogação de sessões (ADR-0064), membro removido e sessão terminada recusados no pedido seguinte; w10_sessoes | — |
| CAP-07 | parcial | sem preview de impacto, segunda aprovação nem alertas de grants excessivos | motivo obrigatório, antes/depois no audit (W1-08, W1-09) | — |
| CAP-08 | parcial | convidados com acesso a uma peça por fazer | /clientes e grants por cliente; admin do cliente só o seu; w1_clients 55/55 | — |
| CAP-09 | feito | — | feature-registry.md (regras); flags separadas das capacidades: my_flags não concede acesso, RPCs verificam capacidades (ADR-0031); w0_feature_flags 20/20 | — |

## 31. Equipa, presença e centro operacional

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| OPS-01 | parcial | sem contadores online, disponíveis, em tarefa, ausentes; sem equipa e projeto | /equipa-agencia com estado, último acesso, tarefas abertas (W1-13) | — |
| OPS-02 | parcial | estado a partir de calendário autorizado; verificação com conta real (R-15) | online, ativo com consentimento, a trabalhar, disponível separados (W6, ADR-0034); w6_ops | — |
| OPS-03 | feito | — | ver, adiar, mostrar já, passar, começar, concluir, idempotentes e auditados (W6, ADR-0034); w6_ops; e2e/ops.spec.ts; produção 06/11: adiar 1 h e mostrar já na Caixa de entrada gravados e auditados (inbox.snooze/inbox.unsnooze); produção 06/11 com conta de cliente: Minha área de trabalho com estado vazio correto; ações adiar/mostrar já verificadas com o dono | 2026-11-06 (agência e cliente, produção) |
| OPS-04 | feito | — | /c/[ws]/quem-trabalha, só do cliente aberto (W6, ADR-0034); w6_ops; produção 06/11: Quem trabalha em quê mostra só a equipa do Numeiro com estados reais; produção 06/11 com conta de cliente: Quem trabalha em quê só com as 4 pessoas do Numeiro, a própria online (tu), sem staff da agência nem outros clientes | 2026-11-06 (agência e cliente, produção) |
| OPS-05 | parcial | sem disponibilidade, férias, capacidade semanal e previsão | workload e WIP (W3-03) | — |
| OPS-06 | parcial | sem SLA, escalonamento e substitutos | templates, checklists, dependências (W3-03) | — |
| OPS-07 | parcial | comparação de versões e acesso externo restrito por recurso | comentários com menções nas tarefas (W3-01); comentários de vídeo com momento e desenho no fotograma (W5-04, W5-12, W10-15) | — |
| OPS-08 | parcial | sem relatórios de throughput, lead/cycle time e retrabalho | /historico (W1-09) | — |
| OPS-09 | por começar | sem automação inteligente | nada no código | — |
| OPS-10 | parcial | Realtime Presence track e Broadcast para colaboração (decisão); verificação com conta real (R-15) | heartbeat no servidor, canal presence:<cliente> só de leitura, isolamento testado (W6, ADR-0034); w6_ops | — |

## 32. Mecanismos adicionais para escalar clipping e conteúdo

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| SCALE-01 | por começar | sem linhagem até publicação e métricas | nada além de guião → takes | — |
| SCALE-02 | por começar | sem ingestão em lote | nada no código | — |
| SCALE-03 | parcial | transcrição pesquisável e múltiplos formatos; ver CLIP-01..07 | W10-12 Clip Miner MVP (ADR-0063) | — |
| SCALE-04 | por começar | sem centro de publicação | nada no código | — |
| SCALE-05 | parcial | sem guidelines de marca, áudio, direitos; verificação factual só marca (VAR-04), não confirma na fonte | checklist por cliente (W3-03); rubrica do Crítico no motor; verificador VAR-04 (W10-06) | — |
| SCALE-06 | parcial | recomendações só de leitura; limiares por calibrar | learn_recommendations com evidência e limitações (W7, ADR-0037); w7_learn | — |
| SCALE-07 | parcial | papéis não copiados | workspace_create com estrutura de outro cliente, template_clone (W1-06, W3-03) | — |
| SCALE-08 | parcial | revisão de vídeos pelo cliente; relatórios para enviar; notificar o cliente do que espera por ele; escolher outro mês nas entregas; verificação com sessão real | portal /c/[ws]/portal: aprovações pelas RPCs existentes, entregas sem valores, desempenho, pedidos (ADR-0041); w8_portal 46; W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção | — |

## 37. Regras transversais novas

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-16 | parcial | correspondência por impressão digital com os nossos renders | origem externo nas importadas, perf_origin_set com motivo e auditoria (W6, ADR-0033); w6_perf | — |
| R-17 | parcial | verificação com sessão real (R-15); lista do Numeiro por preencher | persona_lists versionada e imutável, persona_list_get/version/save com consentimento de terceiros, persona.manage, worker_claim.persona, aba Agentes → Frases-persona (W5-14, ADR-0053); w5_persona_phrases 21/21; persona-rules 11/11; numeiro-engine #14 test_persona 4/4; E2E persona-phrases 4/4 (admin grava v1/v2, outra pessoa sem consentimento bloqueada na UI e no servidor 22023, histórico, manager só leitura 42501, cliente B 42501; W5-15); aba verificada em produção com a conta do Tomás (2026-11-06); verificador de títulos fora da lista (VAR-04, W10-06) | — |
| R-18 | parcial | publicador por API (PUB-01); formato de reels.id no TikTok/YouTube por confirmar | linhagem gravada imutável e idempotente; importadas inferidas e marcadas (W6, ADR-0033); w6_perf; registo manual grava a linhagem no momento (W10-03, ADR-0056) | — |
| R-19 | adiado | decisão do Tomás 29/10: métricas passam a vir da API oficial no futuro; por agora continua o Apify (engine/scrape.py). Fecha com PERF-08/PLAT-02 | engine/scrape.py ApifyClient; ADR-0005 | — |

## 38. Vista de negócio da agência (BIZ)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| BIZ-01 | parcial | filtro de origem (R-16) no cálculo; prazo por vídeo é pressuposto; sem contrato registado no Numeiro | biz_overview, atingimento por cliente e total (W6, ADR-0032); w6_biz 62/62; e2e/biz.spec.ts; produção 03/11: vista de negócio com estados vazios explicados | 2026-11-03 (sessão real do dono da agência, produção) |
| BIZ-02 | parcial | 3 regras sem dados (saúde a cair, renovação com saúde, posts perto de zero) | faixa com até 5 cartões por gravidade e ação direta, também no Painel (W6, ADR-0032); w6_biz; produção 03/11: alerta real de 23 guiões à espera há mais de 48 h | 2026-11-03 (sessão real do dono da agência, produção) |
| BIZ-03 | parcial | AGI distinto do MRR (decisão); índice com fotografias por idade (PERF-03); sem contratos nem câmbio registados | KPIs operacionais e financeiros e tabela por cliente (W6, ADR-0032); w6_biz; produção 03/11: KPIs e tabela por cliente, aviso de câmbio em falta | 2026-11-03 (sessão real do dono da agência, produção) |
| BIZ-04 | feito | — | resposta construída por pessoa; sem biz.finance não sai nenhum campo financeiro (W6, ADR-0032); w6_biz; e2e/biz.spec.ts; produção 06/11: vista de negócio do dono com 3 clientes e alerta real (23 guiões à espera há mais de 48 h); produção 06/11 com conta de cliente: /negocio recusado (A vista de negócio é da equipa da agência) | 2026-11-06 (agência e cliente, produção) |
| BIZ-05 | parcial | registar o contrato real do Numeiro e o câmbio (dono) e ver MRR/margem | client_contracts versionados, EUR/AED, câmbio com data (W6, ADR-0032); w6_biz | — |
| BIZ-06 | parcial | custo de IA só em EUR; verificação com conta real (R-15) | agency_costs com repartição e anulação, margem, custo por vídeo e por 1.000 views (W6, ADR-0032); w6_biz | — |
| BIZ-07 | feito |  | access_simulate por papel, só leitura e auditado (W1-16); produção 03/11: Ver como numeiro@gmail.com, só leitura, access.simulated no audit; W1-17: navegar como papel/pessoa em toda a app, servidor só leitura (_authorize estreita), faixa fixa, auditado (ADR-0045); w1_preview 25/25; produção 04/11: navegar como Leitor, faixa, menu reduzido, sair devolve tudo, 0 erros | 2026-11-04 (sessão real do dono da agência, produção) |
| BIZ-08 | parcial | verificação com sessão real (convite com cargo) | invite_member_with_title e aplicação ao aceitar (W7, ADR-0037); w7_learn; e2e/learn.spec.ts; mapeamento validado pelo Tomás a 2026-11-04 | — |
| BIZ-09 | por começar | sem score de saúde | nada no código | — |

## 39. Ingestão, armazenamento e linha de edição (ING, EDL)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| ING-01 | parcial | carregar as gravações da sessão de 2026-11-06; bruto antigo do Drive continua como link | Supabase Storage (bucket privado media) atrás de src/lib/storage (ADR-0038); W8 (ramo w8-vaga3): SQL 1648/1648, E2E 143/143 no stack local; ainda não aplicado em produção; ; CHG-006: finais para revisão na Drive da agência, versão por link na biblioteca (W5-04); Cloudflare R2 implementado (sigv4, envio por partes, proxies pelo worker; W5-07, ADR-0047); media.r2 ligado no Numeiro; webm de teste verificado pelo worker com versão leve em produção (2026-11-05) | — |
| ING-02 | por começar | sem ingestão da câmara | media.ingest planeada | — |
| ING-03 | parcial | verificação com a sessão real (gravação com marcas do teleprompter); ligar edit.package_marks (ADR-0065) | recording_marks, recording_marks_add, recording_timeline (W5-01, ADR-0026); w5_recording_marks 17/17; e2e/recording-marks.spec.ts 2/2; ficheiro longo por câmara no R2 (W5-07) com transcrição com tempos por palavra e sincronização pelo áudio no pacote (W5-09); W10-17: marcas do teleprompter ligadas às janelas do pacote (input.marks pela flag edit.package_marks, relógio acertado pela transcrição, passagens/retakes e hooks etiquetados, fallback com motivo em result.windows; ADR-0065); w10_marcas_janelas 23/23; motor test_marks 16/16; package-windows 15/15; migração 20261106131632_w10_marcas_janelas aplicada em produção a 2026-11-06; W10-20: aceita um ficheiro por guião e por câmara ligado na Biblioteca (recording_clips, ADR-0070); numeiro-engine#22 em produção (2026-11-06) | — |
| ING-04 | por começar | sem upload pelo telemóvel | nada no código | — |
| EDL-01 | parcial | verificação com a sessão real de 2026-11-06; deteção de cara para o enquadramento; publicar o worker das janelas pelas marcas e ligar edit.package_marks (W10-17, ADR-0065) | preset de edição versionado por cliente com o defeito do PRD (edit_presets, edit_preset_save; W5-02, ADR-0027); job package no worker (transcrição, sincronização pelo som, janelas por guião, takes pela IA, documento v1 por hook), página Edição automática (W5-09, ADR-0048); w5_edit_package 19/19; janelas 20/23 dentro de 5 s na sessão de teste; W5-16: pacote recusa guiões eliminados e o worker só grava guiões do pedido; IDs de outro cliente P0002/42501 (w5_auditoria_isolamento); W10-07: o pacote usa o estilo guardado pedido (aspeto, música, layout) e guarda 2-3 alternativas por secção para o modo guiado (numeiro-engine #16, ADR-0055); pacote que falha: mensagem em linguagem simples, detalhe técnico e Tentar de novo que repõe câmaras e guiões (W10-21, tests/package-errors 6/6; teste de ponta a ponta em produção a 2026-11-06: pacote, 3 exports e revisão); W10-17: janelas por guião pelas marcas do teleprompter afinadas pela transcrição, origem por guião na Edição automática (ADR-0065); W10-20: pacote de um guião de cada vez a partir das gravações curtas desse guião (STU-03, ADR-0070), automático por definição do cliente; W10-27: câmara com o som da lapela escolhida em cada pacote (input.audio, ADR-0074); w10_som_da_lapela; migração 20261109171200_w10_som_da_lapela aplicada em produção e numeiro-engine#29 em produção (09/11) | — |
| EDL-02 | parcial | verificação com a sessão real de 2026-11-06 (pacote → exportar todos → rever); versão leve a 540p em vez de 720p (ADR-0052) | edit_package_export, revisão com ficheiros guardados e player da app, QC por vídeo, Aprovar e seguinte (W5-12, ADR-0052); w5_review_stored 34/34; review-queue 12/12; E2E review-stored 5/5 (player da app com clip, Agora, saltar ao momento, Aprovar e seguinte; sem R2 erro claro e Tentar de novo; revisor sem exportar 42501; Exportar todos idempotente; cliente B 403/42501; W5-15); W10-20: exportar todos de um guião e exportar todos automático quando o pacote do guião acaba (ADR-0070) | — |
| EDL-03 | parcial | distinct_source só por opção (qc_rules.compare_source); calibrar limites no piloto (EDL-06) | numeiro-engine #7: engine/qc.py, run.py qc, tests/test_qc.py 11/11 no CI do motor (ADR-0028); QC sobre cada export no worker, relatório em media_info.qc e na revisão (W5-12); test_qc_summary_on_export; QC do documento antes de render e pHash com as irmãs no worker (numeiro-engine #17, QC 2026-11-06.1); _edit_resolve_siblings (W10-09, w10_qc_irmas 6/6) | — |
| EDL-04 | por começar | sem biblioteca de vídeos de atenção | nada no código | — |
| EDL-05 | por começar | sem pós-produção multi-agente | nada no código nem no motor | — |
| EDL-06 | por começar | piloto não iniciado | nada no código | — |

## 39.1 Editor de vídeo (EDL-07..EDL-13, CHG-007)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| EDL-07 | parcial | ligar edit.ai_visuals, carregar e etiquetar ativos ia-imagem/ia-atencao/ia-musica (a Biblioteca do Numeiro ainda não tem imagens nem áudio); verificação com a sessão real | edit_documents/edit_versions imutáveis, edit_doc_get/save com conflito, 68 vídeos importados do plano (W5-06, ADR-0046); w5_edit_doc 21/21; edit-doc 25/25; produção 04/11: 68 documentos com v1 importada do plano (13 866 palavras); produção 04/11: abrir, nota no cursor, gravar v2, v1 intacta, restaurar v1 como v3, 0 erros; W10-18: edit_package_request manda fill (biblioteca ia-*, frases em vigor, receitas do preset) com a flag edit.ai_visuals; motor package_visuals escreve imagem, frase-persona, vídeo de atenção e música com o porquê em doc.ai.visuals; painel Escolhas da IA no editor; w10_v1_visuais_musica 23/23; edit-doc 81/81; test_package_visuals 7/7; migração 20261106131703_w10_v1_visuais_musica aplicada em produção a 2026-11-06; numeiro-engine#23 em produção (2026-11-06); W10-22: decisão do dono 2026-11-09, etiquetar ia-* é a declaração de direitos do cliente; ficha do ativo pede confirmação, servidor recusa sem ela (22023) e regista media.ai_rights_declared (ADR-0071); w10_decisoes_dono 40/40; media-format 21/21 | 2026-11-04 (sessão real do dono da agência, produção) |
| EDL-08 | parcial | verificação do Tomás com sessão real a ouvir um vídeo inteiro com o som contínuo (W10-29) | edit_preview_sources, media_proxy_access, /api/media/versions/:id/proxy, PreviewVideo (um vídeo por câmara no tempo da sessão), versão leve pelo worker (W5-07, ADR-0047); w5_media_r2 39/39; edit-preview 2/2; palco ligado na página do editor e no modo guiado (PR #62); worker no Railway a gerar versões leves (verificado em produção 2026-11-05); W10-17: doc.ai.window e source.window do pacote vêm das passagens do teleprompter quando batem certo (ADR-0065); W10-28: versão leve do C7870 refeita, palco com imagem e som da câmara da frente (produção, 10/11); W10-29: o som dá o tempo, dois leitores revezam-se nos cortes, sem paragens a carregar em produção (ADR-0077); W10-30: legendas do palco pelo mesmo plano da exportação (caption-plan, igual ao motor em 200 documentos; ADR-0078); W10-32: som substituto da gravação no palco e na exportação (media_audio_replace; w10_som_substituto 19/19; ADR-0080); W10-37: palco com a imagem verdadeira dos visuais, visuais por baixo das letras e hook como o export | 2026-11-10 |
| EDL-09 | feito | — | /c/[ws]/editor: faixas, arrastar pontas e mover, dividir, tirar, reordenar, palavras e hook, visuais e música da biblioteca, volume por corte, notas por momento, desfazer/refazer, atalhos (W5-06); edit-doc 37/37; área principal cabe no ecrã com a barra lateral (min-w-0); visuais e música desenhados no export (numeiro-engine #15, W5-17); produção 06/11: editor do g28 hook 1: dividir no cursor (18→19 cortes), tirar, desfazer e refazer, Descartar sem gravar versão; produção 06/11 com conta de cliente (contributor): editor abre em modo guiado com os 18 cortes, 0 erros; W10-35: câmaras à mão (ângulo, zoom, posição, dividir, aplicar a toda a câmara, tecla C; cam-edit 3/3) e guias do palco (ADR-0082); W10-36: enquadramento de uma câmara em todos os vídeos com a mesma gravação; W10-38: imagens do computador por arrastar (palco e linha do tempo) ou carregar no seletor; W10-39: imagens livres (mover e redimensionar no palco, mover no tempo do vídeo final, tamanho no painel) | 2026-11-06 (agência e cliente, produção) |
| EDL-10 | parcial | imagem no palco (EDL-08); verificação com sessão real de cliente (R-15) a usar uma alternativa da IA | modo guiado /c/[ws]/editor (só edit.guided ou ?modo=guiado): passos Estilo, Corte, Hook, Visual e música, Legendas, Exportar; edit_doc_save valida a diferença no servidor (_edit_guided_problem, W5-10, ADR-0049); w5_edit_guided 38/38 (19 recusas entre modos, música de outro cliente, admin de B); edit-doc 61/61; W10-07: alternativas da IA por secção no passo Corte (edit_alternative_apply, versão montada no servidor a partir de doc.ai.alternatives) e textos do hook da IA (ADR-0055); w10_pacote_estilo_alternativas 37/37; edit-doc 70/70 | — |
| EDL-11 | parcial | visuais guardados no Supabase Storage ou por link ficam de fora (decisão ADR-0068: a IA só usa R2); verificação com sessão real | edit_export_request/list/cancel, media_jobs export, engine/render_doc.py (cortes, câmaras, janelas, zoom, legendas S14/S15, hook, volume, música, -14 LUFS), ExportPanel (W5-07); render local do guião 3: 60,4 s em ~2,5 min; worker numeiro-engine no Railway ligado (abedaf5304ce-1-media, 2026-11-05); exports entram na revisão com QC (W5-12); aspeto e visuais no render (numeiro-engine #15), visuais resolvidos no export (W5-17, w5_export_visuais 8/8); W10-18: posição por visual (overlays[].box) no palco e no render, B-roll com caixa só na caixa (numeiro-engine edl07-visuais-musica, test_render_doc); W10-22: direitos dos visuais da IA declarados ao etiquetar ia-* na Biblioteca, com registo media.ai_rights_declared (ADR-0071) | — |
| EDL-12 | por começar |  |  | — |
| EDL-13 | parcial | verificação com sessão real (pacote com estilo guardado → v1 com o aspeto e a música) | Guardar como estilo no editor (aspeto, música, layout da versão gravada) no catálogo do VAR-02, versionado (edit_style_from_doc, coluna look); aplicar a outro vídeo cria versão nova, também no modo guiado (edit_style_apply) (W5-11, ADR-0050); w5_edit_saved_styles 24/24; edit-doc 63/63; o render do export desenha o aspeto guardado (numeiro-engine #15, test_render_doc); W10-07: edit_package_request manda look e style_version ao worker (numeiro-engine #16), música só se ativa no cliente, versão do estilo na chave de idempotência (ADR-0055); w10_pacote_estilo_alternativas 37/37; W10-30: estilo das legendas (S15/S14) escolhido no editor; W10-31: barra vermelha contínua do S15 no render e no palco (ADR-0079); W10-37: estilo S17 (caixa branca com imagens) no render, no palco e nos estilos do pacote (ADR-0083) | — |
| EDL-14 | parcial | verificação do Tomás com sessão real: editar o corpo num hook e ver nos outros | W10-33: applyBody + gravação nas variantes (body-share 5/5), separadores e estado do corpo no editor (ADR-0081); W10-35: corpo sempre aplicado (sem caixa), também no modo guiado, e Igualar corpos | — |
| EDL-15 | parcial | verificação do Tomás com sessão real (imagens, exportar a partir do quadro) | W10-33: edit_board (w10_videos_por_guiao 12/12; 16 guiões do Numeiro em produção), Vídeos por guião na Edição automática, separadores no editor; W10-34: o que se diz em cada hook e imagens no quadro (edit_board hook_spoken); W10-40: cursor segue o visual escolhido, campo Duração editável com vírgula, mensagens de carregar no fundo do ecrã (testado em produção 2026-11-10) | — |

## 40. Centro de desempenho (PERF)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PERF-01 | parcial | criador/marca é só um campo por conta; verificação com conta real (R-15) | perf_accounts (camada A-D, criador, estado) (W6, ADR-0033); w6_perf 63/63 | — |
| PERF-02 | parcial | publicador por API (PUB-01); frase-persona não preenchida no registo manual | publication_lineage com as etiquetas de §40 (W6, ADR-0033); w6_perf; registo manual chama _perf_record_lineage com hook, estilo, ativo e duração (W10-03) | — |
| PERF-03 | parcial | histórico só desde a primeira captura; 1 h quase nunca existe com scraping diário | perf_readings e perf-tick de hora a hora, fotografia ±25% (W6, ADR-0033); w6_perf | — |
| PERF-04 | parcial | engagedViews do YouTube (API oficial) | _perf_index pela mediana da mesma conta na mesma idade, base ≥5 (W6, ADR-0033); w6_perf | — |
| PERF-05 | parcial | alcance, retenção, skip rate, seguidores, For You (API oficial); custo por vídeo (BIZ-06) | _perf_families com as métricas da recolha e indisponíveis marcadas (W6, ADR-0033); w6_perf | — |
| PERF-06 | parcial | persona e estilo só com linhagem gravada; canibalização básica | perf_breakdown com 12 dimensões (W6, ADR-0033); w6_perf | — |
| PERF-07 | parcial | o motor (Aprendiz/Estratega) ainda não lê as alavancas | perf_levers com amostra mínima 15 e relatório semanal (W6, ADR-0033); w6_perf | — |
| PERF-08 | por começar | sem ligar contas por OAuth | nada no código | — |
| PERF-09 | parcial | só uma leitura por publicação; ligação ao conteúdo por inferência | publicacoes.shares, guiao_id | — |

## 41. Variantes, estilos e republicação (VAR)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| VAR-01 | parcial | render das variantes | pub_variants com os 5 elementos e regra das irmãs (W7, ADR-0036); w7_pub; pub-rules 14/14 | — |
| VAR-02 | parcial | layouts de S01 a S12 (equipa criativa); render real dos estilos no motor (hoje só no protótipo local); verificação com sessão real | edit_styles, edit_style_versions, edit_style_save/set_status (W5-02, ADR-0027); w5_edit_styles 34/34; e2e/edit-styles.spec.ts 3/3; pré-visualização fiel ao spec: letra, tamanho, caixas e destaque (W8-08, StylePreview); W10-41: editor, Edição automática e pacote por guião leem o catálogo (ativos que o motor desenha), selo No editor/Sem render ainda; style-options 3/3 | — |
| VAR-03 | por começar | sem motor frase-imagem | nada no código nem no motor | — |
| VAR-04 | parcial | verificação com sessão real (R-15) depois do deploy do motor; afirmações do corpo não classificadas; idioma por conta de clips | W10-06 (ADR-0057): script_verifications, worker_save_verification, content_verifications, flag scripts.verifier, marcas por hook no cartão do guião; w10_verificador 27/27; verifier-format 12/12; numeiro-engine #18 test_verifier 19/19 | — |
| VAR-05 | por começar | sem republicação | publishing.republish.approve planeada | — |
| VAR-06 | por começar | sem fontes longas no pacote | nada no código | — |
| VAR-07 | por começar | sem distribuição por camadas | nada no código | — |

## 42. Publicação automática e calendário (PUB)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PUB-01 | por começar | sem publicador | nada no código | — |
| PUB-02 | parcial | leitura dos limites em tempo real chega com o publicador | pub_platform_limits com data de verificação, recusa acima do limite (W7, ADR-0036); w7_pub | — |
| PUB-03 | adiado | decisão do Tomás 29/10: sem publicação manual, espera pela API oficial (PLAT-03) | — | — |
| PUB-04 | parcial | quotas de republicação só como aviso; verificação com conta real (R-15) | calendário de publicações com conflitos e arrastar (W7, ADR-0036); w7_pub 91/91; e2e/pub.spec.ts; estado publicada no calendário de publicações (W10-03) | — |
| PUB-05 | por começar | sem republicação agendada | nada no código | — |
| PUB-06 | parcial | notificações a quem aprova; verificação com conta real (R-15) | publishing.approve e republish.approve; aprovação presa à revisão e invalidada ao mudar (W7, ADR-0036); w7_pub; e2e/pub.spec.ts | — |

## 43. Aprovações das plataformas (PLAT)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| PLAT-01 | bloqueado | precisa do Tomás: domínio próprio, Business Verification Meta, registo das apps; páginas públicas adiadas pelo Tomás a 2026-11-04 até haver domínio | PRD §44 itens em aberto; produção em clipstudio-jchs.vercel.app | — |
| PLAT-02 | bloqueado | depende de PLAT-01 e de ligar contas + métricas em produção (PERF-08) | nada submetido | — |
| PLAT-03 | bloqueado | depende de PLAT-01 e do publicador (PUB-01) | nada submetido | — |
| PLAT-04 | por começar | sem apps aprovadas a manter | nada submetido | — |

## 45. Referências por link: dissecar, adaptar e copiar o estil

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| R-20 | por começar |  |  | — |
| REF-01 | parcial | campo só no espaço do cliente (agência sem biblioteca, REF-07); links curtos do TikTok não resolvidos; verificação com sessão real (R-15) | reference_paste + ref_key (W10-04, ADR-0059); w10_referencias_link 65/65; reference-link 13/13 | — |
| REF-02 | parcial | deploy do worker (numeiro-engine#19) e APIFY_TOKEN no worker (não verificado); verificação com sessão real (R-15) | reference_analyses versionada e imutável, worker reference_analysis, dissecção na UI (W10-04, ADR-0059); w10_referencias_link 65/65; motor test_reference 15/15 | — |
| REF-03 | parcial | deploy do worker; calibrar limites de semelhança (pressuposto); verificador factual (VAR-04); verificação com sessão real | reference_adapt + worker reference_scripts, 3 hooks, semelhança no motor e no servidor (W10-04); w10_referencias_link 65/65; motor test_reference 15/15 | — |
| REF-04 | parcial | topo da fila do teleprompter, modo rápido pelo telemóvel (ING-04), estilo extraído (REF-05); meta de 10 min por medir | guiões origem via_rapida em revisão, badge, reference_script_outputs (W10-04) | — |
| REF-05 | por começar |  |  | — |
| REF-06 | por começar |  |  | — |
| REF-07 | parcial | verificação com sessão real da agência e de um cliente | W10-42: agency_styles/agency_style_versions, agency_style_library/save/set_status/history, /estilos (ADR-0084); w10_biblioteca_estilos 29/29 | — |
| REF-08 | parcial | render por parâmetros para chaves diferentes das do motor (REF-05); verificação com sessão real | W10-42: agency_style_import (versão fixa, origem, Atualizar, recusa chave do cliente PT409), origem no catálogo do cliente; w10_biblioteca_estilos 29/29 | — |
| REF-09 | por começar |  |  | — |

## 46.1 Olhar na câmara e teleprompter (GAZE)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| GAZE-01 | parcial | verificação com sessão real no estúdio (iPad a ~2,5 m, R-15) | src/lib/gaze.ts (2·d·tan 3°, px/cm pela diagonal e dpr); ângulo medido no topo com aviso acima de ±4,5°; tests/gaze.test.mts 34/34; w10_teleprompter_olhar 15/15; e2e/teleprompter-gaze.spec.ts; ADR-0060; W10-11 | — |
| GAZE-02 | parcial | verificação com sessão real no estúdio (R-15) | linha de foco focus_pct (bloco atual, retoma e salto pela mesma linha); modo frase phraseLines 2-4 palavras por bloco; tests/gaze.test.mts 34/34; e2e/teleprompter-gaze.spec.ts; ADR-0060; W10-11 | — |
| GAZE-03 | por começar |  |  | — |
| GAZE-04 | por começar |  |  | — |
| GAZE-05 | por começar |  |  | — |
| GAZE-06 | por começar |  |  | — |

## 46.2 Aprendizagem contínua com edições e rejeições (LRN)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| LRN-01 | parcial | ligar learn.edits; E2E só no CI; verificação com sessão real (R-15) | lrn_edit_signals, content_decide_learned, content_edit_reason, chips no cartão (flag learn.edits; W10-19, ADR-0069); w10_aprendizagem 74/74; e2e/aprendizagem-licoes.spec.ts; migração 20261106132216_w10_aprendizagem aplicada em produção a 2026-11-06; W10-22: decisão do dono 2026-11-09, o limiar de 30% fica (ADR-0071) | — |
| LRN-02 | parcial | ligar learn.lessons; verificação com sessão real | job lesson_editor, worker_lesson_pairs/worker_lesson_save com evidência refeita na base, lrn_lessons_tick (W10-19, ADR-0069); w10_aprendizagem 74/74; numeiro-engine#27 (job lesson_editor, test_lesson_editor 9/9, corrida mock contra Postgres local); numeiro-engine#27 em produção (worker com lesson_editor, 2026-11-06) | — |
| LRN-03 | parcial | ligar learn.lessons; verificação com sessão real (R-15) | /c/[ws]/aprendizagem/licoes (flag learn.lessons), learn.lessons.approve, lrn_lesson_versions imutáveis com voltar atrás (W10-19, ADR-0069); w10_aprendizagem 74/74; e2e/aprendizagem-licoes.spec.ts; W10-22: decisão do dono 2026-11-09, aprovam o dono, o admin e o gestor do cliente (como implementado; ADR-0071) | — |
| LRN-04 | parcial | lições da agência aprendidas dos resultados de todos os clientes (hoje só por Propor à agência); verificação com sessão real (R-15) | níveis cliente/agência em lrn_lessons e lrn_lesson_versions, learn.lessons.agency (org), worker_lessons com precedência do cliente (W10-19, ADR-0069); w10_aprendizagem; W10-22: decisão do dono 2026-11-09, a equipa do cliente vê as regras da agência em vigor só leitura (secção Regras da agência (só leitura), lrn_lessons_list agency.readonly; ADR-0071); w10_decisoes_dono 40/40; w10_aprendizagem 74/74 | — |
| LRN-05 | por começar |  |  | — |
| LRN-06 | por começar |  |  | — |
| LRN-07 | por começar |  |  | — |

## 46.3 Cortes de vídeos longos (CLIP)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| CLIP-01 | parcial | verificação com sessão real (R-15) e um master real no R2; Drive do cliente como fonte não ligado | W10-12 (ADR-0063): clips_request só aceita versões R2 prontas do cliente; w10_clip_miner 38/38 | — |
| CLIP-02 | parcial | separação de oradores: fornecedor por escolher depois do teste em PT-PT (UNVERIFIED); hoje só tempos por palavra (faster-whisper) | numeiro-engine clips.py (speakers_for), test_clips | — |
| CLIP-03 | parcial | rubrica e máquinas testadas com episódios reais (piloto CLIP-11); crítica num segundo passo | clips.py + prompts/clip_miner.md (clip-miner-1): IDs de frase, tese, máquina, polémica, riscos, pontuação e justificação; test_clips | — |
| CLIP-04 | parcial | regra final para afirmações sobre terceiros (§46.5, decisão do Tomás); pessoas identificadas só assinaladas | portão da dignidade no motor e no servidor (_clip_meta_problem); test_clips, w10_clip_miner | — |
| CLIP-05 | parcial | medir com vídeos reais (contexto perdido, ≤ 30 min por hora de fonte) | diversidade, 25-60 s, cortes em fins de frase e silêncios em código; test_clips | — |
| CLIP-06 | parcial | verificação com sessão real com um master real (vista Original vs. cortado no editor) | documento v1: gancho no 0:00 com ≤ 3 trechos de frases inteiras, título ≤ 8 palavras, 3 hooks, contexto, CTA; test_clips; vista Original vs. cortado no editor e no modo guiado (W10-24, ADR-0073): clip-order.ts + tests/clip-order.test.mts 25/25; e2e/clip-lado-a-lado.spec.ts escrito, não corrido (stack local em baixo) | — |
| CLIP-07 | parcial | reframe 9:16 com orador ativo (hoje corte ao centro), fontes multi-câmara, verificação com sessão real | cortes no editor, export (EDL-11, QC) e revisão em lote (media_review_list); w10_clip_miner | — |
| CLIP-08 | por começar |  |  | — |
| CLIP-09 | por começar |  |  | — |
| CLIP-10 | por começar |  |  | — |
| CLIP-11 | por começar |  |  | — |

## 46.4 Estúdio ligado à app (STU)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| STU-01 | por começar |  |  | — |
| STU-02 | por começar |  | W10-20 (ADR-0070): contrato para o agente: enviar cada corte pelo upload da Biblioteca e ligar com media_clip_link(ws, ativo, guião, câmara, sessão, 'agente') quando houver identidade própria (studio.capture); o automático e o worker já tratam o resto | — |
| STU-03 | parcial | verificar com sessão real (cortes curtos por guião → pacote em minutos → notificação agrupada → exportar → rever); disparo pelo agente de estúdio (STU-02) | W10-20 (ADR-0070): recording_clips + media_clip_link (envio da Biblioteca, ficha do ficheiro, Edição automática), edit_package_script_request (job package com mode=script, idempotente por guião, versões das gravações e estilo), automático quando as duas gravações ficam prontas e exportar todos automático (em nome de quem ligou, verificado a cada disparo), secção Pacote por guião (flag edit.package_script); numeiro-engine stu03-pacote-por-guiao (transcreve só o corte, janela = ficheiro todo; test_package 14/14); w10_pacote_por_guiao 43/43; e2e/pacote-por-guiao.spec.ts (não corrido localmente: sem stack); migração 20261106131955_w10_pacote_por_guiao aplicada em produção a 2026-11-06; numeiro-engine#28 em produção (2026-11-06); W10-23 (ADR-0072): notificação agrupada por lote de gravação (sessão ou dia local) para pacotes por guião, N de M, por ler a cada mudança, final com falhas nomeadas, idempotente e com advisory lock (decisão do responsável de produto 2026-11-09); w10_notif_agrupada 22/22; suite SQL 2892/2892; edit.package_script ligada no Numeiro; migração 20261109094755_w10_notif_agrupada aplicada em produção a 2026-11-09 | — |
| STU-04 | por começar |  |  | — |
| STU-05 | por começar |  |  | — |

## 47. Radar de reacts (REACT, CHG-009)

| ID | Estado | O que falta | Evidência | Verificado |
|---|---|---|---|---|
| REACT-01 | parcial | agente diário de descoberta a correr e verificado com sessão real; aprendizagem da descoberta com aceitar/rejeitar | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09; Tarefa agendada 'Radar de reacts diário' criada (06:47 Dubai); primeira descoberta com 4 contas propostas em produção | — |
| REACT-02 | parcial | recolha diária pelo agente (tarefa agendada) e classificação do tipo de vídeo por frames; verificação com sessão real | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09 | — |
| REACT-03 | parcial | avaliação feita pelo agente em cada corrida; calibração | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09 | — |
| REACT-04 | parcial | verificação com sessão de cliente (equipa do Numeiro) depois de ligar a flag para todos; agente diário a correr | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09; Produção 09/11 com sessão real da agência (Tomás): fila com 5 takes, vídeo a reproduzir pela rota, separador Fontes com 4 propostas e 1 vigiada, sem erros na consola | 2026-11-09 |
| REACT-05 | parcial | verificação com sessão real; excerto do original no editor | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09 | — |
| REACT-06 | parcial | lições LRN a partir das decisões e relatório de calibração | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09 (worker_react_context devolve as decisões ao agente) | — |
| REACT-07 | parcial | agente diário a renovar links | W10-25 (ADR-0074): react_sources/react_candidates fechadas à API, RPCs com ws_can + flag reacts.radar, worker_react_* só engine_worker; tab /c/[ws]/reacts e rota /api/reacts/:id/video; w10_reacts 33/33, reacts-format 26/26; migração 20261109095944_w10_reacts aplicada em produção a 2026-11-09 (worker_react_context lista links a renovar) | — |
| REACT-08 | parcial | verificação em sessão real de cliente (flag reacts.radar só equipa da agência); recolha pela API oficial quando houver OAuth (R-19) | W10-26 (ADR-0075): comment_ideas fechada à API, comments_list/comment_decide/comment_record com reacts.read/reacts.decide + flag reacts.radar, worker_comment_* só engine_worker com a config ativa do cliente; separador Comentários em /c/[ws]/reacts; w10_comentarios 26/26, comments-format 5/5; migração 20261109132856_w10_comentarios aplicada em produção; 1.ª análise 2026-11-09: 624 comentários de 15 reels, 22 ideias; tarefa agendada de 3 em 3 dias; verificado em produção com sessão da agência a 2026-11-09: separador abre com 22 ideias, filtro por tipo funciona, 0 erros na consola; data do comentário escondida quando não existe | 2026-11-09 |
