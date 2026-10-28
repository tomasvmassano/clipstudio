# ADR-0006 — Teleprompter: sessões, fila, takes e preferências (W2-05)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD M03 FR-03-01..07, §20 "Teleprompter", FL-03, QA-06, E2E-07; AGENTS §6, §8, §9.

## Contexto

O teleprompter lia a lista de guiões do dia no browser, guardava velocidade, letra e espelho só no `localStorage` e só sabia marcar o guião inteiro como gravado. Não havia fila ordenável, blocos, takes, retoma entre dispositivos nem tratamento de falhas de rede.

## Decisão

1. **Sessão por cliente e dia** (`recording_sessions`), com uma só aberta de cada vez (índice único parcial). Abrir o teleprompter noutro dispositivo entra na mesma sessão. A sessão guarda o último guião, bloco e percentagem lidos para retoma segura. Fechar é explícito; reabrir o dia cria uma sessão nova.
2. **Fila na base** (`recording_session_items`): ao abrir, entram os conteúdos elegíveis do dia e os dos dias anteriores ainda por gravar (transitados), sem rejeitados nem arquivados e, se o cliente o exigir, só aprovados. A ordem, os conteúdos saltados e os blocos saltados ficam na sessão. Reabrir acrescenta os novos no fim, sem perder a ordem.
3. **Blocos** = Hook 1..N, Body, CTA, derivados do conteúdo. Blocos personalizados ficam por fazer: exigem mudar o modelo de conteúdo e as versões.
4. **Takes** (`takes`) por conteúdo e bloco, numerados por bloco e ligados à **versão exata** que estava no ecrã (fotografa a cópia de trabalho se ainda não houver versão igual). Um take escolhido por bloco (índice único parcial). Descartar em vez de apagar; nada se apaga (trigger). Notas até 2000 caracteres.
5. **Marcar takes não muda o estado editorial nem o de produção.** "Gravado" continua a ser `content_production` com confirmação explícita. Ler 80% fica como telemetria `recording.viewed_80` (uma vez por conteúdo e sessão).
6. **Idempotência e offline**: cada take tem um `client_ref` gerado no dispositivo. Sem rede, o take fica no dispositivo e é reenviado; o servidor devolve o mesmo take em vez de criar outro. Erros de permissão ou validação saem da fila de envio e ficam visíveis com opção de descartar.
7. **Preferências por utilizador e dispositivo** (`teleprompter_prefs`, chave `(user_id, device_id)`), validadas no servidor (intervalos, atalhos só para ações conhecidas, tamanho máximo). Também ficam sempre no dispositivo. Com o código de equipa ficam só no dispositivo (o servidor recusa).
8. **Capacidades existentes**: `recording.use` abre, lê, reordena, salta e guarda progresso; `recording.confirm` marca, escolhe e descarta takes e marca gravado. Nenhuma capacidade nova.
9. **Ecrã inteiro e wake lock** pedidos com gesto (botão, duplo toque, tecla). Quando o browser não deixa, a app diz-o em vez de falhar em silêncio.

## Alternativas rejeitadas

- Takes como linhas do histórico do guião: misturava produção com edição e não permitia escolher o melhor por bloco.
- Fila só no browser: não sobrevivia a trocar de dispositivo e não deixava retomar.
- Auto-marcar gravado ao ler 80%: falsos positivos (PRD §20).

## Pendentes

- Anexar ficheiro ao take (FR-03-06) depende do armazenamento de media (W5); escondido até lá.
- Filtros por campanha e responsável (FR-03-01) dependem de campanhas e atribuições (W3).
- Abrir o teleprompter já sem rede (precisa de cache offline da app).
- Blocos personalizados.

## Rollback

Bloco no fim de `20261028211702_w2_teleprompter.sql` (exportar `takes` antes, se já houver takes reais). O código em `main` antes deste PR não usa estas tabelas.
