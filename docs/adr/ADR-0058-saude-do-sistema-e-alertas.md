# ADR-0058 — Saúde do sistema e alertas (W10-01)

**Data:** 2026-11-06 · **Estado:** proposta (PR aberto) · **Requisitos:** PRD FR-17-15 (e FR-17-14); AGENTS §2.8, §8, §10.
**Nota:** número escolhido com outras tarefas em paralelo; pode ser renumerado no merge.

## Contexto

FR-17-15 pedia "alertas e dashboard de saúde". Havia correlação (`correlation_id`, `agent_job_attempts`, `run_id`) e o estado do worker por cliente na página dos agentes, mas ninguém era avisado quando um worker parava com trabalho na fila, nem havia uma vista única das filas `agent_jobs` e `media_jobs`. O worker dos agentes e o de media escrevem ambos em `agent_workers` (`worker_claim` e `media_worker_claim`).

## Decisão

1. **Capacidade nova `ops.health` (org, risco M): dono e admin da agência.** PRD §3: "consultar dashboard global de agência: owner sim; admin sim, com escopo". O dono vê todos os clientes ativos da organização; o admin só os clientes a que está atribuído como staff. Dentro de cada cliente, a parte dos agentes exige `agents.read` e a de media `media.read` (uma negação explícita retira a parte). Gestor e membro da agência, equipa do cliente e código de equipa: 42501. Os workers (infraestrutura da agência, sem dados de cliente) aparecem a todos os que têm `ops.health`. Sem flag de disponibilidade: só leitura, sem efeitos.
2. **Uma RPC de leitura (`ops_health`)** com workers, filas (prontos, agendados, mais antigo pronto, a correr, lease expirada, tipos sem worker recente), trabalhos a correr com o último heartbeat, falhas `failed`/`dead` em 24 h e 7 dias, contagens por cliente e os alertas enviados. As contagens globais somam só os clientes visíveis (CAP-08: nenhuma contagem revela outros clientes).
3. **Erros sem segredos (`_ops_redact`)**: tokens Bearer/JWT, chaves `sk-…`, `token=`/`apikey=`/`password=`…, palavras-passe em URLs e emails são substituídos antes de sair da base (aceitação de FR-17-15). A UI repete a limpeza (`redactSecrets`) como segunda linha.
4. **Alertas por pg_cron (`ops_health_tick`, `*/5 * * * *`)**, o mesmo mecanismo de `agent-schedule-tick`:
   - *worker_down*: trabalho pronto de um tipo para o qual nenhum worker foi visto nos últimos 10 minutos, por cliente e origem. Chave do incidente = origem + cliente + último contacto de um worker capaz (ou "nunca"): não repete enquanto o worker estiver em baixo; se voltar e cair, é incidente novo.
   - *job_dead*: trabalho que foi para `dead` nas últimas 24 h (inclui os que morrem por lease expirada, que não passam por `worker_finish`). Quem já recebeu `automation_error` desse trabalho não recebe outra vez.
   - Idempotência: `ops_health_alerts.dedupe_key` única + `_notify` com a mesma chave; lock consultivo para dois ticks em simultâneo. A notificação é do tipo novo `system_health` (obrigatória, só "na app"), para os donos da agência, e cai em "Alerta" na caixa.
5. **Não muda as funções dos workers.** A recuperação de leases continua no claim; o painel só mostra "sem sinal".

## Alternativas rejeitadas

- Alertar a partir do worker ou da app (Vercel): se o worker morre não avisa ninguém, e a app só corre com alguém a abrir uma página. pg_cron corre na própria base.
- Reutilizar `automation_error`: o tipo diz "execução dos agentes falhou" e vai para quem configura os agentes do cliente; os alertas de infraestrutura são da agência.
- Um alerta por tick enquanto o problema durar: ruído; um por incidente com o estado ao vivo no painel.
- Serviço externo de monitorização (Sentry, Grafana): fica possível mais tarde; não há conta nem segredo para isso hoje.

## Consequências e limites

- [UNVERIFIED] O código do worker não está neste repositório. Se o mesmo processo pedir trabalho de agentes e de media com o mesmo id, `worker_claim` reescreve `kinds` só com os tipos dos agentes até ao próximo `media_worker_claim`; um tick nessa janela pode ver a fila de media "sem worker" e avisar. O risco desaparece com ids diferentes por fila ou alargando `worker_claim` a juntar os tipos (como já faz `media_worker_claim`).
- O check de `notifications.kind` é alargado a partir da definição na base. Uma migração posterior que reescreva a lista à mão sem `system_health` falha se já houver notificações desse tipo: acrescentar sempre a partir da definição atual.
- Email/push dos alertas: o canal só existe "na app" (FR-13-01 adiado).

## Rollback

Bloco no fim de `supabase/migrations/*_w10_saude.sql`: desagendar, apagar funções, repor `_ops_category` e o check, apagar tabelas e a capacidade.
