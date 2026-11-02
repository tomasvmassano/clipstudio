# ADR-0030 · Blocos personalizados marcados no corpo do guião

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** FR-03-02

## Contexto
O teleprompter tinha Hook 1..N, Body e CTA. O PRD pede também blocos personalizados, com takes e repetição por bloco. O texto do guião é versionado (`content_versions`) e as aprovações ficam presas à versão.

## Decisão
- Um bloco personalizado é uma linha `## Nome` dentro do corpo. O texto antes da primeira marca é o Body; cada marca abre um bloco com chave `x_<nome>` (minúsculas sem acentos, até 24 caracteres; repetidos ganham `_2`, `_3`).
- Como fica no corpo, mudar blocos é editar o texto: cria versão nova e retira a aprovação como qualquer outra edição. Não há coluna nova nem mudança ao versionamento.
- A mesma regra existe no servidor (`_content_block_keys`, `_block_slug`) e no browser (`blocksOf`, `blockSlug`). Takes, marcas de tempo, saltos de bloco e retoma aceitam as chaves novas (`_block_key_ok`); um take num bloco do corpo só é aceite se o bloco existir no texto atual.
- O cartão do guião mostra as marcas como títulos de bloco; a duração estimada não conta as marcas.

## Alternativas rejeitadas
- Lista de blocos num campo próprio versionado: obrigava a mudar `content_versions`, o restauro, o motor e as comparações de versões, para o mesmo resultado.
- Chaves por posição (`custom_1`, `custom_2`): reordenar os blocos trocava os takes de bloco.

## Consequências
O motor gera corpos sem marcas, por isso nada muda nos guiões gerados. Se o motor passar a escrever blocos, usa a mesma sintaxe. Rollback no fim da migração (só enquanto não houver takes com chaves `x_`).
