# ADR-0060 — Teleprompter: coluna pela distância, linha de foco e modo frase (W10-11)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD §46.1 GAZE-01, GAZE-02 (CHG-008); estende FR-03-03 e FR-03-05; AGENTS §6 e §9.

## Decisão

1. **Geometria no cliente, numa biblioteca pura** (`src/lib/gaze.ts`, testada em `tests/gaze.test.mts`). Largura máxima da coluna = 2·d·tan(3°) (alvo ±3°, ≈10,5 cm a 1 m, ≈26 cm a 2,5 m); ângulo mostrado = atan(largura / 2d). Conversão cm → px CSS pela diagonal do ecrã físico e pela resolução em píxeis do dispositivo (`screen.width/height × devicePixelRatio`), dividida pelo `devicePixelRatio`. A coluna nunca passa a largura disponível na janela.
2. **O ângulo vem da linha medida, não da definição.** A barra do topo mostra o meio ângulo da linha mais larga realmente desenhada (coluna, ou a linha mais larga no modo frase; palavra maior do que a coluna também conta). Acima de ±3° fica âmbar; acima de ±4,5° (teto) fica um aviso vermelho com a correção.
3. **Sem diagonal, não se adivinha.** Sem tamanho do ecrã a coluna fica como estava (até 1100 px) e a app pede a diagonal. Não se usa a polegada CSS (96 px) como estimativa: num iPad engana em cerca de 45%.
4. **Linha de foco configurável** (`focus_pct`, 5 a 60 %, 20 % por defeito: a lente fica em cima). É a mesma linha que decide o bloco atual, a retoma por bloco e o salto entre blocos; fica dentro do espelho, por isso continua no sítio certo com espelho vertical.
5. **Modo frase como função pura** (`phraseLines`): partição ótima (programação dinâmica) de cada parágrafo em linhas de 2 a 4 palavras, com custo baixo para quebrar no fim de frase, na vírgula e antes de conjunções, e custo alto para fechar a linha num artigo ou preposição. Aplica-se por bloco: Hook, Body, CTA e blocos personalizados mantêm a identidade, os takes e a retoma.
6. **Preferências por utilizador e dispositivo, no mecanismo que já existe** (`teleprompter_prefs`, `tp_prefs_get/set`). Cinco chaves novas no jsonb (`distance_m`, `screen_in`, `column_fit`, `focus_pct`, `phrase_mode`), validadas em `_tp_prefs_clean` (migração aditiva `PENDING_w10_teleprompter_olhar.sql`). Se o servidor ainda não as conhecer, o cliente guarda as restantes e avisa que estas ficam só no dispositivo.

## Alternativas rejeitadas

- Coluna em caracteres por linha: não depende da distância nem do tamanho do ecrã, que é o que decide o ângulo.
- Pedir à pessoa que meça o ecrã com uma régua em vez da diagonal: mais passos; fica como verificação opcional (a app mostra os cm que a coluna deve medir).
- Tabela nova para as definições do olhar: as preferências já são por utilizador e dispositivo; uma tabela nova duplicava RLS e sincronização.
- Modo frase guardado no servidor (texto já partido): perde-se ao editar o guião e mistura apresentação com conteúdo.

## Consequências

- Com zoom do browser o `devicePixelRatio` muda e a coluna acompanha; num monitor externo a diagonal é a desse monitor (uma por dispositivo).
- O ritmo do auto-scroll mantém-se em px por segundo; no modo frase o texto fica mais alto, por isso a mesma velocidade lê menos palavras por segundo.

## Rollback

Bloco no fim de `PENDING_w10_teleprompter_olhar.sql` (repõe `_tp_prefs_clean`; as chaves já guardadas ficam no jsonb e o código anterior ignora-as). Reverter o PR volta à coluna de 1100 px e à linha a 34 %.
