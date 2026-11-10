# ADR-0084 · Biblioteca de estilos da agência e importar para clientes

**Estado:** aceite (2026-11-10) · **Requisitos:** REF-07, REF-08, VAR-02 · **Mudança:** W10-41, W10-42 (migração `w10_biblioteca_estilos`)

## Contexto

O Tomás viu que os estilos do editor (lista no código: S14, S15, S17) não batiam com a página "Estilos de edição" do cliente (catálogo na base: S01 a S12 vazios, S13 a S16), e pediu que os estilos nasçam na agência e se importem para cada cliente, para cada um ter os seus ou partilhar alguns. O PRD já o previa (REF-07, REF-08, CHG-005).

## Decisão

- W10-41: o editor, a Edição automática e o pacote por guião leem o catálogo do cliente: estilos ativos que o motor desenha (`CAP_STYLES`, espelho de `STYLES` em render_doc.py). O estilo atual de um vídeo aparece sempre, marcado com o motivo. S01 a S12 arquivados (não apagados) e S17 criado no catálogo do Numeiro pela app.
- W10-42: tabelas `agency_styles` e `agency_style_versions` por organização, fechadas à API e só por RPC (`agency_style_*`), com `styles.library.manage` (dono e admin da agência). Versões imutáveis. O aspeto guardado vai sem música (a música é da biblioteca de cada cliente).
- Importar (`styles.import` + `styles.manage` no cliente + ver o cliente): copia a versão atual como versão nova do estilo do cliente e fixa a origem (`edit_styles.origin_org/key/version`). O cliente fica nessa versão até alguém carregar em "Atualizar" (pressuposto do REF-08). Nunca escreve por cima de um estilo criado no cliente com a mesma chave: pede outra chave.
- Backfill: os estilos ativos do Numeiro (S13 a S17) entram na biblioteca como v1 e ficam marcados como importados.

## Alternativas recusadas

Estilos só na agência, referidos pelos clientes sem cópia: uma mudança na agência mudava logo os vídeos de todos os clientes, sem revisão. Atualizar todos os clientes automaticamente: idem.

## Consequências

O motor desenha por chave: um estilo importado com outra chave (ex.: S17A) aparece no catálogo mas não no editor até o render ler os parâmetros da ficha (REF-05, passo 3). A equipa do cliente vê só "Da agência · chave vN" no seu catálogo, nunca a biblioteca. Rollback no fim da migração.
