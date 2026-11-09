# ADR-0071 — Decisões do dono de 2026-11-09: custos, direitos para a IA, lições da agência e Início (W10-22)

**Data:** 2026-11-09 · **Estado:** aceite (decisões do dono do produto, Tomás, 2026-11-09); implementação proposta (PR por aprovar) · **Requisitos:** PRD FR-10-01, EDL-07, EDL-11, LRN-01, LRN-03, LRN-04, FR-01-02; AGENTS §2.1, §5, §7, §9; ADR-0062 (custos), ADR-0068 (visuais da IA), ADR-0069 (aprendizagem).

## Contexto

Ficaram pendentes de decisão do dono: quem vê os custos de IA dentro de um cliente (ADR-0062 dava `costs.read`/`costs.export` por defeito ao dono e ao admin do cliente, o que incluía a equipa do próprio cliente, em conflito com AGENTS §9), quem garante os direitos dos ficheiros que a IA usa (EDL-07/EDL-11), se a equipa do cliente vê as regras da agência que o motor lhe aplica (LRN-04), quem aprova lições e o limiar de 30% (LRN-03, LRN-01) e quando ligar o pipeline diário do Numeiro. Apareceu também um erro no Início: "Formatos de hoje" contava guiões arquivados.

## Decisões do dono (2026-11-09)

1. **Custos (FR-10-01, AGENTS §9):** a equipa do próprio cliente nunca vê custos de IA, seja qual for o papel ou a exceção individual. Staff da agência com `costs.read` continua a ver; o código de equipa continua a nunca ver.
2. **Direitos para a IA (EDL-07, EDL-11):** pôr numa peça da Biblioteca a etiqueta `ia-imagem`, `ia-atencao` ou `ia-musica` é a declaração de quem a põe de que o cliente tem direitos para a IA usar o ficheiro. A app avisa e pede confirmação explícita; a declaração fica no histórico.
3. **Lições da agência (LRN-04):** a equipa do cliente vê as regras da agência que se lhe aplicam, só leitura (sem aprovar, editar nem promover), em Aprendizagem → Lições, numa secção "Regras da agência (só leitura)". As propostas da agência continuam só para a equipa da agência.
4. **Quem aprova lições (LRN-03):** dono, admin e gestor do cliente (`workspace_owner`, `workspace_admin`, `manager`), como já estava implementado em ADR-0069 como proposta. Sem código.
5. **Limiar de edição (LRN-01):** o motivo obrigatório acima de 30% de texto mudado fica. Sem código.
6. **Pipeline diário do Numeiro:** continua desligado até depois da primeira semana real de gravação. Só registo; nenhuma flag nem agenda mudam aqui.
7. **Início:** "Formatos de hoje" e "Guiões de hoje" contam só guiões vivos (sem arquivados nem eliminados). Correção de erro, sem decisão de produto.

## Implementação

Migração aditiva `supabase/migrations/20261109094711_w10_decisoes_dono.sql` (sem tabelas, colunas, capacidades nem grants novos; rollback no fim).

