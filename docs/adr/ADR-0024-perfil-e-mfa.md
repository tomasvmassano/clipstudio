# ADR-0024 · Perfil próprio e verificação em dois passos aplicada no servidor

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** FR-14-01, FR-14-02 (parte), FR-14-03 (parte), FR-14-04

## Contexto
Não havia página de perfil: sem nome, fotografia, mudança de palavra-passe, recuperação nem MFA. O PRD pede MFA "quando disponível". O Supabase Auth suporta TOTP, mas por si só só muda o `aal` do token; se a base de dados não olhar para isso, quem rouba uma palavra-passe entra na mesma.

## Decisão
- `profiles` (uma linha por pessoa, só pelas RPCs `profile_update` e `my_context`): nome, avatar, fuso, tema e cliente preferido. Avatar num bucket privado `avatars`, só na pasta `<uid>/` da própria pessoa (RLS do storage), com URL assinado de 1 hora.
- **MFA no servidor:** `_mfa_ok` faz `_authorize` e `_org_can` recusarem quem tem um fator TOTP verificado e apresenta uma sessão `aal1`. Só vale para o pedido da própria pessoa (`p_uid = auth.uid()`), para não afetar verificações que o servidor faz por outros. `my_context` devolve `mfa_required` e a app leva ao passo do código no login.
- Palavra-passe: mudar exige a atual (confirmada com uma entrada nova); recuperar usa o link do Supabase para `/perfil?recuperar=1`.
- Histórico de segurança: `security_event` regista mudanças de palavra-passe, MFA e "terminar sessão em todo o lado" depois de o Auth as confirmar; `my_security_log` mostra-as à própria pessoa.
- `/perfil` existe nos dois espaços (`/perfil` e `/c/[ws]/perfil`).

## Alternativas rejeitadas
- Nome e avatar em `user_metadata`: editável por qualquer cliente com a sessão e vai no JWT; não serve para nada que se audite.
- MFA só na interface: não protege a API nem o REST.
- Obrigar MFA a todos já: decisão do owner; fica disponível e o dono pode ligá-lo primeiro.

## Consequências
O email de recuperação sai pelo SMTP do Supabase (poucos por hora) até haver domínio próprio (FR-13-01 adiado). Sessões/dispositivos individuais (FR-14-03) e exportação de dados (FR-14-05) ficam por fazer. Rollback no fim da migração `20261029153629_w1_profile_mfa.sql`.
