# ADR-0001: Tenancy, identidade e transição do código de equipa

Estado: **aceite** (28/10/2026, decisões do owner Tomás). Requisitos: R-01…R-12, TEAM-01…05, TEAM-16, CAP-01/03/05, MIG-02/03/04/06.

## Contexto

A app serve um cliente (`numeiro`) com isolamento por convenção e escrita por código de equipa partilhado (ver `docs/inventory/supabase.md`). O PRD exige identidade individual, agência com vários workspaces e autorização no servidor.

## Decisões

1. **Organização da agência: "ClipStudio"** (`organizations`, slug `clipstudio`). Todos os workspaces pertencem-lhe.
2. **Workspace = linha de `clients`.** Para não migrar FKs de 15 tabelas e do motor agora, a tabela `clients` passa a ser a tabela de workspaces (ganha `organization_id`, `timezone`, `currency`, `status`) e a coluna `client_id` é o `workspace_id`. Renomear para `workspaces`/`workspace_id` fica para quando o motor estiver migrado (W4), com vista de compatibilidade. *Alternativa rejeitada:* tabela `workspaces` nova em paralelo, que criaria duas fontes de verdade (PRD §7 o proíbe).
3. **Login: email + password e Google** (Supabase Auth). O Google só aparece quando o provider estiver ativo no Supabase (precisa de OAuth client do Google Cloud, a configurar pelo owner). Registo aberto, mas **sem convite não há acesso a nada** (deny by default).
4. **Convites por email**: quem tem `team.invite` cria um convite (email, papel, workspace). Quando a pessoa entra com esse email **confirmado**, o convite é aceite e o acesso criado. Não há envio de email transacional ainda; o link de entrada é partilhado à mão.
5. **Referências isoladas por cliente**: as contas de referência passam a pertencer ao workspace do cliente (`accounts.client_id`). Outro cliente terá as suas próprias.
6. **Autorização central**: `authorize(capability, workspace)` em SQL, usada por RLS e RPCs. Avaliação de PRD §3: identidade ativa ∧ acesso ativo e não expirado ∧ capacidade do papel ou grant `allow` ∧ sem grant `deny`. Capacidade desconhecida = negado. `agency_owner` ativo tem acesso global (CAP-08); as escritas ficam no `audit_events`.
7. **Transição do código de equipa (decisão: em paralelo)**: o código continua a funcionar só por RPCs `security definer` que validam o token e registam `actor_kind='legacy_code'` no audit. As leituras públicas anónimas acabam: sem login nem código, não se vê nada. O código é desligado quando o Numeiro tiver conta (MIG-04, MIG-10).
8. **Auditoria**: `audit_events` só aceita inserções (sem UPDATE/DELETE para ninguém da API), com ator, tipo de ator, workspace, ação, entidade, antes/depois e resultado. Nunca guarda tokens (R-05).

## Consequências

Links partilhados sem código deixam de mostrar guiões (antes eram públicos). A sala dos agentes em tempo real passa a canal privado: só utilizadores com login a recebem; quem usa o código vê as corridas ao recarregar. O motor continua como owner até ao W4 (risco registado).

## Rollback

Cada migração W1 é aditiva. Para voltar atrás: recriar as políticas `*_read using (true)` removidas (estão em `supabase/migrations/20261028160333_*` e `20261028162355_*`) e repor as assinaturas antigas das RPCs. Os dados não mudam de forma destrutiva (só `accounts.client_id` das referências e `ideas.client_id` são preenchidos).
