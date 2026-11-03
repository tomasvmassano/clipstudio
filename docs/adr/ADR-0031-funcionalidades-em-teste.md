# ADR-0031 · Interruptores de funcionalidades por cliente

**Estado:** aceite · **Data:** 2026-10-29 · **Requisitos:** MIG-09, CAP-09

## Contexto
Para acelerar a entrega, vários módulos novos vão ser feitos em paralelo. O PRD (§44, MIG-09) pede que entrem atrás de uma flag por workspace e que disponibilidade não seja autorização (CAP-09). Não havia mecanismo.

## Decisão
- `feature_flag_defs`: registo de cada flag (chave estável, módulo, âmbito `ws` ou `org`, fase por defeito). `feature_flags`: exceções para a agência inteira (sem cliente) ou para um cliente. Fases: `off` (ninguém), `owner` (só donos da agência), `agency` (equipa da agência com acesso), `all` (todos com acesso). A exceção do cliente ganha à da agência, que ganha ao defeito.
- `my_flags(ws)` devolve as flags ligadas para quem pede; não revela nada de clientes a que a pessoa não tem acesso. O código de equipa só vê fases `all`.
- Gestão em `/funcionalidades`, só com `flags.manage` (dono da agência). Cada mudança fica na auditoria com antes e depois.
- No browser: `useFlags`, `FlagGate` (também para quem entra pelo endereço) e `flag` nos itens do menu. As RPCs dos módulos continuam a verificar capacidades: uma flag ligada não dá acesso a nada.
- Módulos novos registam a sua flag com fase por defeito `owner`.

## Alternativas rejeitadas
- Flags no código ou em variáveis do Vercel: exigiam uma publicação para ligar a um cliente e não davam fases por pessoa.
- Usar as capacidades como flags: misturava disponibilidade com autorização (CAP-09).

## Consequências
Os módulos da vaga 1 (vista de negócio, centro de desempenho, área de trabalho) entram desligados para os clientes até o Tomás os ligar. Rollback no fim da migração.
