# Changelog

## 2026-10-30 (vaga 2: pesquisa, publicações planeadas e aprendizagem)

Tudo atrás de funcionalidades em teste (só o dono da agência até as ligar).

- **W7 Pesquisa global** (FR-16-01, FR-16-02, FR-01-05, FR-17-07; ADR-0035). Ctrl/Cmd+K pesquisa guiões, fontes, referências, tarefas, campanhas, pessoas e estilos só nos clientes e entidades que a pessoa pode ver, com sugestões, #etiquetas e IDs; ações rápidas para criar fonte, guião, campanha e tarefa. Operações em lote nos guiões (responsável, campanha, etiquetas, aprovar, reagendar, exportar CSV) com pré-visualização, confirmação, idempotência e auditoria.
- **W7 Publicações planeadas** (PUB-02, PUB-04, PUB-06, TEAM-10, FR-21-01, 02, 04, VAR-01; ADR-0036). Separador **Publicações** no calendário: planear por conta e plataforma, arrastar, conflitos e limites das APIs (verificados a 29/10, editáveis só pelo dono da agência), variantes com a receita de 5 elementos, aprovação presa à versão e ao destino que deixa de valer quando algo muda, política por cliente (agência, cliente ou ambos; autoaprovação opcionalmente proibida), aprovação em lote, contas de destino "por ligar". Nada publica: a publicação automática chega quando as plataformas aprovarem a app.
- **W7 Aprendizagem** (FR-17-10, 11, 12, SCALE-06, BIZ-08, FR-14-05, FR-10-05; ADR-0037). Categoria ao rejeitar ou pedir alterações e painel de retrabalho; experiências de hooks e formatos com amostra mínima e critério de decisão; repetir vencedor como rascunho; recomendações com evidência e limitações; cargos no convite que pré-preenchem papel e exceções; exportar os meus dados e pedir eliminação; custos dos agentes por guião e publicação com tendência e CSV.
- Testes: SQL 1355/1355 (novos w7_busca 71, w7_pub 91, w7_learn 101); E2E 109/109; unitários search-format, pub-rules, learn-format.

## 2026-10-30 (vaga 1: negócio, desempenho e área de trabalho)

Tudo atrás de funcionalidades em teste: só o dono da agência vê até as ligar em **Funcionalidades em teste**.

- **W6 Vista de negócio** (BIZ-01 a 06, parciais; ADR-0032). Página **Negócio** com atingimento de entrega (meta 95%, alerta abaixo de 90% no ritmo do mês, atrasos do cliente à parte), faixa **Precisa da tua atenção** com até 5 alertas por gravidade e ação direta (também no Painel) e KPIs e tabela por cliente, da causa para o resultado. O staff da agência vê só o operacional dos clientes atribuídos; contratos, receita, custos e margem só o dono, decidido no servidor. Contratos por cliente versionados em EUR ou AED, câmbio com taxa e data visíveis, custos humanos e de ferramentas com repartição e margem. Saúde do cliente (BIZ-09) indicada como ainda sem dados.
- **W6 Centro de desempenho** (PERF-01 a 07, R-16, R-18, parciais; ADR-0033). Fotografias às 1 h, 24 h, 72 h, 7 d e 30 d guardadas de hora a hora; índice pela mediana da própria conta, sem comparar views entre contas; vistas por conta, plataforma, criador, camada, conteúdo, hook, estilo, tema, formato, geração e origem; saúde da conta; "o que replicar" com amostra mínima e relatório semanal. Cada publicação tem origem sistema ou externo, com correção auditada, e linhagem gravada ou inferida e marcada. Métricas que o scraping não dá aparecem como indisponíveis até ligar a conta pela API oficial. O Desempenho de sempre continua igual.
- **W6 Minha área de trabalho** (FR-01-03, FR-17-01, OPS-02, 03, 04, 10, parciais; ADR-0034). **A minha fila** no Início do cliente e caixa de entrada única: um item por objeto, decisões além de aprovações, gravações de hoje; ver, adiar, passar, começar e concluir, com auditoria. **Quem trabalha em quê**: cartões por pessoa só do cliente aberto, estados distintos (online, ativo com consentimento, a trabalhar, disponível), canal privado de avisos.
- Migrações `BIZMIG`, `PERFMIG`, `OPSMIG` (aditivas). Testes: SQL 1092/1092 (novos: w6_biz 62, w6_perf 63, w6_ops 77); E2E 80/80 (novos: biz, perf, ops); unitários perf-format 11/11.

## 2026-10-29 (funcionalidades em teste)

- **W0 MIG-09** interruptores de funcionalidades por cliente (CAP-09, ADR-0031). Cada módulo novo entra só para o dono da agência e liga-se em **Funcionalidades em teste** (menu da agência): para a equipa da agência ou para todos, na agência inteira ou cliente a cliente. O menu e as páginas escondem o que está desligado, também por endereço; as permissões continuam a ser verificadas no servidor. Nova capacidade `flags.manage` (dono da agência). Migração `20261029193316_w0_feature_flags` (aditiva). Testes: SQL 20/20.

## 2026-10-29 (campanhas e filtros do teleprompter)

- **W2-07** campanha, responsável, plataformas e etiquetas no guião (FR-02-03) e fila do teleprompter filtrável (FR-03-01), ADR-0029. Cada guião tem **Detalhes**: escolher ou criar uma campanha ou série, o responsável, as plataformas e etiquetas. Aparecem no cartão. Mudar isto não cria versão nem tira a aprovação; quem fica responsável recebe notificação. No teleprompter a fila filtra por campanha e por responsável ("só os meus"), por dispositivo. Nova capacidade `projects.manage` (dono, admin, gestor). Migração `20261029185412_w2_content_meta` (aditiva). Testes: SQL 30/30, E2E 2/2.

## 2026-10-29 (QC técnico dos vídeos)

