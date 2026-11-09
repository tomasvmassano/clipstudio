# ADR-0073 — Original vs. cortado no editor (W10-24)

**Data:** 2026-11-09 · **Estado:** aceite · **Requisitos:** PRD CLIP-06 (o revisor vê original e reordenado lado a lado), EDL-07, EDL-10; AGENTS §6, §9.

## Contexto

O Clip Miner (ADR-0063) grava cada corte como documento de edição formato 1 com o gancho passado para o 0:00 (reordenação de frases inteiras, no máximo 3 trechos). O PRD pede que o revisor veja o original e o reordenado lado a lado. `doc.ai.clip` (numeiro-engine `engine/clips.py`) guarda só IDs de frase (`original`, `parts`, `reordered`, versões do prompt e da rubrica), **sem tempos**: as frases e os seus tempos não ficam no documento.

## Decisão

1. **Sem migração nem mudança no motor.** A comparação calcula-se dos campos que o documento já tem (`src/lib/clip-order.ts`, puro): os segmentos dão a ordem do corte e os tempos no master (tempo da fonte = master, offset 0); as palavras das legendas continuam no documento quando se tira um segmento, por isso marcam o trecho original inteiro e o que ficou de fora com fala. `ai.clip` decide se a vista aparece e dá o resumo ("a IA passou o gancho para o início, N trechos").
2. **Movido = fora da maior subsequência crescente** dos lugares no master, na ordem do corte; em empate fica no lugar a que começa mais tarde, para que seja o gancho puxado para a frente a aparecer como "movido de 2.º para 1.º" e não os trechos que ele empurrou. Trecho usado duas vezes = "repetido".
3. **Cortado = parte do trecho original sem segmento por cima e com fala** (≥ 0,25 s), com os tempos do master das palavras ("cortado: 0:46-0:54") e o texto riscado. Pausas sem fala que o worker aparou entre frases não contam.
4. **UI** (`src/components/edit/clip-order-view.tsx`): secção "Original vs. cortado" na linha do tempo (por baixo do palco) e no passo "Corte" do modo guiado; só leitura (nenhuma permissão nova; o editor já está atrás de `media.read`, da flag `edit.studio` e do RPC `edit_doc_get`). Compara com a versão aberta, incluindo alterações por gravar. Clicar ou Enter num trecho leva a pré-visualização ao início dele na saída; os cortados não têm botão (não estão na saída). Duas colunas a partir de `md`, empilhadas a 390 px. Documento sem trechos ou com tempos inválidos: aviso com a saída (outra versão). Dentro de `WidgetBoundary`.

## Alternativas rejeitadas

- **Guardar os tempos das frases em `ai.clip` (motor + migração):** mais exato para pedaços sem fala, mas obriga a mudar o worker em produção e não serve os cortes que já existem. Fica como melhoria se a verificação com masters reais mostrar falta.
- **Comparar com a versão 1 em vez do master:** mostraria só o que a equipa mudou, não a reordenação da IA, que é o que o CLIP-06 pede para rever.
- **Marcar como movido todo o trecho cujo lugar mudou:** um gancho puxado para a frente marcaria todos os outros como movidos; a subsequência crescente mostra só o essencial.

## Rollback

Reverter o commit: só código de UI e uma função pura; sem dados nem migração.
