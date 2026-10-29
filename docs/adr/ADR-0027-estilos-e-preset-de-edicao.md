# ADR-0027 · Catálogo de estilos versionado e preset de edição por cliente

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** VAR-02 (parcial), EDL-01 (parcial), EDL-03 (regra do retângulo seguro)

## Contexto
A edição vai ser automática (decisão do Tomás, 29/10). Antes do motor de render, é preciso saber o que gerar por guião e com que aspeto, por cliente. O PRD dá um ponto de partida para o Numeiro (S01 a S13, só S13 com layout descrito) e o pacote por defeito do EDL-01. AGENTS §1 e §7: a configuração do Numeiro é dado do cliente, nunca regra global; versões aprovadas são imutáveis.

## Decisão
- `edit_styles` (estado e versão atual) e `edit_style_versions` (só de acrescentar). Cada versão guarda nome, layout (`spec`: `canvas` 1080×1920 e camadas `video`, `image`, `attention_video`, `title`, `captions`, `band` com caixa `[x, y, largura, altura]`, cor, contorno, máximo de palavras), nível de transformação, plataformas e notas.
- Validação no servidor (`_edit_spec_problems`), espelhada no browser para avisar enquanto se escreve: tudo dentro de 1080×1920 e texto dentro do retângulo seguro comum x 60-960, y 210-1600 (EDL-03). Ativar exige pelo menos uma camada.
- `edit_presets` (só de acrescentar): lista de 1 a 12 saídas por guião. Saídas `style` fixam `style_version`; editar um estilo não muda pacotes em silêncio, o preset fica marcado `stale` até ser gravado de novo. Não se arquiva nem se passa a rascunho um estilo usado no preset atual.
- Concorrência otimista: gravar estilo ou preset leva a versão que a pessoa estava a ver; se mudou, 40001 com mensagem para recarregar.
- Capacidade nova `styles.manage` (dono, admin, gestor do cliente); ler com `scripts.read` (inclui o código de equipa, só leitura). Auditoria com antes/depois.
- Ponto de partida: semeado na migração só para o `numeiro`. S13 entra ativo com o layout do PRD §41; S01 a S12 entram em rascunho só com o nome, porque o PRD não lhes descreve o layout e não se inventa. Outros clientes podem copiar o ponto de partida (`edit_catalog_init`) uma vez.

## Alternativas rejeitadas
- Estilos globais partilhados entre clientes: viola o isolamento e a regra de preset por workspace.
- Preset a apontar para "a versão atual" de cada estilo: um retoque num estilo mudaria todos os pacotes seguintes sem aprovação.
- Editor visual de arrastar camadas já nesta fase: o layout em JSON com pré-visualização chega para a equipa criativa desenhar os estilos e o motor de render ler; o editor visual fica para quando houver render real para comparar.

## Consequências
O job de pacote (EDL-01) lê o preset e as versões fixadas. Falta: layouts de S01 a S12 (equipa criativa), o render, o QC técnico do vídeo (EDL-03) e a revisão em lote (EDL-02). Rollback no fim da migração.