- **EDL-03** QC técnico em código no motor (numeiro-engine #7, ADR-0028): formato 1080×1920, fps, duração, áudio, loudness e pico, troços pretos e congelados, retângulo seguro do layout e distinção por pHash face à fonte e às irmãs. `python run.py qc video.mp4`. Limites por cliente, pressupostos até ao piloto. O motor passa a ter CI com os testes do worker e do QC (vídeos gerados por ffmpeg). Também no motor: alojamento no Hetzner por cloud-init (numeiro-engine #6).

## 2026-10-29 (estilos de edição)

- **W5-02** catálogo de estilos e preset de edição (VAR-02 e EDL-01 parciais, ADR-0027). Nova página **Estilos de edição** no menu do cliente. Cada estilo é um template versionado: layout em 1080×1920 com pré-visualização, nível de transformação, plataformas e notas; gravar cria sempre uma versão nova e o histórico fica. O texto tem de ficar no retângulo seguro (x 60-960, y 210-1600), validado no servidor. O **preset** diz o que a edição automática gera por guião e fixa a versão de cada estilo; quando um estilo muda, o preset avisa. Numeiro começa com S01 a S13 (S13 "Faixa de estatuto" ativo com o layout do PRD, os outros em rascunho à espera do layout) e o preset por defeito do EDL-01: masters por hook, os dois split screens e S13. Outros clientes podem partir do mesmo ponto. Nova capacidade `styles.manage` (dono, admin e gestor). Migração `20261029180804_w5_edit_styles` (aditiva). Testes: SQL 34/34, E2E 3/3.

## 2026-10-29 (tempos de gravação)

- **W5-01** base da edição automática (ING-03 parcial, ADR-0026). O teleprompter regista quando cada guião é aberto, quando rola e para, cada mudança de bloco, os takes, a resposta ao "Gravaste?" e a saída, com a hora do dispositivo e do servidor. Fica no dispositivo e é enviado em lotes (também sem rede, sem duplicar). Na fila, **Tempos da sessão** mostra por guião quanto tempo se leu cada bloco e a que horas. É o que o corte automático vai usar. Migração `20261029165727_w5_recording_marks` (aditiva). Testes: SQL 17/17, E2E 2/2.
- PUB-03 (publicação assistida) registado como `adiado`: sem passos manuais, espera pela API (decisão do Tomás, 29/10).
- Menu: o aviso da Base UI sobre o estado inicial dos grupos com submenu deixou de aparecer.

## 2026-10-29 (revisão de guiões)

- **W2-06** revisão (FR-05-01, FR-05-02, FR-02-02; ADR-0025). Nova página **Revisão** no menu do cliente: guiões à espera de decisão com filtros por estado, responsável, prioridade, prazo e pesquisa, com o responsável, a prioridade e o prazo da tarefa de revisão. Cada guião tem **Comentários**: carregar numa frase para a comentar, responder, resolver e reabrir; cada comentário fica com a versão em que foi feito. O código de equipa do Numeiro também comenta. Migração `20261029162938_w2_review_comments`. Testes: SQL 33/33, E2E 3/3.

## 2026-10-29 (perfil)

- **W1-15** perfil (FR-14-01, ADR-0024) em `/perfil` e `/c/[ws]/perfil`, com entrada no menu da conta: nome, fotografia (bucket privado `avatars`), email verificado, mudar a palavra-passe (com a atual), "Esqueci-me da palavra-passe" no login, verificação em dois passos (TOTP) com o passo do código no login e aplicada no servidor (sessão sem código não acede a nada), fuso, tema, cliente ao entrar, terminar sessão em todos os dispositivos e histórico de segurança. Migração `20261029153629_w1_profile_mfa`. Testes: SQL 24/24, E2E 3/3 (incluindo REST e RPC recusados em aal1).
- FR-13-01 registado como `adiado`: o envio por email espera pela escolha do domínio (decisão do Tomás, 29/10).

## 2026-10-29 (convites por email)

- **W1-14** convites com link (FR-13-01, ADR-0023). Convidar envia o convite logo; cada convite tem Reenviar (token novo, validade renovada para 14 dias, máximo 5 envios, um por minuto) e Cancelar. A pessoa abre `/convite`, vê quem convidou, para onde e com que papel, e aceita (entrando com esse email) ou recusa sem precisar de conta. Expirados e recusados ficam na lista 30 dias. Email pelo Resend quando `RESEND_API_KEY` e `INVITE_FROM` estiverem no Vercel; sem isso a app mostra o link para copiar. Migração `20261029151140_w1_invite_delivery` (aditiva). Testes: SQL 25/25, E2E 5/5, unitários 6/6.
- Registo de estado: `check.py --set` para editar uma linha. Correção: notas de QA-01, 02, 03, 11, 13 e 16 dos PRs #29 e #30 tinham sido apagadas pelo `--fix` (a edição apanhava a tabela gerada); repostas.

## 2026-10-29 (E2E no CI)

- **W0-QA-02** E2E com contas reais no repositório e no CI (ADR-0022). Playwright contra uma stack Supabase local (migrações e dados sintéticos), com quatro contas criadas só ali: dono da agência, staff só com o A, equipa do A e equipa do B. 41 testes: isolamento A/B pela UI, pela REST e por RPC; espaço certo por papel; 19 rotas por URL e refresh sem erros na consola; código de equipa. `npm run test:e2e` corre localmente (precisa de Docker). Fixture com hooks no formato real (`{text, mecanismo}`).

## 2026-10-29 (testes no CI)

- **W0-QA-01** testes SQL no CI (ADR-0021): job `db` aplica as 57 migrações numa base limpa e corre os 21 ficheiros de `supabase/tests` (707 casos) sobre dados sintéticos. Quatro testes desatualizados corrigidos: `w1_review_fixes` (a versão aprovada vive em `content_versions` desde W2-01), `w4_worker` (o worker fixa `engine.client_id` desde W4-03), `w4_engine_isolation` e os de datas (`w1_data_access`, `w2_teleprompter`, `w3_calendar`), que dependiam de dados e dias de produção. R-19 registado como `adiado` por decisão do Tomás (API oficial no futuro, Apify por agora).

## 2026-10-29 (PRD)

- **CHG-004** registo de estado por requisito (`docs/status.md`) validado no CI, início e fim de tarefa pelo registo, adiamentos registados e revisão automática diária. PRD §33, §36.

## 2026-10-29 (CHG-003 PRD Parte IV)

- **CHG-003 linha de produção, medição e distribuição em escala** (só documentação; PRD Parte IV §37-§44). Regras R-16 (origem sistema/externo), R-17 (hipérbole de persona, decisão de produto; AGENTS §7 com a exceção), R-18 (linhagem gravada no momento), R-19 (só APIs oficiais). Requisitos BIZ (vista de negócio), ING/EDL (ingestão, armazenamento, pacote de edição, revisão em lote), PERF (centro de desempenho), VAR (variantes, estilos, republicação), PUB (publicação automática, modo assistido, calendário), PLAT (aprovações das plataformas). Sequência de entrega revista em §44: medição antes de media. 12 capacidades novas registadas como planeadas. Sem alteração funcional.

## 2026-10-29 (CI)

- **Vercel salta builds sem mudanças na app** (`vercel.json` → `scripts/vercel-ignore.sh`): commits só de documentação, migrações e testes SQL, testes unitários ou CI deixam de gastar deploys do limite diário. Na dúvida, constrói.
- Testar sem deploy: `npm install` e `npm run dev` no próprio computador, em `http://localhost:3000` (já nas Redirect URLs do Supabase). Usa a base de dados de produção.

## 2026-10-29 (W1 Equipa da agência)

- **W1-13 Equipa da agência** (PRD §2, §3, R-12, R-14, M13 parcial; ADR-0020; migração `20261029130512_w1_agency_team`).
  - Nova página no menu da agência: quem é staff, papel na agência, estado, último acesso, clientes onde trabalha (com o papel) e tarefas abertas.
  - O dono convida para a agência, muda papéis, suspende e reativa, e atribui ou tira pessoas dos clientes. Os admins da agência só veem.
  - Quem vê só fica a conhecer os clientes a que também tem acesso.
  - Quem é da equipa de um cliente não pode ser convidado para a agência.
  - Se aceitar um convite falhar, a pessoa vê o motivo em vez de "sem acesso".
  - Testes: `w1_agency_team` 24/24.

## 2026-10-29 (Alojamento)

- **Um só projeto Vercel:** produção passa a ser `https://clipstudio-jchs.vercel.app`; apagados os duplicados `clipstudio` e `clipstudio-c8h1`, que triplicavam cada deploy e esgotaram o limite diário do plano gratuito. Supabase Auth: Site URL e Redirect URLs têm de apontar para `https://clipstudio-jchs.vercel.app` (e `/**`), mais `http://localhost:3000/**` para desenvolvimento.

## 2026-10-29 (registo de estado)

- **CHG-004 implementação.** `docs/status.md` com os 263 IDs do PRD, semeado por uma auditoria independente (17 feito, 145 parcial, 98 por começar, 3 bloqueado). `scripts/status/check.py` valida o registo contra o PRD e o CI `Qualidade` recusa PRs que mexem em `src/` ou `supabase/migrations/` sem o atualizar. AGENTS §3/§13 e CLAUDE.md: tarefas começam e acabam no registo. Revisão automática diária às 07:23 (Dubai). Linhas com UI sem verificação com conta real ficaram `parcial`.

## 2026-10-29 (PRD)

- **CHG-002** R-15 (falhas contidas, gestor único de canais, sessões que não caem por falhas de rede, gate de release com CI e E2E com conta real) e QA-16. Origem: incidente de `/c/numeiro`; correção no W1-12 (#20).

## 2026-10-29 (W1 Correção)

- **W1-12 erro ao abrir um cliente** (ADR-0019, PRD R-07; CHG-002).
  - Corrigido: abrir o Início de um cliente com conta caía no ecrã de erro do browser. Dois widgets abriam o mesmo canal de tempo real dos guiões.
  - Os canais de tempo real passam a ser partilhados por um gestor único; nada abre canais fora dele.
  - Se uma página ou um widget falhar, aparece uma mensagem em português com "Tentar de novo" e o resto da app fica de pé.
  - CI novo em cada PR: guardas de execução, lint, tipos, testes unitários e build.
  - Testes: `realtime-hub` 9/9, `safeNext` 10/10; E2E da estrutura 15/15.

## 2026-10-29 (PRD)

- **CHG-001** espaço da agência e espaço do cliente (R-13), isolamento dos convites e cliente único (R-14), cliente no endereço, menu da agência e peças previstas. PRD §2, M01, §22, §33, §36. Implementado no W1-11 (#18).

## 2026-10-29 (W1 Espaços da agência e do cliente)

- **W1-11 espaço da agência e espaço do cliente** (PRD §2, R-01, R-03, R-04; ADR-0018; migração `20261029121252_w1_single_client_staff`).
  - A equipa da agência entra no **Painel da agência**, com menu próprio: Painel, Clientes, Caixa de entrada de todos os clientes e, em breve, equipa da agência, calendário de todos, custos, histórico e definições da agência.
  - Carregar num cliente abre o **espaço do cliente** (`/c/<cliente>/…`) com o menu operacional e a administração desse cliente; "← Agência" volta ao painel e o seletor salta para outro cliente.
  - A equipa de um cliente e o código de equipa vão direto para o seu cliente e não veem nada da agência; um cliente a que não tens acesso (ou que não existe) mostra a mesma mensagem.
  - Links antigos (`/guioes`, `/tarefas?tab=…`) continuam a funcionar e abrem o último cliente.
  - Convites: quem já pertence à equipa de um cliente não pode entrar na equipa de outro; o convite é cancelado e fica no histórico.
  - Correção: a sessão por código já não termina por uma falha de rede a meio de uma navegação.
  - Testes: `w1_invite_isolation` 23/23 (convite da agência ao cliente, do cliente à sua equipa, cliente único, staff da agência); E2E da estrutura 15/15; regressão do Início 15/16 (a única diferença é a esperada: `/agencia` com código passa a abrir o próprio cliente).

- **W1-10 Início por cliente e painel da agência** (PRD FR-01-01, FR-01-02, FR-01-06 parcial, R-04; ADR-0017; migração `20261029114823_w1_dashboard`).
  - O Hoje passa a **Início**: escolhes o período (7, 30, 90 dias ou datas tuas) e cada número compara com o período anterior do mesmo tamanho. Cada número tem a explicação de como se calcula (toca no ⓘ).
  - Números: fontes, guiões criados, à espera de aprovação, aprovados, gravados, publicados, views, engagement, custo dos agentes e tarefas concluídas, cada um só para quem tem permissão.
  - **Personalizar** (dono e admin do cliente): escolher e ordenar os widgets de cada função; repor o original; tudo no histórico.
  - **Agência** (`/agencia`, equipa da agência): os teus clientes lado a lado com totais, variação e "Abrir"; diz quantos clientes ficaram de fora de cada número por falta de acesso.
  - A meta de guiões por dia vem da configuração dos agentes do cliente (já não é 30 fixo).
  - Testes: `w1_dashboard` 38/38; E2E em modo código 16/16 (período, explicação, comparação, permissões, telemóvel).

- **W4-03 dados do motor por cliente, fase contract** (ADR-0016; migração `20261029113539_w4_engine_client_contract`).
  - Chaves passam a (cliente, id): dois clientes podem acompanhar o mesmo criador, cada um com os seus reels, análises, temas, citações e meta.
  - O worker do motor só vê e escreve o cliente da sua sessão; sem cliente não vê nada.
  - Guiões, análises e referências só apontam para reels, temas e citações do mesmo cliente.
  - Desempenho, Hoje e as vistas `v_*` filtram pelo cliente do reel. Saem os acessos de leitura antigos da API a estas tabelas.
  - Testes: `w4_engine_isolation` 23/23 (regras novas); regressão `w2_references` 36/36.

- **W4-03 dados do motor por cliente, fase expand** (PRD R-02, SCALE-07 parcial; ADR-0016; migrações `20261029111417_w4_engine_client_scope`, `20261029111654_w4_engine_client_fill`, `20261029111703_w4_engine_client_fill_nested`, `20261029111826_w4_engine_client_fill_definer`).
  - Reels, temas, citações, análises, guiões gerados, meta e relatórios do motor passam a pertencer a um cliente; os dados atuais ficam no Numeiro.
  - O motor (numeiro-engine) só lê e escreve no cliente da execução. Reels novos ficam ligados à conta do cliente e entram no Desempenho.
  - Referências e Descobrir só usam reels e análises do próprio cliente, mesmo que a conta diga outra coisa.
  - Até à fase contract, o mesmo reel ou tema em dois clientes dá erro em vez de misturar dados.
  - Testes: `w4_engine_isolation` 20/20; regressão `w2_references` 36/36; motor `test_pgdb` 8/8 (Postgres local) e `test_worker` 19/19.

## 2026-10-29 (W1 Fundação, fecho)

- **W1-09 histórico de ações** (PRD R-05, CAP-07 parcial, FR-15-06 parcial; ADR-0015; migração `20261029110013_w1_audit_list`).
  - `/historico` (Administração): quem fez o quê no cliente, do mais recente para o mais antigo, com o que mudou (antes e depois), filtros por ação, pessoa e período (no fuso do cliente) e "Carregar mais".
  - Só para quem tem `audit.read` no cliente; nunca mostra outros clientes; a tabela continua fechada à API e o registo não se altera.
  - Testes: `w1_audit` 16/16.

- **W1-08 consola de permissões** (PRD CAP-02, CAP-03, CAP-05, CAP-07 parcial; ADR-0014; migrações `20261029105036_w1_permissions_console`, `20261029105538_w1_capability_labels`).
  - `/permissoes` (Administração): por pessoa, cada capacidade com o estado (pelo papel, exceção, negado, sem acesso), o porquê e as ações permitir, negar e retirar exceção, com motivo obrigatório e prazo opcional; por papel, a matriz papéis × capacidades; e a lista das exceções ativas.
  - Quem não gere permissões vê "As tuas permissões" com o porquê de cada uma.
  - Regras no servidor: só se dá o que se tem, nunca a si próprio nem acima do seu nível, staff da agência só pelo dono, negar prevalece, uma exceção ativa por pessoa e capacidade, nada se apaga e tudo fica auditado.
  - Todas as capacidades passam a ter nome em português no registo.
  - Testes: `w1_permissions` 35/35; regressão `w1_isolation` 38/38.

- **W1-07 definições do cliente** (PRD M15 FR-15-01, FR-15-02 parcial, FR-15-08 parcial; ADR-0013; migrações `20261029103605_w1_settings_branding`, `20261029103627_w1_settings_branding_strict`).
  - `/definicoes` (Administração): nome, @, fuso, moeda, logótipo e cor da marca; regra "só se gravam guiões aprovados"; limite de tarefas abertas por pessoa; atalhos para agentes, templates, automações e equipa; arquivar (dono da agência).
  - Logótipo num bucket privado: só quem trabalha no cliente o vê, só quem gere as definições o muda, nunca de outro cliente; PNG, JPG ou WebP até 500 KB. Aparece no seletor de cliente, com a cor da marca.
  - Tarefas aceita `?tab=templates|regras|carga`.
  - Testes: `w1_settings` 20/20; regressão `w1_clients` 55/55.

- **W1-06 clientes e gestão de equipa** (PRD §2, §3, CAP-03, CAP-06, CAP-08, SCALE-07, FL-01, TEAM-15, M15 parcial; ADR-0012; migrações `20261029100534_w1_clients_team`, `20261029101111_w1_drop_tmp_import`).
  - `/clientes` (agência): lista dos clientes com equipa, convites e estado da configuração dos agentes; criar cliente (nome, @, fuso, moeda), com opção de começar com a estrutura de outro cliente (formatos e regras dos agentes, templates, automações; nunca a voz, léxico, notícias, pessoas, guiões nem dados); editar; arquivar com motivo e confirmação; recuperar.
  - O dono da agência vê todos os clientes; o admin da agência só os atribuídos; a equipa de um cliente não tem acesso à lista.
  - `/equipa`: mudar papel, suspender, reativar e remover membros (nunca a si próprio, só até ao seu nível, o último dono do cliente fica protegido); ao remover, as tarefas abertas passam para quem escolheres. O dono da agência atribui staff da agência a um cliente sem convite. Voltar a convidar quem foi removido reativa o acesso.
  - Menu: Clientes em Administração e "Gerir clientes" no seletor de cliente.
  - Removida a função antiga `tmp_import`.
  - Testes: `w1_clients` 55/55; regressão `w1_team` 21/21 e `w1_isolation` 38/38.

## 2026-10-29 (W4 IA e jobs)

- **W4-02b preços dos modelos** (FR-06-05; migração `20261029095100_w4_model_prices`): preços públicos da Anthropic registados com fonte e data (Opus 5.5 4/20 USD, Sonnet 5.5 2/10 USD, Haiku 5.5 0,10/0,50 USD por milhão de tokens de entrada/saída, Haiku com escalão acima de 100 000 tokens, pesquisa web 10 USD por 1000), convertidos para EUR ao câmbio do BCE de 28/10/2026. O motor passa a contar também as pesquisas web no custo. Com isto, o custo de cada execução deixa de ficar desconhecido e o limite diário passa a funcionar. Testes do worker 19/19.

- **W4-02 worker do motor ligado à fila** (PRD FR-06-03, FR-06-05 parcial, FR-06-06 parcial; ADR-0011; migrações `20261029092137_w4_engine_worker`, `20261029093332_w4_worker_finish_cost_unknown`, `20261029093455_w4_worker_search_path`).
  - O motor passa a correr como worker (`python run.py worker`, repositório privado `numeiro-engine`): apanha as execuções da fila, usa a configuração da versão ativa e grava cada guião aprovado pelo Crítico diretamente na app, em revisão, no dia seguinte (ou no próprio dia, escolha nova na configuração).
  - Repetir não duplica guiões; cancelar pára entre guiões; reinício do alojamento devolve a execução à fila; o limite de custo diário pára a meio e fecha como parcial.
  - Tokens e custo por chamada de agente e por execução. Sem preços dos modelos o custo fica desconhecido em vez de 0.
  - A corrida diária passa a ser enfileirada pelo próprio Supabase a cada 5 minutos.
  - Utilizador de base próprio para o worker, com o mínimo de acesso e sem login até ser configurado.
  - Na página dos agentes, o progresso aparece em linguagem de pessoa (etapa, guiões gravados, chumbados, motivo de paragem) com link para os guiões do dia.
  - Testes: `w4_worker` 30/30, `w4_agents` 44/44 (regressão), worker em mock 16/16, payload real do motor validado na base, E2E 7/7.

- **W4-01 agentes: catálogo, configuração versionada e execuções duráveis** (PRD M06, FR-06 parcial, NFR durabilidade de jobs; ADR-0010; migração `20261029084441_w4_agents_config_jobs`).
  - `/agentes/configuracao`: catálogo dos 13 agentes do motor (etapa, modelo, o que lê e escreve), versão ativa, corrida diária, estado do worker e lista de execuções.
  - Configuração por cliente (voz, léxico, regras, formatos com proporções, produção, modelo por agente, agenda, limite de custo, áreas de notícias, leituras). Cada gravação é uma versão nova validada no servidor; ativar uma antiga volta atrás. O preset Numeiro é só a versão 1 deste cliente.
  - Execuções duráveis: Correr agora (uma por tipo e dia), cancelar, repetir, tentativas com espera crescente, lease com heartbeat, falha definitiva com notificação, limite de custo diário. As execuções ficam em fila até o worker do motor ser ligado (W4-02): nada aparece como corrido sem ter corrido.
  - Custos só para quem tem `costs.read`. As funções do worker só existem para o servidor.
  - Testes: `w4_agents` 44/44.

## 2026-10-29 (W3 Operações)

- **W3-01 tarefas, handoffs e caixa de entrada** (PRD TEAM-06, TEAM-12, FR-11-02 parcial, FR-17-01, FR-17-05, TEAM-15 parcial; ADR-0007; migração `20261029071504_w3_tasks_handoffs_inbox`).
  - `/tarefas`: As minhas, Abertas, Sem responsável, Feitas e Automações. Cada tarefa tem tipo, responsável, prazo, prioridade, estado, motivo de bloqueio, dependências, guião ou fonte ligados, comentários com menções e histórico.
  - Só se atribui a quem tem acesso a tarefas no cliente. O responsável muda o estado das suas; quem gere muda tudo. Edições concorrentes não se sobrepõem.
  - Automações por cliente: por exemplo "guião enviado para revisão → tarefa Rever guião {n} para a Ana, prazo 24 h, fecha quando for aprovado ou rejeitado". Repetir o mesmo evento não duplica tarefas.
  - `/caixa`: notificações, as minhas tarefas, guiões à espera da minha aprovação e tarefas sem responsável, de todos os clientes a que tenho acesso. Marcar lido não aprova nada. Quem perde acesso deixa de receber e de ver.
  - Capacidade nova `tasks.work`; `tasks.read` e `tasks.manage` ativas. O código de equipa só lê tarefas.
  - Testes: `w3_tasks` 53/53, `w2_content` 47/47 (regressão com o consumidor de eventos). E2E em workspace de teste isolado 20/20 (modo código, só leitura).

- **W3-02 calendário e estados de produção** (PRD M11 FR-11-01, FR-11-02 parcial, FR-11-03 parcial, FR-11-05 parcial; ADR-0008; migração `20261029074048_w3_calendar_production`).
  - `/calendario` por dia, semana e mês, com guiões (cor pelo estado de produção, atrasados a vermelho), tarefas pelo prazo à hora local e sessões de gravação com o número de takes.
  - Arrastar um guião para outro dia reagenda-o (ou "Mover para" no detalhe, para teclado e iPad); arrastar uma tarefa muda o dia do prazo e mantém a hora. Nada vai para o passado e edições em simultâneo são recusadas.
  - Estados de produção novos na app: agendado, em edição, pronto, cancelado; cada passo com a sua capacidade (`calendar.schedule`, `production.update`; gravar continua em `recording.confirm`).
  - Automações de tarefas reagem a "em edição" e "pronto" (ex.: gravado → passa a edição → tarefa para o editor, fecha quando fica pronto).
  - Guiões e teleprompter passam a tratar em edição e pronto como já gravados.
  - Testes: `w3_calendar` 39/39, `w2_content` 47/47 (regressão do `content_production`). E2E em workspace de teste isolado 18/18 (modo código).
- **Calendário: detalhe do guião completo**: hooks com mecanismo, corpo, CTA, notas, estado editorial, formato e tarefas ligadas (com estado, responsável e prazo) no painel que abre ao tocar num guião. E2E 6/6.
- **W3-03 templates de produção, checklists e carga** (PRD FR-11-04, FR-17-08, FR-17-09, TEAM-08 parcial; ADR-0009; migração `20261029081024_w3_templates_checklists_workload`).
  - Tarefas → Templates: lista de tarefas com dia relativo ao guião, hora, responsável e "depois da anterior", mais uma checklist. Copiar para outro cliente (só quem gere os dois; sem responsáveis).
  - No calendário, o detalhe do guião tem a checklist (quem marcou e quando) e "Aplicar template": cria as tarefas com prazos e dependências e a checklist. Aplicar de novo não duplica.
  - Tarefas → Carga: por pessoa, abertas, em curso, bloqueadas, atrasadas, próximos 7 dias e feitas na semana, com limite opcional que só avisa.
  - Testes: `w3_templates` 35/35. E2E em workspace de teste isolado 7/7 (modo código, só leitura).
- Limitações W3-02: sem vista por equipa/plataforma/campanha nem deteção de sobrecarga (FR-11-03), sem publicações no calendário (W6), sem templates e checklists (FR-11-04). O motor cria guiões numerados 1..30 por dia: um guião movido para um dia futuro antes da corrida do motor pode partilhar o número com um novo (contrato do motor a fechar no W4; **UNVERIFIED**).

### Limitações conhecidas W3-01 (PARTIAL)

- Sem lembretes de prazo agendados (o atraso aparece na lista e na caixa, mas não gera notificação sozinho) nem escalonamento por SLA (FR-17-06).
- Sem projetos nem campanhas: o âmbito é o cliente. Templates e carga entregues no W3-03; sem estimativas de horas nem disponibilidade por pessoa, sem equipas funcionais (TEAM-08) nem redistribuição em lote (FR-17-07).
- Sair da equipa não pede reatribuição automaticamente; as tarefas ficam em "Sem responsável".
- Notificações só dentro da app (sem email/push).

## 2026-10-29 (CHG-000 processo)

- **CHG-000 PRD com fonte única e trabalho por PR** (PRD §28, §33; AGENTS §10, §11, §15; ADR-0004). O PRD só é escrito neste repo e só muda em PRs só de documentação com `docs/changes/CHG-NNN.md`; o workflow `PRD guard` chumba o resto. `CLAUDE.md` ganha a secção "Change workflow": nada de push direto para `main`, merge por PR com checks verdes e preview verificado, migrações em expandir/contrair. Sem alteração funcional.
- Por fazer: ligar a proteção do `main` no GitHub (PR obrigatório, 0 aprovações, checks `prd-guard` e Vercel obrigatórios). Até lá o guard avisa mas não bloqueia.

## 2026-10-29 (W2 Conteúdo)

- **W2-01 modelo canónico de conteúdo** (PRD §4, §7, §23, FR-02-01..06, FR-17-04; ADR-0002). Migrações `20261028195656_w2_content_core`, `20261028195905_w2_legacy_sync`, `20261028200818_w2_conflict_code_pt409`.
  - `guioes` ganha estado editorial (`draft → in_review → changes_requested/approved/rejected`, `archived`) e de produção independentes, `cta`, `notas`, `lock_version`.
  - `content_versions` imutáveis; a aprovação fica presa à versão exata (`approved_version_id`); editar um aprovado volta a rascunho sem perder a aprovação antiga.
  - `content_transitions` append-only; outbox `domain_events`; auditoria em cada ação.
  - RPCs `content_save`, `content_transition`, `content_production`, `content_create`, `content_duplicate`, `content_history`, `content_restore_version`; `guiao_update` passa a usar o modelo novo.
  - Os 30 guiões existentes migrados com versão 1 e estado "em revisão".
- **W2-02 app de guiões**: editor por blocos (Hook 1..N, Corpo, CTA, Notas) que guarda sozinho e deteta conflitos de edição; Aprovar, Pedir alterações, Rejeitar (motivo obrigatório), Retirar aprovação, Recuperar; Histórico com versões, autoria e "Usar este texto"; Novo guião, Duplicar, Arquivar conforme a capacidade; filtros por estado. Teleprompter mostra o CTA e deixa de engolir erros ao marcar gravado.
- **W2-05 teleprompter** (PRD M03 FR-03-01..07, §20, FL-03; ADR-0006; migrações `20261028211702_w2_teleprompter`, `20261028211915_w2_teleprompter_same_ws_fix`, `20261028212101_w2_teleprompter_prefs_revoke_anon`, `20261028213636_w2_teleprompter_search_path`).
  - Fila de gravação do dia guardada no servidor e partilhada entre dispositivos (iPad e computador veem a mesma): transitados primeiro, reordenar, saltar guiões e saltar blocos; sem rejeitados nem arquivados.
  - Leitura por blocos (Hook 1..N, Body, CTA) com saltar para o bloco anterior/seguinte.
  - Takes por bloco ("Take" ou tecla T): numerados, ligados à versão lida, escolher o melhor, descartar, notas. Não mudam o estado do guião; "gravado" continua a pedir confirmação.
  - Sem rede, os takes ficam no dispositivo e são enviados quando a ligação volta, sem duplicar.
  - Retomar onde se ficou, também noutro dispositivo.
  - Espelho horizontal e vertical independentes, velocidade, letra, entrelinha, margens, contraste (branco, alto, âmbar), atalhos configuráveis para comandos Bluetooth, ecrã inteiro por botão, tecla ou duplo toque, ecrã sempre ligado quando o browser deixa (e aviso quando não deixa).
  - Preferências guardadas por utilizador e dispositivo (com conta) ou só no dispositivo (código de equipa).
  - Testes: `w2_teleprompter` 52/52; E2E em workspace de teste isolado 28/28 (inclui offline, dois dispositivos, iPad e telemóvel).
- **W2-04 referências** (PRD M07; ADR-0005; migrações `20261028205017_w2_references`, `20261028205134_w2_references_zero_duration`).
  - `/referencias` (sai de "em breve"): Biblioteca com pesquisa, coleções e favoritos; Descobrir com os reels dos criadores seguidos ainda por guardar, ordenados por quanto ficaram acima da mediana, já com a análise; Arquivo.
  - Guardar um reel na biblioteca herda hook, formato, narrativa, duração e idioma; adicionar por link; classificar (formato, estilo, narrativa, duração, idioma, tags, coleções, notas).
  - Métricas só com origem e data ("scraper · 29/10"); referências por link não mostram números.
  - Referências no painel do guião (ligar e desligar) e "Usada em" na biblioteca. Também ligáveis a fontes.
  - Corrigido antes de chegar à app: reels com duração 0 faziam falhar o guardar.
  - Testes: `w2_references` 36/36; E2E em workspace de teste isolado 13/13.
- **W2-03 fontes, briefs e pedidos do talento** (PRD M04, FR-17-02/03, §20; ADR-0003; migração `20261028202656_w2_sources_briefs_requests`).
  - `/fontes` substitui `/ideias` (redirecionamento): separadores Por triar, Selecionadas, Pedidos, Usadas, Descartadas, Todas; pesquisa; Adicionar fonte por link com deteção de repetidos; Selecionar, Em triagem, Descartar com motivo; Criar guião a partir da fonte.
  - Corrigido: o "take" e a expiração das fontes nunca apareciam (a página lia campos que não existem).
  - Pedido do talento por texto ("Pedir um tema"), também disponível no código de equipa. Nada é gerado sem aprovação.
  - Painel "Brief e fontes" em cada guião: brief estruturado com versões, fontes ligadas, ligar e desligar. A aprovação guarda o brief em vigor; se mudar depois, a app avisa.
  - Capacidade nova `requests.create`. URL repetido vindo do motor não derruba a corrida: entra descartado com a referência ao original.
  - Testes: `w2_sources` 41/41, `w2_content` 47/47 (regressão). E2E em workspace de teste isolado 16/16.
- Testes (W2-01/02): `w2_content` 47/47, `w1_review_fixes` 11/11, `w1_data_access` 25/25 (com o modelo novo). E2E de escrita num workspace de teste isolado (criado e apagado no fim) 23/23.

### Limitações conhecidas W2 (PARTIAL)

- Teleprompter: sem anexar ficheiro ao take (W5), sem filtros por campanha/responsável (W3), sem blocos personalizados, não abre já sem rede.
- Sem eliminação definitiva (só arquivo); sem diff visual entre versões; sem bulk actions (FR-02-05) nem vistas guardadas (FR-02-07).
- Outbox sem consumidores (W4). Estados de produção além de gravado chegam no W3.
- Fontes: sem RSS/integrações nem resumo por IA; o motor ainda não prioriza fontes selecionadas nem lê pedidos (W4). Referências (M07) entregues no W2-04.

## 2026-10-28 (W1 Fundação)

- **Produção**: app no Vercel em `https://clipstudio-c8h1.vercel.app` (deploy automático a cada push no `main`). Projeto Supabase `numeiro-engine` transferido para a organização **Informal Labs** (mesmo ref, mesmas chaves). Auth: Site URL = Vercel; Redirect URLs = `https://clipstudio-c8h1.vercel.app/**` e `http://localhost:3000/**`. E2E em produção 21/21; anónimo continua sem acesso (401/42501).

- **W1-01 identidade e tenancy** (PRD §2, §3, §16, CAP-01..04, TEAM-01..03): organização ClipStudio, `workspace_access`, `agency_memberships`, `permission_grants` (allow/deny com expiração), `invitations`, `audit_events` append-only, registo de capacidades e `authorize(cap, ws)` deny-by-default. ADR-0001.
- **W1-02 corte do acesso aos dados**: fim das leituras anónimas; RLS por `authorize()`; RPCs verificam o workspace (login) ou o token legado (`legacy_can`); escritas auditadas; canal de agentes privado (`agents:<ws>`); guiões no realtime.
- **W1-03 app com login individual**: `/login` (email+palavra-passe; Google aparece só quando o fornecedor estiver ativo no Supabase; código de equipa como opção de transição), `/auth/callback` (PKCE, destino só interno), `src/proxy.ts` (verificação otimista, renova cookies), contexto de workspace com troca entre clientes autorizados, todas as páginas atrás de `WorkspaceGate` com a capacidade certa, menu lateral derivado das capacidades.
- **Ecrã de entrada novo (efferd `auth-5`)**: email primeiro, depois palavra-passe (entrar ou criar conta); Google só aparece quando o fornecedor estiver ligado; código de equipa como opção discreta. Removidos do bloco os botões Apple/GitHub, o testemunho inventado e os links `#` (AGENTS §4). Links de email que caiam na Site URL com `?code=` passam a ir para `/auth/callback`; `otp_expired` (link já usado) mostra uma mensagem clara em PT-PT.
- **Equipa (`/equipa`)**: membros, convites pendentes, convidar (papel até ao teu teto; staff da agência só pelo dono), cancelar convite. RPCs `workspace_team`, `revoke_invitation` (migração `20261028185835_w1_team_rpcs`).
- **Revisão de segurança independente** (migração `20261028191546_w1_review_fixes`):
  - Open redirect em `next` (`/%09/evil.com` virava `//evil.com`): helper único `src/lib/safe-next.ts` que recusa caracteres de controlo e confirma a origem.
  - Editar um guião validado anula a validação (AGENTS §2.6), com a versão anterior no histórico e `validacao_anulada` no audit; `status` só aceita `aprovado`/`rejeitado`.
  - Convidar staff da agência passa a exigir o dono da agência também no servidor (antes só a UI escondia).
  - Entrar com conta apaga o código de equipa guardado nesse browser.
  - Testes negativos passam a exigir o SQLSTATE certo (antes qualquer erro contava como recusa).
- Testes SQL (com rollback): `w1_isolation` 38/38, `w1_team` 21/21, `w1_data_access` 25/25, `w1_review_fixes` 10/10. `tests/safe-next.test.mts` 10/10. E2E Playwright (modo código e anónimo) 11/11.

### Limitações conhecidas W1 (PARTIAL)

- Tentativas negadas vão para o log da base (`RAISE LOG audit_denied`), não para `audit_events` (o rollback da exceção apagava-as).
- Convites não enviam email: quem convida avisa a pessoa.
- Google OAuth por configurar no Supabase (o botão fica escondido até lá).
- Motor ainda não integrado (escreve em `generated`, `agent_log` sem `client_id`).
- Consola de permissões (CAP-02): feita no W1-08, exceto papéis personalizados.
- `tmp_import` ainda pode ser chamada por anónimos (protegida só por token fixo) e escreve em `reels`/`script_analysis`: apagar quando confirmares que já não é usada.
- Código de equipa: sem expiração nem limite de tentativas em `studio_whoami`, e o `?k=` fica nos logs do servidor antes de sair do URL. Aceitável só durante a transição; retirar quando o Numeiro tiver conta.
- Extensão `citext` no schema `public`.
- E2E com contas reais (agência A+B, cliente A, cliente B) depende de contas criadas pelo Tomás; os testes SQL cobrem esses casos com utilizadores simulados.

## 2026-10-28

- **W0 (inventário e contratos)**: `docs/inventory/supabase.md`, `docs/inventory/engine-and-app.md`, `docs/feature-registry.md`, `docs/access-matrix.md`, `docs/workflow-registry.md`. As 15 migrações aplicadas estão agora em `supabase/migrations/` (segredos tapados; o repo é público).
- **SEC-HOTFIX-001**: `anon`/`authenticated` tinham INSERT/UPDATE/DELETE por defeito; a vista `agent_feed` (security definer) permitia apagar `agent_log` com a chave pública. Revogada toda a escrita direta, fechadas as vistas `v_*` à API, privilégios por defeito corrigidos. Reteste: escrita 401, app 200.
- Design system: shell e dashboard passam para o efferd `app-shell-3` + `dashboard-3`. Navegação com estado ativo por rota; módulos do PRD ainda sem página aparecem como "em breve", sem link (AGENTS.md §4).
- Hoje (`/`): layout do dashboard-3 com dados reais: guiões do dia, validados, gravados, views 30 dias vs 30 anteriores, views por dia (7/30/60), mix de formatos, produção diária, views médias por semana, agentes da última corrida real, guiões de hoje e atividade. Nova RPC só de leitura `hoje_resumo(p_client)`.
- Desempenho (`/desempenho`): passa ao layout do dashboard-3, por conta: views 30 dias e reels publicados vs 30 dias anteriores, mediana, virais, views por dia (7/30/60), reels por nível de outlier, views médias por semana, produção diária, mediana vs referências, top reels e últimos publicados. A RPC `desempenho` ganha `diario`, `bandas` e os totais dos 30 dias anteriores. Removidos os componentes de demonstração do dashboard-5 que já não eram usados.
- Teleprompter: deixa de marcar "gravado" sozinho aos 80% de leitura. Ao avançar ou sair pergunta "Gravaste?" (Enter/Esc). Cumpre AGENTS.md §6 e PRD §20.
- Sala dos agentes: o ensaio deixa de inventar resultados (AGENTS.md §7). Mensagens marcadas `[ensaio]`, só temas e hooks reais. Ensaios não contam no Hoje.
- Sessão: diálogo do código de equipa único no shell; menu do utilizador mostra a sessão real (sem perfil de demonstração).
- Documentação: `AGENTS.md` v1.1 (com regras do Next.js preservadas), `CLAUDE.md` e `docs/ClipStudio_PRD_Master_v2.1.md`.

### Limitações conhecidas (PARTIAL)

- Acesso ainda por código de equipa partilhado; Supabase Auth individual e workspaces (PRD §2, §16, MIG-04) por fazer.
- Sem testes automatizados no repo (só E2E manual com Playwright nesta sessão).
- `feature-registry.md`, `access-matrix.md`, `workflow-registry.md` e ADRs ainda por criar.
