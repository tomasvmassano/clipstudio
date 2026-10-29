# AGENTS.md — ClipStudio Engineering & Product Guidelines

**Version:** 1.1 · **Owner:** Product/Engineering · **Language:** PT-PT for product; English identifiers in code.

> **Source of truth:** `docs/ClipStudio_PRD_Master_v2.1.md`. This file governs implementation discipline, not product scope. If it conflicts with product requirements, flag the conflict and request an explicit decision. Do not silently change the PRD. The existing repository's Next.js generated `AGENTS.md` guidance must also be preserved, especially its instruction to consult the installed Next.js version documentation.

## 1. Mission and boundaries

Build ClipStudio as a reliable multi-client content operations platform: one global user identity; agency staff can access explicitly authorized client workspaces; each client's own staff are restricted to their workspace. Workflow: Sources → Brief → Scripts → Approval → Recording → Media → Review → Publication → Analytics → Learning. The Numeiro/Viral Engine configuration is a **workspace preset**, never a global hardcoded rule.

## 2. Non-negotiable invariants

1. Deny by default. Every business read/write checks authenticated identity, active membership, workspace scope, resource scope, and explicit permission server-side.
2. Never trust `workspace_id`, `client_id`, `role`, or `user_id` supplied by a browser as proof of authorization. Enforce RLS and scoped queries/RPCs/storage/realtime/jobs.
3. Agency staff do not automatically gain client access by being staff; client staff never gain agency-wide access. Agency owner global access is privileged and audited.
4. Job title (clipper, editor, copywriter, etc.) is not an authorization role. Roles and grants are separate.
5. One canonical content identity links source, brief, script, versions, hooks, takes, variants, tasks, approvals, publications, and metrics.
6. Approved versions are immutable. Editing creates a new version and may invalidate approvals.
7. Publishing requires explicit human approval of the correct asset version and destination. Never silently auto-publish.
8. Async operations must be durable, idempotent, observable, cancellable where feasible, and recoverable after failures.
9. Never store secrets in source, browser bundles, client logs, screenshots, or test fixtures.
10. Never claim a feature works based only on a rendered page; test the actual persisted workflow and failure cases.

## 3. Before starting a task

- Read the relevant PRD requirement IDs and acceptance criteria. Read related code, existing migrations, tests, and integration contracts.
- Verify actual installed package versions. For Next.js, consult the installed version docs under `node_modules/next/dist/docs/` before changing routing/auth/data APIs, as required by the repository's generated agent instructions.
- Identify affected workspaces, permissions, database entities, events, background jobs, UI, and integrations.
- Document assumptions and blockers. If production SQL/RLS, Python engine, or external API contract is unavailable, label **UNVERIFIED**; do not fabricate implementation details.
- Write a short implementation plan with dependencies and rollback strategy for schema/security changes.

## 4. Implementation pattern

For each PRD requirement implement, in order:

1. Data model and migration (including constraints, indices, tenant scoping, backfill, rollback).
2. Server-side authorization and RLS tests (including cross-tenant negative tests).
3. API/service contracts, validation, error taxonomy, idempotency, audit event.
4. UI states: initial, loading, empty, success, validation error, network error, forbidden, retry, offline when relevant.
5. Unit/integration/E2E tests with at least two workspaces and agency/client accounts.
6. Observability, documentation, and acceptance evidence.

No dead links, `href="#"` placeholders, fake metrics, decorative buttons, swallowed errors, or indefinite spinners in a releasable feature. Hide unavailable features or label them explicitly as unavailable, never imply completion.

## 5. Auth and tenancy

- Use individual Supabase Auth identities and invitation flows; remove shared team-code access only after safe migration.
- Centralize policy evaluation; UI may hide actions, but server/RLS are authoritative.
- Validate membership on each request and worker action; do not use stale cached grants for sensitive operations.
- Every tenant-owned table, object path, search index, realtime subscription, export, and job is workspace-scoped.
- Test URL tampering, object ID swapping, stale signed URLs, removed users, invite escalation, and cross-workspace search.
- An agency staff member may have different permissions in A and B; the client A member must never discover B.

## 6. Content and workflow

- Keep editorial, production, media review, and publication statuses distinct. Define transitions and actor permissions in a state machine.
- Every transition stores actor, timestamp, version, previous/new status, reason, and correlation ID.
- Create tasks/notifications through idempotent events; no duplicate assignments after retry.
- For the teleprompter, scrolling past a threshold is **not proof of recording**. Require confirmation by default.
- Preserve rejected versions and reasons; regenerations create linked new outputs, not destructive overwrites.
- Multiple publications can share one content variant but have independent platform/account/caption/time/metrics.

## 7. AI and automation

- Model, prompt, agent and rubric versions must be explicit and auditable. Store run/step state, input/output references, token use, cost, duration, retries, and errors.
- Never present generated claims as verified facts; keep source provenance and verification state. Block unverified quotations from factual scripts where required.
- Persona hyperbole about the creator (PRD R-17, CHG-003) is not a factual claim: allow it only from the workspace's approved, versioned persona-phrase list. Keep blocking false claims about identified third parties, invented news about real events, numbers presented as verified data and promises of financial gain.
- Execute long pipelines in durable workers, not short request handlers. Use concurrency controls, exponential backoff, idempotency keys, budget caps, and dead-letter handling.
- Treat the original Viral Engine's 30 scripts, 3 hooks, 90 videos, 18:00 Dubai schedule as **Numeiro defaults only**.
- AI recommendations do not automatically modify strategy, permissions, or publication settings without authorized approval.
- The agents-room animation is a view of real persisted events; never fabricate status or messages.

