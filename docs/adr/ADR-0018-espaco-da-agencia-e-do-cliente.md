# ADR-0018 — Espaço da agência e espaço do cliente (W1-11)

**Data:** 2026-10-29 · **Estado:** aceite · **Requisitos:** PRD §2 (hierarquia, regra de âmbito), R-01, R-03, R-04, M01; decisão de produto do Tomás (29/10).

## Contexto

A app era uma só, com o cliente escolhido num seletor guardado no browser e a agência como mais uma página. O produto pediu o contrário: a agência é a casa da equipa da agência; o cliente é um espaço onde se entra a partir dela; a equipa de um cliente só conhece o seu.

## Decisão

1. **Dois espaços.** Espaço da agência em `/` (Painel), `/clientes`, `/caixa` (todos os clientes) e, a seguir, equipa da agência, calendário de todos, custos, histórico e definições da agência (hoje "em breve" no menu). Espaço do cliente em `/c/<cliente>/…` com o menu operacional (Início, Guiões, Tarefas, Calendário, Teleprompter, Fontes, Referências, Desempenho, Agentes) e a administração desse cliente (equipa, permissões, histórico, definições).
2. **O cliente aberto vive no endereço**, não no browser. Um link abre sempre o cliente certo; recarregar não muda de cliente. O servidor continua a verificar o acesso em cada pedido (R-01): o endereço nunca é prova de autorização.
3. **Entrada.** A equipa da agência (`dashboard.agency`) entra sempre no Painel. A equipa de um cliente e o código de equipa vão direto para o seu cliente e nunca veem nada da agência.
4. **Sem acesso não revela nada.** Um cliente no endereço a que a pessoa não tem acesso, ou que não existe, mostra a mesma mensagem.
5. **Rotas antigas** (`/guioes`, `/tarefas?tab=…`) redirecionam para a mesma página do último cliente aberto, mantendo os parâmetros.
6. **Um cliente por pessoa da equipa do cliente (R-03)**, agora imposto na aceitação dos convites: um convite de cliente para quem já está noutro cliente é cancelado e registado (`invitation.blocked`), sem erro para quem convidou (não revela que o email pertence a outro cliente).
7. **Sessão por código:** só se revalida quando o código muda; uma falha de rede já não termina a sessão (o servidor valida o código em cada pedido; código revogado continua a terminar a sessão).

## Alternativas rejeitadas

- **Manter o cliente no browser:** menos mudança, mas links sem cliente e risco de abrir o cliente errado depois de trocar noutro separador.
- **Subdomínio por cliente:** isolamento visual forte, mas exige DNS e sessões por domínio; desnecessário com RLS.

## Rollback

Reverter o PR repõe as rotas planas (as rotas `/c/…` deixam de existir). Migração: comentário no topo de `20261029121252_w1_single_client_staff.sql`.
