# ADR-0060 — Clip Miner: cortes de vídeos longos (W10-12)

**Data:** 2026-11-06 · **Estado:** proposto (PR por rever) · **Requisitos:** PRD CLIP-01..07 (§46.3), SCALE-03, VAR-06, EDL-01/02/03/07/11; ADR-0046 (documento), ADR-0047 (R2 e jobs de media), ADR-0048 (pacote), ADR-0052 (revisão em lote); AGENTS §2, §6, §7, §8, §15.

## Contexto

O Tomás pôs o Clip Miner entre as funcionalidades com mais prioridade (§46.5: CLIP-01..07 e CLIP-11 a seguir às tarefas W5). Os clientes têm vídeos longos (podcasts, entrevistas, vlogs) e querem 5-10 cortes verticais por vídeo, revistos por uma pessoa antes de publicar. Já existem: upload por partes para o R2 com verificação e versão leve (ADR-0047), o documento de edição com editor e exportação (ADR-0046, EDL-11), o pacote automático por sessão com transcrição no worker (ADR-0048) e a revisão em lote com QC (ADR-0052).

## Decisão

1. **Job de media `clips`** (mesmo padrão do `package`): `clips_request(ws, versão, n)` com a capacidade nova `clips.mine` (dono, admin, gestor do cliente; outros por grant individual), flags `clips.miner` e `edit.studio`, R2 ligado, versão de vídeo R2 pronta e ativa do próprio cliente, 2 min a 4 h quando a duração é conhecida, 5-10 cortes. Idempotente pela versão e pelo número de cortes; depois de falhar/cancelar pode pedir-se outra vez. O job leva o nome do ficheiro e a chave do master fixados no pedido.
2. **No worker** (`engine/clips.py`, `numeiro-engine`): som do master → transcrição com tempos por palavra (faster-whisper, a mesma de `package.py`) → silêncios medidos no som → frases numeradas `fNNNN` → Claude (prompt `clip_miner.md`, versão `clip-miner-1`, rubrica `clip-rubric-1`) por blocos de 20 min (teto de 12 chamadas) → candidatos com início/fim **em IDs de frase** (o código recusa IDs desconhecidos e ignora qualquer tempo do modelo) → portão da dignidade → ajuste à duração alvo 25-60 s só com frases inteiras e cortes em silêncios/pausas → diversidade (≤ ⌈n/3⌉ por máquina, ≤ 2 por tema, sem sobreposição, ≥ 1 não polémico) → documento formato 1 por corte (uma câmara `front` = o master, gancho no 0:00 com reordenação de frases inteiras em ≤ 3 trechos, título ≤ 8 palavras no hook, 3 hooks alternativos em `ai.alternatives.hook_texts`, cartão de contexto opcional, CTA "Vê o episódio completo" no último 1,5 s, original vs reordenado em `ai.clip`). As máquinas virais vêm do preset do cliente (`clients/<ws>.yaml`), com lista genérica quando não há.
3. **Gravar**: `media_worker_clips_save` (só `engine_worker`, idempotente por job e posição) valida o documento (`_edit_doc_problem`), que só usa o vídeo do pedido, e os metadados (`_clip_meta_problem`: pontuação 0-100, IDs de frase, título ≤ 8 palavras, nunca um corte bloqueado: segunda linha do portão), recusa se o master foi para o lixo, e cria o ativo (etiquetas `corte`, `corte_N`), o documento e a versão 1 `ai`, mais a linha em `media_job_clips` (tabela nova, fechada à API, com os metadados do candidato e o master). Os cortes não têm guião (`content_id` nulo): a identidade canónica do corte é o master + o intervalo de frases.
4. **App**: página "Cortes de vídeos longos" (`/c/[ws]/cortes`, flags `edit.studio` + `clips.miner`): escolher o master, pedir, ver o progresso real, lista dos cortes com pontuação, justificação, máquina, etiquetas, riscos e estado da exportação, abrir no editor, "Exportar todos" (`clips_export`, `edit.export`, pelas regras de `edit_export_request`). `media_review_list` passa a incluir os cortes exportados (sem guião) na revisão em lote. `media_worker_finish` ganha o ramo `clips`; o fim avisa quem pediu.

## Alternativas rejeitadas

- **Reutilizar `media_job_outputs`**: a chave é (job, guião, hook) com hook 1-9 e guião obrigatório; os cortes não têm guião e podem ser 10. Uma tabela irmã guarda também os metadados do candidato.
- **Criar um guião por corte**: inventaria guiões que ninguém escreveu nem aprovou e misturaria o ciclo editorial com o de media (AGENTS §6).
- **Tempos pedidos ao modelo**: o PRD proíbe tempos inventados (CLIP-03); IDs de frase tornam a resposta verificável.
- **Diarização já com pyannote**: modelo pesado, token de terceiros e sem teste com episódios reais; o PRD manda escolher o fornecedor depois do teste (CLIP-02). Fica o gancho `speakers_for` (registo `DIARIZERS`, env `CLIP_DIARIZER`).

## Limitações (UNVERIFIED onde indicado)

- **Oradores (CLIP-02): UNVERIFIED.** Nenhum fornecedor escolhido; as frases vão ao modelo com orador `?` e o relatório do job avisa.
- **Reframe 9:16 com orador ativo (CLIP-07): por fazer.** O render usa o corte ao centro do plano (âncora fixa de `render_doc.geo`); cada documento leva o aviso em `ai.flags` e a página diz isso. Fontes multi-câmara ainda não são usadas.
- Legendas: as palavras da transcrição como saíram (sem correção pelo modelo); o editor corrige.
- Portão da dignidade: decisão do modelo + regras em código (inimigo do tipo grupo, frases que essencializam um grupo) + verificação no servidor. A rede em código é mínima e não substitui a revisão humana. A regra final para afirmações sobre terceiros continua pendente (§46.5): pessoas identificadas só ficam assinaladas.
- Piloto (CLIP-11) e tempos reais (≤ 30 min por hora de fonte) por medir com vídeos reais.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_clip_miner.sql`; a página e as RPCs param com a flag `clips.miner` desligada. No motor, tirar `clips` de `MEDIA_KINDS` (ou reverter o PR) deixa os jobs na fila.