## 8. Media and external integrations

- Use object storage appropriate for file size; large raw sessions should not be placed in the small final-asset bucket by default.
- Validate media MIME/size/checksum, permissions, virus scanning where appropriate, retention and signed access.
- Separate upload, transcode, edit, render, and review jobs; expose each state and recovery action.
- Only use officially authorized platform/API integrations. Provide explicit manual fallback where API capability is absent.
- OAuth tokens are encrypted and scoped per workspace/social account; token expiry is visible and recoverable.
- Publishing endpoints must be idempotent; never duplicate posts after retry.

## 9. UX and accessibility

- PT-PT initial UI; dates stored UTC and shown in the workspace timezone. Dark theme default, accessible contrast, keyboard navigation and WCAG 2.2 AA targets.
- Desktop, iPad, mobile; teleprompter has large touch targets, Bluetooth keyboard controls, independent H/V mirror, safe resume and persistent settings.
- A user should see their work first: inbox, tasks, blockers, approvals. Agency users may switch among authorized workspaces; client users remain scoped.
- Loading must show progress where known; every failure offers a clear recovery action. Never use optimistic success for critical approvals/publication without confirmation.
- Avoid displaying confidential cost data or agency-only controls to client staff.

## 10. Testing and release gates

Minimum required suites:

- Unit tests: state machines, permissions, calculations, validators.
- Integration tests: SQL/RLS/RPC, events, jobs, storage, OAuth token handling.
- E2E: agency member A+B, client A only, client B only, reviewer/editor, script approval, teleprompter, media revision, multi-account publishing, retries and failures.
- Negative security: 403/404 for unauthorized workspace/API/media/search; removed membership revokes new requests.
- Non-functional: accessibility, responsive iPad, performance, backup restore, log redaction, error alerts.

- Runtime guards (PRD R-15, CHG-002): error boundaries at app, space (`app/c/[ws]/error.tsx`), global and per widget; realtime channels and any browser resource returned by name only through `src/lib/realtime.ts` (`realtime.listen`); network errors never end a session. CI `Qualidade` (guards, lint, types, unit tests, build) must pass.
- Verify with a **real logged-in session** (agency and client) before calling a navigation or live-data change done; team-code E2E alone is not enough (it skips realtime and agency paths). Zero console errors on main routes.

**Release blocked if:** a route falls into the browser/Next generic error page; cross-tenant leak; critical authorization bypass; missing migration rollback/backup for destructive change; publishing without approval; secrets exposed; failed critical E2E; broken primary route; silent data loss; unbounded retry/duplicated job; critical error without recovery.

## 11. Change control

- PRD requirement IDs remain stable. New behavior needs a new ID or explicit revision record.
- For each PR, include: requirement IDs, affected files, migrations, permissions, tests run/results, screenshots for UI, known limitations, rollback plan.
- Keep a `CHANGELOG.md` and a decisions log (`docs/adr/`). Record rejected alternatives and trade-offs.
- Prefer small, independently verifiable increments. Never change scope or silently replace an integration with mock data.
- Preserve existing user data and compatibility during migrations; stage and reconcile counts before switching.

## 12. Definition of Done (mandatory)

A feature is DONE only when: implemented in backend and UI; authorized and tenant-isolated; correct persistence and versions; failure/loading/empty states; automated tests pass; accessibility and responsive behavior verified; events/logs present; docs and changelog updated; acceptance criteria demonstrated in staging. If any condition is missing, mark **PARTIAL** and list what remains.

## 13. Task reporting template

At the end of every implementation task report:

- **Requirement IDs:** ...
- **Implemented:** ...
- **Files/migrations:** ...
- **Authorization/RLS impact:** ...
- **Tests executed and outcomes:** ...
- **Manual verification needed:** ...
- **Risks/known gaps:** ...
- **Status:** DONE / PARTIAL / BLOCKED.

## 14. Repository integration

Place this document at repository root as `AGENTS.md` **after merging with, not deleting**, the repository's existing Next.js-generated AGENTS instructions. Put `ClipStudio_PRD_Master_v2.1.md` in `docs/` and update this path if moved. Agents should read both at task start. Do not commit live credentials or database dumps.

## 15. Mandatory feature change protocol (PRD v2.1)

- Every request, however small, requires a `change_id`, product owner, affected roles/workspaces, capability keys, data/API/RLS/storage/realtime/job/event impact, failure modes, acceptance criteria and rollback. Do not implement an isolated UI request without these.
- Maintain `docs/feature-registry.md`, `docs/access-matrix.md`, `docs/workflow-registry.md`, `docs/CHANGELOG.md`, and an ADR for architectural decisions in the same pull request.
- Any new button, module, endpoint, worker action or export must have a registered stable capability key and server-side policy enforcement. Fail closed for unknown capabilities.
- Permission UI must derive from the capability registry, not hardcoded unrelated toggles. Custom role changes and per-user overrides require scoped authorization, before/after audit, and cross-tenant negative tests.
- Distinguish `online`, `active`, `working` and `available`. Presence is not proof of working hours or productivity. Never expose another client's presence or tasks.
- Before marking Done, demonstrate: agency staff with A/B grants, client-only staff A, an individual override, explicit deny, revoked session, URL/API bypass attempt, and one new feature registered and visible in the permission console.
- If requested behavior conflicts with current PRD or policy, propose a PRD change and await product decision. Never silently weaken security, broaden grants or substitute mock data.

---

## Next.js generated instructions (preserved, do not delete)

<!-- BEGIN:nextjs-agent-rules -->

## This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->
