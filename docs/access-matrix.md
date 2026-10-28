# Matriz de acessos

Fonte: PRD v2.1 §3 (papéis), §5A (TEAM-01…16), CAP-03/05/08. **PROPOSTA de defaults**, a validar pelo owner; grants individuais e negações explícitas por cima (CAP-03).

**Avaliação** (PRD §3): `allow` só se identidade ativa ∧ membership ativo ∧ workspace autorizado ∧ grant suficiente ∧ recurso no âmbito ∧ sem `deny` explícito. Por defeito `deny`. A afiliação (`agency_staff`/`client_staff`) e o cargo (clipper, editor…) **não** são papéis.

## Papéis da agência (âmbito `org`)

| Capacidade | agency_owner | agency_admin | agency_manager | agency_member |
| --- | --- | --- | --- | --- |
| `workspaces.read` | todos (auditado) | delegados | atribuídos | atribuídos |
| `workspaces.create` / `archive` | ✓ | se delegado | — | — |
| `team.invite` (staff interno) | ✓ | se delegado | — | — |
| `team.manage` (atribuir staff a clientes) | ✓ | se delegado | — | — |
| `permissions.manage` (org) | ✓ | limitado | — | — |
| `costs.read_agency` | ✓ | se delegado | — | — |
| `audit.read` (org) | ✓ | ✓ | — | — |

Um `agency_member` sem atribuição a um workspace **não vê nada** desse workspace (R-03, TEAM-03).

## Papéis do workspace (âmbito `ws`)

| Capacidade | ws_owner | ws_admin | manager | contributor | reviewer | viewer |
| --- | --- | --- | --- | --- | --- | --- |
| `scripts.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `scripts.create` / `edit` / `submit` | ✓ | ✓ | ✓ | ✓ (own) | — | — |
| `scripts.approve` / `reject` | ✓ | ✓ | ✓ | — | ✓ | — |
| `scripts.delete` | ✓ | ✓ | — | — | — | — |
| `scripts.export` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `recording.use` / `confirm` | ✓ | ✓ | ✓ | ✓ (own) | — | — |
| `sources.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `sources.create` / `triage` | ✓ | ✓ | ✓ | ✓ | — | — |
| `review.comment` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `review.approve` | ✓ | ✓ | ✓ | — | ✓ | — |
| `media.upload` / `download` | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| `media.share` | ✓ | ✓ | ✓ | — | — | — |
| `publishing.schedule` / `publish` | ✓ | ✓ | grant | — | — | — |
| `analytics.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `costs.read` | ✓ | ✓ | grant | — | — | — |
| `agents.read` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `agents.rehearse` / `run` | ✓ | ✓ | ✓ | — | — | — |
| `agents.configure` | ✓ | ✓ | — | — | — | — |
| `team.invite` (client_staff, mesmo workspace) | ✓ | ✓ | — | — | — | — |
| `team.manage` / `permissions.manage` (ws) | ✓ | dentro do teto | — | — | — | — |
| `settings.manage` / `integrations.manage` | ✓ | ✓ | — | — | — | — |

Teto de autoridade: ninguém concede mais do que tem (R-12); um admin do cliente nunca cria papéis da agência nem convida staff da agência (TEAM-02, TEAM-04).

## Mapeamento de hoje

O código de equipa `studio_tokens(role='creator')` do Numeiro corresponde a um `contributor` com `scripts.approve`, `scripts.reject` e `recording.confirm` por grant. Na migração W1 cada pessoa que usa o código recebe uma conta individual com esse papel. O código só é desligado depois de a migração estar validada (AGENTS §5).
