# ADR-0067 — Anotações desenhadas no vídeo (W10-15)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD FR-05-03, OPS-07, QA-07; AGENTS §2.1, §2.6, §9.

## Contexto

A revisão de vídeo (W5-04, W5-12) já tinha comentários por momento e, nos vídeos guardados na app, o player com o tempo real. Faltava a parte "anotações" do FR-05-03: apontar no fotograma o que tem de mudar ("este canto", "este texto") sem o descrever por palavras. Nos vídeos da Google Drive isto não é possível: o player embutido não expõe nem o tempo nem o fotograma.

## Decisão

1. **Vetores normalizados, não imagens.** O desenho guarda-se como `{"v": 1, "shapes": [{type, color, width, points}]}` em `media_comments.annotation` (jsonb, coluna nova e opcional). As coordenadas são 0..1 em relação ao **fotograma visível** (o retângulo do vídeo dentro da caixa do player com `object-fit: contain`, sem as faixas pretas), e a espessura é uma fração da largura do fotograma. O mesmo desenho cai no mesmo sítio em qualquer ecrã (telemóvel, iPad, desktop) e em qualquer versão leve do mesmo vídeo.
2. **Validação no servidor, forma canónica.** `public._review_annotation` aceita só `pen` (1 a 500 pontos), `arrow`, `rect`, `ellipse` (2 pontos), cor `#rrggbb`, espessura 0,002 a 0,05, coordenadas numéricas 0..1, no máximo 50 formas e 2000 pontos, pedido até 256 KB; reescreve só as chaves conhecidas, com 4 casas decimais. Os mesmos limites estão em `src/lib/annotation.ts` (a UI não deixa passar deles, mas quem decide é o servidor).
3. **Preso ao comentário e ao momento.** Um desenho exige momento (`t_ms`), não vai em respostas, só existe em vídeos guardados (versão `upload` de vídeo) e, como o texto, não se reescreve depois de gravado (`media_comments_guard`). O texto continua obrigatório: é a alternativa acessível ao desenho e o que aparece nas notificações e na pesquisa.
4. **Assinatura compatível.** `media_review_comment` ganha `p_annotation jsonb default null` no fim, por drop + create na mesma migração: as chamadas antigas (3 a 6 argumentos, por nome ou por posição) continuam iguais, e a app só envia `p_annotation` quando há desenho. Manter as duas versões em paralelo tornaria ambíguas as chamadas de 3 a 6 argumentos.
5. **Mostrar no momento.** Quando a reprodução está a ±0,5 s do momento de um comentário com desenho, ou quando se clica no tempo do comentário ou na marca da linha do tempo (o vídeo pausa nesse fotograma), o desenho aparece numa camada SVG por cima do fotograma, que não apanha cliques (os controlos do vídeo continuam a funcionar). Linha do tempo com uma marca por comentário (QA-07), com cor diferente para os que têm desenho.
6. **Entrada por Pointer Events.** Rato, caneta e toque (iPad) pelo mesmo código, `touch-action: none` só na área de desenho e só enquanto se desenha. Ferramentas, cores, Desfazer, Limpar e Concluir são botões com nome; Ctrl+Z e Esc na área de desenho.

## Alternativas rejeitadas

- **Guardar uma imagem (PNG) do desenho:** pesa mais, não escala sem perda, não se valida (qualquer imagem passaria) e obrigava a storage e URLs assinados para cada comentário.
- **Coordenadas em pixels do ecrã de quem desenhou:** o desenho ficava deslocado noutro tamanho de ecrã ou com as faixas pretas de um vídeo horizontal.
- **Capacidade nova (`review.annotate`):** desenhar é uma forma de comentar; separar criaria um toggle sem caso de uso. Fica em `review.comment`.
- **Desenhar nos vídeos da Drive:** sem tempo nem fotograma, o desenho não teria a que se prender.

## Rollback

Bloco no fim de `20261106065228_w10_anotacoes.sql`: repor as funções de `20261103153227_w5_media_review.sql`, apagar `_review_annotation` e, só depois de exportar os desenhos que se queiram guardar, a coluna. O código anterior não envia `p_annotation` e ignora a chave `annotation` nos comentários.
