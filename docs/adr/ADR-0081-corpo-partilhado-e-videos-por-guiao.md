# ADR-0081 · Corpo partilhado entre hooks e vídeos por guião

**Estado:** aceite (2026-11-10) · **Requisitos:** EDL-14, EDL-15 (CHG-011) · **Mudança:** W10-33

## Contexto

Cada hook de um guião é uma variante com o seu documento de edição (EDL-07). Os erros do primeiro pacote real estavam quase todos nos corpos, e com três hooks o Tomás tinha de corrigir o mesmo corpo três vezes. A escolha dos vídeos era uma lista de nomes.

## Decisão

- Corpo = cortes que não são hook, e o que toca esses trechos da gravação (legendas, câmaras, visuais, volumes; efeitos que lá começam). `applyBody(src, dst)` (puro, `src/lib/body-share.ts`, testado) põe o corpo de src em dst e mantém os cortes de hook, o texto do hook, o aspeto e a música de dst. Como tudo está em tempo da fonte e os hooks são takes diferentes, não há mistura.
- Ao gravar no editor (modo completo), por defeito o corpo é aplicado aos outros hooks do guião: para cada um lê-se a versão atual e grava-se uma versão nova com `edit_doc_save` e essa versão como base. Mesmas regras, auditoria e controlo de versões; quem gravou entretanto fica de fora com aviso. Igual = não grava. Caixa para não aplicar (lembrada no dispositivo).
- `edit_board` (só leitura) agrupa os vídeos por guião com hook, duração, versão, exportação, assinatura dos cortes do corpo e o primeiro corte; a página Edição automática mostra-os com uma imagem (a versão leve da câmara no primeiro corte) e o editor mostra separadores entre hooks e se o corpo está igual.

## Alternativas rejeitadas

- Um documento de corpo partilhado referido pelas variantes: mudava o formato do documento, o render e o QC; a cópia em versões novas mantém tudo imutável e auditável.
- Aplicar no servidor numa só transação: duplicava em SQL a lógica do editor; as gravações por variante já trazem validação, modo guiado e conflitos.

## Consequências

Cada gravação cria até N versões (uma por hook). No modo guiado só há separadores (aplicar o corpo exige o modo completo). A assinatura no quadro compara só os cortes; o editor compara o corpo inteiro ao aplicar.
