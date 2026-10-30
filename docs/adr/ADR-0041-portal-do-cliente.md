# ADR-0041 · Portal do cliente

**Estado:** aceite · **Data:** 2026-10-30 · **Requisitos:** SCALE-08 (parcial, ver Consequências); toca R-13, R-14, TEAM-10, PUB-06, FR-17-01, AGENTS §9

## Contexto
SCALE-08 pede um portal de cliente com aprovação externa, estado de entregas, relatórios e pedidos de conteúdo, sem acesso à administração da agência. As peças já existem em módulos separados: aprovação editorial (`content_transition`, `content_transition_reasoned` com `learn.rework`), aprovação de publicações com política TEAM-10 (`pub_approve`, flag `pub.planning`), atingimento de entrega e contratos (BIZ-01/05, `_biz_ops`, `client_contracts`, espaço da agência), centro de desempenho (`perf_center`, `perf_levers`, flag `perf.center`) e pedidos do talento (`ideas.kind = 'talent_request'`, `talent_request_create`). A equipa do cliente tem de as encontrar num só sítio, sem ver custos, outros clientes, flags ou permissões (R-13, AGENTS §9).

## Decisão
- **Espaço: cliente.** Rota `/c/<cliente>/portal`, item "Portal" no menu do cliente (cap `scripts.read`, flag `client.portal`) e um aviso no Início do cliente para a equipa do cliente e o código de equipa quando a flag está ligada. A equipa da agência atribuída (e o dono da agência) pode abrir o portal e vê "Estás a ver o portal como a equipa do cliente o vê"; as suas ações contam como da agência (`_pub_actor_side`).
- **Só leituras novas; ações pelas RPCs de sempre.** `portal_home(ws, token)` agrega cinco blocos; `portal_block(ws, bloco, token)` devolve um (para recarregar depois de uma ação ou "tentar de novo"). Aprovar/pedir alterações/rejeitar guião, aprovar publicação e criar pedido chamam diretamente `content_transition(_reasoned)`, `pub_approve` e `talent_request_create`, que mantêm todas as regras (capacidade, versão vista, política, autoaprovação, idempotência, auditoria e eventos).
- **Acesso ao portal:** `scripts.read` no cliente (como `my_flags`; 42501 igual para cliente sem acesso e cliente inexistente), depois a flag `client.portal` (55000).
- **Cada bloco verifica a sua capacidade e devolve indisponível com o motivo** (`{available:false, code, reason}`), nunca derruba o portal: `sem_capacidade`, `desligado` (flag do módulo) ou `erro` (o erro vai para o log do servidor com `portal_block_error` e volta com o `sqlstate`; a UI oferece "Tentar de novo").
  - Guiões por aprovar: `scripts.approve`; rejeitar/pedir alterações só com `scripts.reject`; categoria com `learn.rework`.
  - Publicações por aprovar: `calendar.read` + `pub.planning`; lista as planeadas futuras a que falta a parte do cliente ou de qualquer parte (`_pub_missing`), cada uma com `_pub_json` (pode aprovar? porque não?). O código de equipa só lê (aprovar exige sessão individual).
  - Entregas do mês: `scripts.read`; números de `_biz_ops` (a mesma conta de BIZ-01) e do contrato só volumes, plataformas e prazo (`videos_per_month`, `scripts_per_month`, `platforms`, `deadline_days`).
  - Desempenho: `analytics.read` + `perf.center`; resumo por conta (publicações 30 d, índice mediano 72 h, últimos 7 d vs 30 anteriores) e os 3 melhores da semana, de `perf_center`/`perf_levers`.
  - Pedidos: ver com `requests.create` ou `sources.read`; criar só com `requests.create`. Últimos 180 dias, estado em linguagem do cliente (Recebido, Em análise, Aceite, Em produção, Não avança + motivo) e guiões a que deu origem.
- **Nunca sai do servidor:** `amount`, `currency`, `billing_period`, pagamento, renovação e notas do contrato; custos e margens; notas internas de saúde das contas e quem as escreveu; `notas` da triagem; parâmetros internos; outros clientes; flags e permissões.
- **Sem capacidade nova.** Todas as capacidades usadas já existem; `portal.view` seria redundante com `scripts.read` e criaria uma segunda forma de entrar no cliente. Flag nova `client.portal` (fase `owner` por defeito).

## Alternativas rejeitadas
- **RPCs de ação próprias do portal** (`portal_approve_script`, …): duplicariam regras de transição e de política e podiam divergir das do calendário e dos guiões.
- **Reutilizar `biz_overview` para as entregas:** é do espaço da agência (`biz.read`, flag `biz.view`) e mistura campos financeiros; o cliente não deve depender de uma capacidade de agência.
- **Capacidade `portal.view`:** sem ganho de segurança (cada bloco já pede a sua), mais um interruptor a manter na consola.
- **Falhar o portal inteiro quando um bloco falha:** um módulo desligado ou com erro deixaria a equipa sem as aprovações.

## Consequências
Falta para SCALE-08 ficar feito: revisão de media/vídeos pelo cliente (M08 não existe); relatórios para enviar ao cliente (PDF/agendados, peça prevista da agência); notificações ao cliente de itens à espera (PUB-06/FR-17-01); escolher outro mês nas entregas; verificação com conta real (R-15). Os números de entrega herdam os pressupostos de BIZ-01 (prazo = data do guião + dias do contrato; um guião em várias plataformas conta um vídeo), mostrados na página. Rollback: bloco comentado no fim de `20261030160100_w8_portal.sql` (só funções e a flag).
