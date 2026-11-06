# ADR-0065 · Janelas por guião pelas marcas do teleprompter no pacote automático

**Estado:** proposto · **Data:** 2026-11-06 · **Requisitos:** ING-03, EDL-01 ("usar as marcas de gravação (ING-03) para afinar as janelas"), EDL-08; STU-03 (refazer o corte a partir das marcas e da gravação contínua)

## Contexto
O Numeiro grava um ficheiro longo por câmara por sessão. O pacote automático (W5-09, ADR-0048) encontra a janela de cada guião só pela transcrição (`script_windows`: blocos de ~30 palavras votam no guião mais parecido, a corrida mais comprida ganha, +25 s/+60 s de folga). Funciona (20/23 janelas a menos de 5 s na sessão de teste) mas falha quando dois guiões têm vocabulário parecido, quando há ensaios soltos e quando um guião é repetido muito mais tarde. O teleprompter já grava, por guião e bloco, `play`/`block`/`pause`/`take`/`recorded` com o relógio do dispositivo e do servidor (`recording_marks`, W5-01, ADR-0026), mas nada as liga à gravação: o relógio das marcas é UTC do iPad, o do ficheiro começa em 0 no arranque da câmara, e a hora de criação no ficheiro (`creation_time`) é muitas vezes a hora local escrita como UTC, ou a hora do fim.

Produção está a ser usada para gravar; nada pode mudar até o dono aplicar a migração e o worker novo ser publicado.

## Decisão
**App (migração `PENDING_w10_marcas_janelas.sql`, aditiva):**
- Flag `edit.package_marks` (por cliente, fase inicial `owner`). Avaliada para **quem pede** o pacote (`_flag_on_for(..., created_by)`), não para quem vê.
- `_package_marks(ws, guiões)` (interna, sem EXECUTE para `anon`/`authenticated`): escolhe a sessão deste cliente com mais destes guiões lidos (empate: a mais recente) e devolve por guião as leituras de cada bloco (como `recording_timeline`: de `play`/`block` até à marca seguinte do mesmo dispositivo, até 300), os takes e o último "Gravaste?" (`recorded` só se não foi desfeito); por dispositivo, o desvio mínimo `server_at - client_at` e o número de marcas. Tudo filtrado por `workspace_id`.
- Trigger `BEFORE INSERT` em `media_jobs` (só `kind = 'package'`, só se o input ainda não tem `marks`): junta `input.marks`. Erro ao juntar = `input.marks.error`, nunca falha o pedido. `edit_package_request` não muda (assinatura, chave de idempotência, auditoria iguais).

**Worker (numeiro-engine `ing03-marcas-janelas`, `engine/marks.py`):** só quando o job traz `input.marks`:
1. Corrige o relógio de cada dispositivo pelo do servidor (desvio mínimo, só com 3+ marcas e até 10 min; mais do que isso é envio offline).
2. Junta as leituras de cada guião em **passagens** (mais de 120 s entre leituras = outra passagem, isto é, retake noutra altura); o "Gravaste? sim" até 60 s depois fecha a passagem.
3. Resolve o relógio `t_ficheiro = t_marca + d (+ r·(t - t0))`. **A transcrição manda:** cada guião com corrida na transcrição dá uma âncora `d = início da corrida - início de uma passagem`; ganha o `d` com mais guiões a menos de 25 s (maioria obrigatória, 2+ guiões). A hora do ficheiro (`com.apple.quicktime.creationdate` com fuso, ou `creation_time`; testa início e fim) só confirma (a menos de 120 s) ou, sem âncoras, serve se todas as passagens couberem na gravação. Deriva só com 4+ âncoras espalhadas por 10+ min, até 0,2%, e se explicar pelo menos metade da variância (as âncoras têm ~10 s de ruído).
4. Janela de cada guião = as suas passagens no tempo do ficheiro, -6 s/+12 s, alargadas pela corrida da transcrição que lhes toca (até 20 s de cada lado). Cada leitura fica identificada (hook 1/2/3, corpo, CTA, n.ª leitura, passagem) e vai para a IA como etiqueta `[teleprompter: hook 2 · 2.ª leitura · passagem 2]` junto das unidades da transcrição, com uma nota a dizer que a fala manda.
5. **Volta ao caminho só pela transcrição** (a janela de hoje, igual): por guião sem leituras (`sem_marcas`) ou com leituras fora do ficheiro (`fora_do_ficheiro`); para o pacote inteiro quando não há sessão (`sem_sessao`), as marcas não vieram (`pedido_sem_marcas`, `erro_marcas`), não há referência para o relógio (`relogio_sem_referencia`) ou não há maioria (`marcas_inconsistentes`). Um guião com marcas que a transcrição não confirma (`agree: false`) usa as marcas (o relógio global foi validado pelos outros) e fica avisado.
6. `result.windows = {clock: {ok, method, reason, d, r, anchors, support, session, file_start}, items: {guião: {source, reason, windows, passes, takes, agree, hooks}}}`; cada documento v1 leva `doc.ai.window` (origem da sua janela). `source.window` continua o intervalo total (o que o editor e o render já usam); `source.windows` continua `null`.

