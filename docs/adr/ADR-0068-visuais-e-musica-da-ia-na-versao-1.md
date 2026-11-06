# ADR-0068 — Visuais e música da IA na versão 1 do pacote (W10-18)

**Data:** 2026-11-06 · **Estado:** proposto (à espera da migração e do numeiro-engine) · **Requisitos:** PRD EDL-07, EDL-01, EDL-04, EDL-11, EDL-13, VAR-02, VAR-03 (reutilização), R-17; AGENTS §2, §7, §8.

## Contexto

O job `package` (ADR-0048, ADR-0055) escreve a versão 1 de cada documento com cortes, legendas, hook, aspeto e a música do estilo guardado, mas sem visuais (imagem, frase-persona, vídeo de atenção) e sem música quando o estilo não a tem. O preset de edição do cliente (`edit_presets`, VAR-02/EDL-01) já diz que saídas quer: master por hook, `split_image_persona`, `split_attention`, estilos. A IA não pode inventar nem descarregar media: só pode usar o que o cliente tem e autorizou.

## Decisão

1. **O servidor escolhe o que a IA pode usar.** Com a flag `edit.ai_visuals` (por cliente, `owner`), `edit_package_request` junta `input.fill` ao job, montado por `_edit_package_fill` (fechada à API):
   - `library`: só ativos do próprio cliente, ativos, com a versão atual pronta, carregada (`upload`) no R2, e com a etiqueta que os autoriza para a IA: `ia-imagem` (imagens), `ia-atencao` (vídeos de atenção, EDL-04: loops próprios ou licenciados), `ia-musica` (áudio). A etiqueta é a declaração de quem gere a Biblioteca de que o ficheiro é do cliente ou está licenciado; sem etiqueta a IA não o vê. Até 60 de cada, os mais recentes.
   - `persona`: a lista de frases-persona em vigor (R-17, ADR-0053), só o texto e o nome de quem a frase envolve.
   - `recipes`: a receita de cada hook vem do preset do cliente: o 1.º hook é o master, os seguintes seguem as saídas `split_image_persona` → `imagem_frase` e `split_attention` → `atencao_frase`, pela ordem. Sem preset: o ponto de partida do EDL-01 (o mesmo de `_edit_seed`). Nada fica fixo no motor.
   A chave de idempotência ganha `:ia1`; o audit leva as contagens, a versão das frases e do preset.
2. **O motor (numeiro-engine `package_visuals`) só escolhe dentro disso:**
   - `imagem_frase`: imagem cujo título/etiquetas têm palavras do guião (sem palavra em comum, fica vazio: a imagem é a prova, VAR-03), no início do corpo durante 3 s, caixa `[108, 500, 864, 560]`; no máximo 2 vídeos do mesmo pacote com a mesma imagem. Frase-persona da lista (a com mais palavras do guião, senão por rotação), tal e qual, na faixa do título `[120, 230, 840, 220]` (livre depois do hook, dentro do retângulo seguro).
   - `atencao_frase`: vídeo de atenção (o menos usado no pacote) na metade de baixo `[0, 960, 1080, 960]` em todos os cortes do corpo, e uma frase diferente da do outro vídeo do mesmo guião.
   - Música: a do estilo guardado se houver; senão uma `ia-musica` (rotação por guião, -18 dB); senão vazio.
   - Tudo o que escolhe vai para `doc.ai.visuals` (`{version, recipe, picks: [{slot, overlays, asset, label, why}], empty: [{slot, why}], persona_version, phrase_options}`); o que fica vazio leva o motivo.
3. **Posição por visual (levanta o limite "caixa fixa" do EDL-11).** `overlays[].box = [x, y, w, h]` em 1080×1920, opcional. O render já desenhava gráficos e texto na caixa; passa a desenhar o B-roll com caixa a cobrir só essa caixa (sem caixa: ecrã inteiro, como antes). O palco do editor desenha cada visual na sua caixa; no inspetor do visual, "Posição" com posições prontas (atrás da flag, ou sempre que o visual já tem caixa).
4. **Editor.** Painel "Escolhas da IA na versão 1": cada escolha com o porquê e o estado (em uso, trocada por ti, tirada), "Trocar por…" (imagem e vídeo pela Biblioteca, as etiquetadas primeiro; frase só pela lista aprovada que a IA recebeu; música pela Biblioteca), "Tirar", "Ver aos"; os lugares vazios com o motivo. No modo guiado só mostra (os visuais não mudam no modo guiado, ADR-0049). Lê `doc.ai.visuals` do próprio documento: nenhuma edição o altera (o modo guiado não deixa mudar `ai`; a linha do tempo não lhe toca).
5. **`_edit_doc_problem` fica igual** e continua a ser o portão: aceita `box` e `ai.visuals` porque não valida visuais; documentos antigos validam e desenham como antes.

## Alternativas rejeitadas

- **Visuais do Supabase Storage ou por link (resto do limite do EDL-11):** não são precisos para a IA (só usa R2) e o link é inseguro (direitos por verificar, o worker iria buscar URLs arbitrários). Ficam fora; o export continua a deixá-los de fora com aviso.
- **Validar `box` no servidor:** obrigava a reescrever `_edit_doc_problem`; um documento antigo com uma caixa estranha deixava de gravar. O render já tolera e recorta caixas inválidas (cai na caixa de sempre).
- **Escolha dos visuais pelo Claude na mesma chamada:** mais custo e respostas por validar; a escolha por palavras em comum é determinística, testável e explica-se numa frase.
- **Usar todas as imagens da Biblioteca:** sem sinal de direitos; a etiqueta explícita é a autorização.
- **Gravar o porquê em cada visual:** o editor muda os visuais; o porquê fica em `doc.ai`, imutável.

## Limitações

- O vídeo da pessoa não se desloca: na receita da imagem a imagem fica por cima, a meio; no ecrã dividido com o vídeo de atenção a metade de baixo tapa o corpo da pessoa (a cara fica em cima). Um layout de ecrã dividido "a sério" é um estilo do catálogo (VAR-02).
- O pacote continua a fazer um documento por hook; as saídas `split_*` do preset aplicam-se aos hooks 2 e 3 em vez de criar vídeos novos.
- Escolha por palavras: sem etiquetas boas nas imagens, fica vazio (e diz porquê).

## Ordem de deploy

1. Dono aplica a migração (`20261106131703_w10_v1_visuais_musica.sql`): sem efeito com a flag desligada; com ela ligada, um worker antigo ignora `fill` (v1 como hoje).
2. Merge do numeiro-engine (`edl07-visuais-musica`) → Railway faz o deploy do worker.
3. Merge desta PR (UI).
4. Ligar `edit.ai_visuals` para o Numeiro (fase `owner` primeiro), etiquetar na Biblioteca as imagens, loops e músicas autorizadas, pedir um pacote.

## Rollback

Desligar a flag (o pedido volta a ser o de hoje). Bloco no fim da migração: repor `edit_package_request` de `20261106060134_w10_pacote_estilo_alternativas.sql`, drop de `_edit_package_fill`, apagar a flag. Versões já gravadas com visuais ficam válidas.
