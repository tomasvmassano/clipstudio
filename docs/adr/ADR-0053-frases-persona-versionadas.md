# ADR-0053 — Lista de frases-persona versionada por cliente (W5-14)

**Data:** 2026-11-06 · **Estado:** aceite · **Requisitos:** PRD R-17 (CHG-003), VAR-03, VAR-04, REF-03; AGENTS §7.

## Decisão

1. **Uma lista por cliente, versionada.** `persona_lists` guarda cada gravação como versão nova e imutável (trigger recusa update/delete); a em vigor é a mais alta. Gravar exige `persona.manage` (workspace_owner, workspace_admin, e o dono da agência pelo acesso global) e sessão individual; `p_expected` protege contra duas pessoas a gravar ao mesmo tempo (40001). Auditoria com as frases que entraram e saíram.
2. **Terceiros com consentimento.** Uma frase que envolve outra pessoa (ex.: parceira) só grava com quem deu o consentimento e em que dia (R-17). O motor só recebe o nome; o registo do consentimento fica na app.
3. **Os agentes só usam a lista.** `worker_claim` devolve `persona {version, phrases}`; o motor junta uma regra ao `guard` de todos os agentes: só estas frases, tal e qual; lista vazia proíbe hipérbole de persona. O resto das proibições de R-17 fica escrito na mesma regra. A versão usada vai para o `agent_log` de cada chamada.
4. **Ler** com `agents.read` (quem vê a página dos agentes), na aba Frases-persona.

## Alternativas rejeitadas

- Guardar as frases dentro da configuração dos agentes (`agent_config_versions`): misturava uma decisão jurídica/editorial com parâmetros técnicos e exigia ativar uma configuração para mudar uma frase.
- Fixar a lista na execução no momento em que entra na fila: a lista em vigor no claim é a que a equipa espera; a versão fica registada, por isso é auditável na mesma.
- Verificador automático de hipérbole fora da lista nos guiões gerados: fica para VAR-04 (classificador de títulos).

## Consequência

Enquanto a lista do Numeiro estiver vazia, os agentes deixam de usar hipérbole de persona. Para manter as frases habituais, o dono ou admin do cliente grava-as na aba.

## Rollback

Bloco no fim de `*_w5_persona_phrases.sql`. O motor sem a chave `persona` no claim volta ao comportamento anterior.