**UI:** na Edição automática, com a flag ligada para quem vê, cada pacote acabado tem "Janelas por guião: N de M pelas marcas do teleprompter" (um `<details>`, abre pelo teclado) com a linha do relógio e, por guião, a origem, passagens, hooks, takes, aviso e as janelas em m:ss. Pacote de um worker anterior: diz que não há registo.

## Ordem de deploy
1. App: aplicar a migração (o worker atual ignora `input.marks`; com a flag na fase `owner` só os pacotes pedidos pelo dono levam marcas). Pode ir antes do merge da PR da app (aditiva, ADR-0004).
2. Worker: merge e deploy do numeiro-engine. Sem `input.marks` o documento e a entrada da IA ficam byte a byte iguais aos de hoje (testado); o resultado ganha `windows` (só origem "transcrição").
3. App: merge da PR (mostra a origem das janelas com a flag).
Desligar sem rollback: flag `edit.package_marks` em `off` no cliente.

## Alternativas rejeitadas
- **Confiar na hora de criação do ficheiro:** as câmaras gravam hora local como UTC (desvios de horas certas) ou a hora do fim; ficou como confirmação e último recurso.
- **Sincronizar por um "clap" ou sinal sonoro do teleprompter:** obriga a mudar o fluxo do estúdio e o teleprompter não toca som na gravação; as âncoras da transcrição dão o mesmo sem mudar nada.
- **Reescrever `edit_package_request` para pedir a sessão:** muda a função que outras tarefas (W10-07) acabaram de mexer e a UI do pedido; o trigger acrescenta sem tocar no contrato. A sessão é escolhida pelos guiões pedidos.
- **Marcas como janela final, sem transcrição:** a pessoa começa a falar antes de carregar em play e acaba depois da última marca; as marcas dão o sítio, a transcrição afina.
- **Uma janela única (do início da 1.ª à última passagem):** com um retake uma hora depois apanhava todos os guiões do meio; as passagens viram janelas separadas e as unidades seguem numeradas.

## Consequências e limites
- O job leva as marcas do momento do pedido. Pedir outra vez o mesmo pacote devolve o mesmo job (mesma chave); marcas novas só entram num pedido novo (job falhado ou outro estilo/guiões).
- Uma sessão por pacote: guiões lidos noutra sessão vão pela transcrição (`sem_marcas`).
- Relógio global para a gravação (um ficheiro da câmara do lado; a da frente segue pelo desvio do som de sempre). Dois dispositivos com relógios diferentes são corrigidos pelo servidor, não entre si.
- A hora do ficheiro nunca vem do browser: o worker lê-a do contentor no R2.
- **UNVERIFIED** na sessão real de 2026-11-06 até haver a gravação no R2 e o pacote ser pedido com a flag.