1. **Custos:** a regra fica no avaliador central, `_authorize_base` (reescrito a partir de `20261103203930_w1_preview_papel.sql`): com acesso `client_staff` ao cliente, qualquer capacidade `costs.*` é recusada, depois da negação explícita e do dono da agência e antes dos papéis e exceções. Assim recusam ou escondem, sem tocar em cada função: `costs_ai_usage`, `costs_ai_usage_export`, `content_costs`, `content_costs_export` (42501 com `audit_denied` de `_content_require`), o widget `kpi.costs` do Início, o custo e o limite na configuração dos agentes (`agents_overview.can.costs`) e o menu "Custos" do cliente, que já deriva de `my_context.capabilities` (o servidor deixa de devolver `costs.*`). `_access_explain` (consola de permissões, simulação) diz o motivo: "A equipa do cliente nunca vê custos de IA…". Os registos de `role_capabilities` não mudam: um admin de cliente que seja staff da agência mantém `costs.read`.
2. **Direitos para a IA:** trigger `media_assets_ai_rights` (AFTER INSERT/UPDATE OF tags em `media_assets`): se a escrita acrescenta `ia-imagem`, `ia-atencao` ou `ia-musica` e vem de uma pessoa ou do código de equipa (`auth.role()` `authenticated`/`anon`) sem a confirmação da transação (`clipstudio.ai_rights_confirmed`), recusa com 22023 `direitos_ia_por_confirmar`. Senão regista `media.ai_rights_declared` no histórico (quem, quando, etiquetas acrescentadas, ativo, versão atual e número, se houve confirmação, o texto da declaração). `media_asset_save` (reescrito a partir de `20261103152523_w8_media_p2.sql`) aceita `p_fields.ai_rights_confirmed` e liga a confirmação só para a sua escrita. Na ficha do ativo, ao acrescentar uma destas etiquetas aparece o aviso e a caixa "Confirmo que o cliente tem direitos para a IA usar este ficheiro."; Guardar fica desligado até a marcar. No envio da Biblioteca, estas etiquetas são recusadas com a indicação de as pôr na ficha.
3. **Lições:** `lrn_lessons_list` (reescrito a partir de `20261106132216_w10_aprendizagem.sql`, tudo o resto igual) devolve `agency` também a uma sessão individual que não é da agência: `readonly: true`, a versão em vigor só com `id`, `category` e `text` de cada regra (sem `change`, `created_label` nem evidência) e `proposed: []`. A equipa da agência recebe `readonly: false` e o mesmo de antes. Código de equipa: `null`. Aprovar, retirar, voltar atrás e promover continuam a exigir `learn.lessons.agency` (42501).
4. **Início:** `src/lib/today-format.ts` (`liveToday`, `formatMix`) tira os arquivados (`editorial_status = 'archived'`) e os eliminados (`deleted_at`, que a RLS de `guioes` já esconde) antes de contar; os rejeitados continuam fora da mistura de formatos como antes.

## Alternativas rejeitadas

- **Tirar `costs.read`/`costs.export` de `workspace_owner`/`workspace_admin` em `role_capabilities`:** também tirava os custos ao staff da agência que é admin num cliente, e uma exceção individual voltava a abrir à equipa do cliente. A decisão é por afiliação, não por papel.
- **Verificar a afiliação em cada RPC de custos:** obrigava a reescrever quatro RPCs, o painel do Início e a configuração dos agentes, e o menu continuaria a mostrar "Custos". O avaliador central cobre tudo e a consola explica.
- **Guardar a declaração só no `after` do `media.asset_updated`:** o `after` copia as colunas do ativo, não a confirmação nem a versão; e o servidor não podia exigir a confirmação. A recusa no servidor precisava de uma regra; ficou num trigger para cobrir também o envio e os links sem os reescrever.
- **Aceitar a confirmação também no envio (`media_upload_begin`) e nos links:** obrigava a reescrever duas funções grandes; a etiqueta põe-se na ficha depois de carregar.
- **Mostrar à equipa do cliente a mesma versão da agência que vê a agência:** incluía quem mudou e o tipo de mudança, que são dados internos da agência.

## Limitações e riscos

- Uma pré-visualização de acesso por papel (`access_previews.target_role`) não sabe a afiliação: o dono da agência a pré-visualizar "admin" vê custos. A pré-visualização de uma pessoa concreta da equipa do cliente esconde-os.
- A confirmação de direitos é declarativa (não há verificação de licenças); fica o registo de quem declarou.
- Workers e service role não são travados pelo trigger (nenhum acrescenta `ia-*` hoje); se o fizerem ficam registados com `confirmed = false`.
- Verificação com sessão real (R-15) da agência e de uma conta de cliente por fazer depois de aplicar a migração.

## Rollback

Ver o bloco no fim da migração: recriar `_authorize_base`, `_access_explain`, `media_asset_save` e `lrn_lessons_list` com os corpos das migrações de origem, e apagar o trigger e as duas funções novas. Os registos `media.ai_rights_declared` ficam (histórico só de acrescentar). O browser deixa de mandar `ai_rights_confirmed` antes de recriar o `media_asset_save` antigo (que o recusaria como campo desconhecido).
