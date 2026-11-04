# ADR-0046 — Documento de edição versionado e linha do tempo (W5-06)

**Data:** 2026-11-04 · **Estado:** aceite · **Requisitos:** PRD EDL-07, EDL-09 (parcial), EDL-08 e EDL-11 (dependem de R2 e do worker); CHG-007; AGENTS §2.6, §4, §8.

## Decisão

1. **A edição é um documento JSON por ativo da biblioteca** (`edit_documents`, um por vídeo) com versões imutáveis (`edit_versions`: número, base, origem `import|ai|user|agent`, nota, autor). Gravar exige a versão atual como base: se outra pessoa gravou entretanto, `conflito_versao_edicao` (40001) e nada se perde. Repetir a mesma gravação não cria versão.
2. **Tudo em tempo da fonte.** Segmentos `[in, out]` por ordem (com secção hook/corpo), palavras das legendas, câmaras e visuais no tempo da gravação sincronizada (o "tempo virtual" das janelas extraídas da sessão, guardadas em `source.windows`). O tempo de saída deriva dos segmentos (`src/lib/edit-doc.ts`), por isso aparar, dividir, tirar ou reordenar um corte reflui sozinho as legendas e as câmaras desse trecho.
3. **O servidor valida a forma mínima** (`_edit_doc_problem`: formato 1, 1-400 segmentos com ≥ 0,1 s, palavras válidas, hook ≤ 200, ≤ 1,5 MB); a app valida o mesmo antes de gravar.
4. **Capacidades** `edit.timeline` (dono, admin, gestor), `edit.guided` (também revisor e colaborador), `edit.export` (dono, admin, gestor; só usada quando houver export). Ler o editor exige `media.read`, a biblioteca e a flag `edit.studio` (dono por omissão) e uma das duas de edição: o leitor não abre. Importar ou gravar como IA só com `edit.timeline`.
5. **Versão 1 a partir dos planos do render.** Os 68 vídeos do Numeiro já têm `plan.json` (palavras, cortes, câmaras, caixa do título): convertidos para o formato 1 e gravados como `import`, com verificação de que as palavras caem no mesmo tempo (erro máximo 2 ms).
6. **UI** `/c/[ws]/editor?asset=`: palco 9:16, inspetor (hook, corte, palavra, visual, notas), linha do tempo com faixas Secções, Cortes, Câmara, Legendas, Visuais, Som e Notas, zoom, cursor, desfazer/refazer e atalhos. Arrastar as pontas de cortes e visuais apara; arrastar uma palavra ou um visual move-o (o arrasto entra no histórico só ao largar). Visuais e música vêm da biblioteca de media do cliente (`asset` = id do ativo); volume da música geral e por corte. Notas por momento (N) ficam no documento, em tempo da fonte, com autor e estado: são a entrada do agente (EDL-12). Abre a partir da revisão do vídeo ("Abrir no editor").

## Limitações (assumidas, à vista na UI)

- **Sem imagem na pré-visualização** até haver proxies em R2 (EDL-08): o palco mostra cortes, câmara, legendas e hook no tempo certo; o vídeo exportado abre na Drive.
- **Sem exportar** (EDL-11) até o worker estar alojado: o botão está desativado com o motivo; as versões gravadas ficam prontas.
- Visuais e música começam vazios nos 68 vídeos (o render atual não os usa); só se veem no export quando o worker os souber renderizar.
- O palco mostra o nome do visual, não a imagem dele, até haver proxies.

## Rollback

Bloco no fim de `supabase/migrations/20261104180102_w5_editor_doc.sql`; a flag `edit.studio` desliga a UI.
