# ADR-0054 — Verificador antes da revisão humana (W10-06)

**Data:** 2026-11-06 · **Estado:** proposto · **Requisitos:** PRD VAR-04, R-17 (CHG-003), SCALE-05; AGENTS §7. Número sujeito a renumeração se outro PR ocupar o 0054.

## Decisão

1. **Passo novo no motor, depois do Crítico e do Editor** (`engine/agents/quality.py` `Verifier`, chamado em `orchestrator.run_slot`). Cada hook (o título/sobreposição do vídeo) é classificado em afirmações: persona, opinião atribuída, facto, terceiro identificado, afirmação com validade; e PT-PT (mesmas expressões do Editor; idioma do cliente diferente de pt-PT não é marcado).
2. **O LLM classifica, as regras decidem a marca** (`reconcile`): persona só passa se a frase estiver na lista aprovada em vigor no claim (normalizada, tal e qual; lista vazia = fora da regra; sem lista = rever); facto exige fonte datada (a ideia de origem com URL e data) e mesmo assim fica "atenção, não verificado"; terceiro identificado leva marca jurídica (exceto famosos dentro de uma frase-persona aprovada, R-17); validade leva data de expiração; promessa de ganhos fica fora da regra. O LLM só pode agravar uma marca. Se o LLM falhar, ficam as regras e o resultado diz "só regras". Com `ENGINE_MOCK=1` o LLM é substituído pelas mesmas heurísticas.
3. **Nunca chumba sozinho.** O guião entra em revisão como antes; o resultado vai ao lado e a UI mostra marcas por hook com o porquê. Quem revê decide.
4. **Guardar ao lado, não dentro do guião.** Tabela `script_verifications` (fechada à API) escrita por `worker_save_verification` (lease, só guiões de `agent_job_outputs` da própria execução, idempotente por execução e guião, forma validada, 64 KB), com a versão do texto (`current_version_id`), versão do verificador, modelo, versão dos prompts e da lista de frases-persona. Leitura por `content_verifications(ws, ids, token)` com `scripts.read`.
5. **Expandir/contrair entre repositórios.** A app sem a migração: o worker apanha 42883, regista e segue (guião gravado, sem verificação). O motor antigo não chama a função nova.

## Alternativas rejeitadas

- Campo dentro de `guioes.hooks` ou coluna em `guioes`: `worker_save_script` deita fora chaves desconhecidas dos hooks e uma coluna em `guioes` ficava editável por quem tem `scripts.edit` (o resultado do verificador podia ser forjado no browser).
- Alterar `worker_save_script` para gravar tudo numa transação: outros trabalhos em paralelo mexem nessa função; redefini-la arriscava apagar mudanças alheias. A chamada separada é idempotente e, se falhar, o guião continua (conta em `progress.verificacao_falhou`).
- Chumbar automaticamente guiões com persona fora da lista: contraria "quem revê decide" e perde guiões bons por falsos positivos das heurísticas.
- Texto nas `notas`: não estruturado, sem marcas por hook nem versões.

## Consequências

Uma chamada LLM a mais por guião aprovado (modelo `verifier` da configuração ou, por omissão, o do Crítico), registada no `agent_log` com versões. Guiões gravados por uma tentativa que caiu entre gravar e verificar ficam "sem verificação" na UI.

## Rollback

Bloco no fim de `supabase/migrations/PENDING_w10_verificador.sql`. Motor: reverter o PR do numeiro-engine (ou deixar: sem a função na app só regista).
