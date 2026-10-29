# ADR-0023 · Envio de convites por email, com link e recusa

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** FR-13-01, FR-13-05, TEAM-04, R-03

## Contexto
Os convites existiam só na base de dados: quem convidava tinha de avisar a pessoa por fora, não havia forma de recusar nem de reenviar, e um convite expirado desaparecia da lista. O SMTP do Supabase está limitado a poucos emails por hora e não serve para convites.

## Decisão
- **Link com token.** `invitation_issue_link` gera 24 bytes aleatórios por envio; na base fica só o SHA-256. Cada reenvio troca o token, por isso só o último email vale. O link leva a `/convite?t=`, uma página pública que mostra o convite (quem convidou, para onde, papel, validade) e deixa aceitar ou recusar.
- **Aceitar continua a ser por email confirmado.** Aceitar exige entrar com o email do convite (`accept_invitations`, que passa a ignorar recusados). O token sozinho não dá acesso a nada: só mostra e recusa.
- **Envio no servidor.** `POST /api/invites/:id/send` chama a RPC com a sessão de quem pede (é a base de dados que decide quem pode) e envia pelo Resend quando `RESEND_API_KEY` e `INVITE_FROM` estão definidos no Vercel. Sem eles, ou se o serviço falhar, devolve o link e a app mostra-o para copiar: alternativa manual explícita (AGENTS §8), nunca um sucesso falso.
- **Limites.** Um envio por minuto e no máximo 5 por convite (PT429). Reenviar renova a validade para 14 dias.
- **Lista.** As listas de convites mostram também expirados e recusados durante 30 dias, com estado e último envio.

## Alternativas rejeitadas
- `auth.admin.inviteUserByEmail` do Supabase: precisa da chave de serviço na app, cria a conta antes de a pessoa aceitar e usa o SMTP limitado.
- Aceitar pelo token sem login: quem apanhasse o link entrava no cliente.
- Guardar o token em claro: uma fuga da base de dados dava acesso a todos os links pendentes.

## Consequências
Para os emails saírem, o Tomás cria a conta no Resend, verifica o domínio e põe `RESEND_API_KEY`, `INVITE_FROM` e `APP_URL` no Vercel. Até lá tudo funciona com o link copiado. Rollback: ver o fim da migração `20261029151140_w1_invite_delivery.sql`; as colunas novas só saem num contract posterior.
