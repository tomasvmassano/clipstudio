# ADR-0047 — Modo guiado do editor de vídeo (W5-07)

**Data:** 2026-11-05 · **Estado:** aceite · **Requisitos:** PRD EDL-10 (parcial), CHG-007; AGENTS §2.1, §2.6, §5, §15.

## Contexto

O cliente (e o revisor/colaborador da agência) tem `edit.guided`, não `edit.timeline`. Até aqui `edit_doc_save` aceitava qualquer documento a quem tivesse uma das duas: a diferença entre modos era só da UI. EDL-10 pede uma vista simples sobre o mesmo documento e o servidor tem de ser a autoridade (AGENTS §2.1).

## Decisão

1. **Mesmo documento, mesma RPC.** `edit_doc_save` continua a ser o único caminho de gravação. Sem `edit.timeline`, compara o documento novo com a versão base (`_edit_guided_problem`) e recusa com `42501 modo_guiado: <motivo>` o que não for do modo guiado. Origem só `user` (nem `ai`, `import` ou `agent`). A auditoria regista `mode: guiado|completo`.
2. **O que o modo guiado pode mudar:** texto das palavras (os tempos ficam; não se tiram nem juntam palavras), texto do hook (a caixa não), tirar cortes ou repor cortes que já existiram em versões deste documento (objeto igual, sem aparar, criar ou reordenar os que ficam), trocar ou tirar a música (só um áudio ativo da biblioteca do mesmo cliente; volume por trecho só se limpa ao tirar a música), juntar notas com o nome de quem grava e marcar notas como feitas (não se apagam nem reescrevem). Tudo o resto (visuais, câmaras, layout `style`, aspeto `look`, volumes por trecho) tem de ficar igual.
3. **`edit_doc_get` diz o que o modo guiado precisa:** `ai_choice` (a última versão `import`/`ai`: hook, música, cortes), `cut_pool` (cortes de versões anteriores que não estão nesta, com o corte que os precedia), `guiao.hooks` (os hooks escritos no guião, como alternativas) e `can.styles`.
4. **UI** `GuidedEditor` (`src/components/edit/guided-editor.tsx`): passos Estilo → Corte → Hook → Visual e música → Legendas → Exportar, cada um com a escolha da IA e as alternativas que existem de facto, e uma nota no momento do cursor. Quem só tem `edit.guided` abre sempre esta vista; quem tem a linha do tempo pode abri-la com `?modo=guiado`. `guidedProblem` (espelho em `edit-doc.ts`) avisa antes de gravar; o servidor decide.
5. **Palco partilhado** `EditorStage`: o mesmo desenho no modo completo e no guiado, com uma camada `media` por baixo para o `<video>` do proxy (EDL-08) sem mudar o resto.
6. **Aspeto opcional `look`** no documento (cores, tamanho e centro vertical das legendas e do hook, em px de 1080×1920, dentro do retângulo seguro y 260-1550), validado por `_edit_look_problem`. Entra aqui porque o modo guiado o tem de proteger; é preenchido pelos estilos guardados (EDL-13, ADR-0048).

## Alternativas rejeitadas

- **RPC própria por operações** (`corrigir palavra`, `tirar corte`…): mais fácil de validar, mas duplicava a gravação, o conflito de versões e a idempotência, e deixava `edit_doc_save` aberto ao colaborador até um contract posterior.
- **Marcar cortes como "desligados" no documento** em vez de os tirar: mudava o formato 1 e obrigava o render e a linha do tempo a saber de cortes fantasma. Repor a partir das versões anteriores mantém o formato.
- **Só esconder a linha do tempo na UI:** não protege nada (AGENTS §2.1).

## Limitações

- As 2-3 alternativas por secção da IA só existem quando o job do pacote (EDL-01) as gerar; hoje há a escolha da IA (v1), os hooks do guião e os cortes tirados. Estilo e Visual mostram o que existe e pedem nota para o resto.
- Aperto de regra: quem só tem `edit.guided` deixa de gravar mudanças da linha do tempo. Em produção a flag `edit.studio` está no estágio `owner`, por isso ninguém nessa situação chega hoje ao editor.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w5_07a_editor_guided.sql` (voltar às funções do W5-06); a UI guiada cai com o código.
