# ADR-0048 — Pacote de edição automático a partir da sessão gravada (W5-09)

**Data:** 2026-11-05 · **Estado:** aceite · **Requisitos:** PRD EDL-01, ING-03 (parcial), EDL-07; ADR-0046 (documento), ADR-0047 (R2 e jobs de media); AGENTS §2.6, §2.8, §7.

## Contexto

O Numeiro grava a 2026-11-06 uma sessão nova para testar o sistema todo. Até aqui, as versões 1 dos documentos saíram do protótipo local (transcrição, alinhamento, escolha dos takes pela IA, render). Para a equipa usar a app sozinha, isso tem de correr no worker a partir das duas gravações carregadas na Biblioteca.

## Decisão

1. **Job de media `package`** (`edit_package_request`, com `edit.timeline`, R2 ligado, duas versões de vídeo R2 prontas e diferentes, 1 a 40 guiões do cliente, idempotente pela combinação). O job leva o texto dos guiões fixado no momento do pedido.
2. **No worker** (`engine/package.py`, `numeiro-engine`): som da câmara do lado (lapela) → transcrição com tempos por palavra (faster-whisper `small`, CPU, int8) → desvio da câmara da frente pela correlação do envelope do som dos primeiros 10 min (sem som na frente: desvio 0 e aviso) → janela de cada guião por semelhança de texto (blocos de 30 palavras votam no guião mais parecido; alargada 25 s antes e 60 s depois) → unidades numeradas → Claude com o mesmo brief do protótipo (último take limpo de cada hook, corpo uma vez, legendas com o que foi dito) → documento formato 1 por hook, em tempo da câmara do som (`source.time = session`, `source.offsets`).
3. **Gravar**: `media_worker_package_save` (só `engine_worker`, idempotente por job, guião e hook) cria o ativo de vídeo (sem ficheiro, etiquetas `hook_N`, estilo, `pacote`, ligado ao guião), o documento e a versão 1 com origem `ai`. A confiança e os avisos da IA ficam no documento (`ai`). Quem pediu é avisado quando o pacote acaba.
4. **Página "Edição automática"** (`/c/[ws]/edicao-automatica`, flag `edit.studio`): escolher as gravações e os guiões da sessão, ver o progresso real do job, abrir cada vídeo no editor; lista dos documentos com versão, confiança da IA e estado da exportação.
5. Render e imagem do editor aplicam o desvio por câmara.

## Alternativas rejeitadas

- **Transcrição por API externa** (mais rápida): sem conta nem contrato; a local corre no Railway sem custo por minuto.
- **Janelas pelo teleprompter** (tempos de leitura): o relógio do teleprompter não está ligado ao tempo do ficheiro da câmara; o texto é mais robusto.

## Limitações

- Precisão das janelas medida na sessão de teste: 20 de 23 guiões dentro de 5 s; os restantes ficam mais largos (o brief manda ignorar o que não é do guião).
- Enquadramento: âncora fixa (sem deteção de cara); o editor ajusta o zoom.
- Transcrever 2 h de sessão no Railway pode levar 30–60 min; o progresso aparece na página.

## Rollback

Bloco no fim de `supabase/migrations/20261105192728_w5_edit_package.sql`; a página só aparece com `edit.studio`.
