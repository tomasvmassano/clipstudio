# CLAUDE.md

Read and follow these at the start of every implementation task, before touching code:

@AGENTS.md

Product source of truth: `docs/ClipStudio_PRD_Master_v2.1.md`. It is long, so read the sections whose requirement IDs the task touches (grep the FR/R/NFR IDs) rather than loading it whole, and always re-read sections 2, 3, 22, 30 and 33 when a change affects auth, tenancy, permissions or a new capability.

If a request conflicts with the PRD or AGENTS.md, stop and ask for a product decision. End every task with the reporting template in AGENTS.md section 13.

## Change workflow

- Never push to `main`. Work on a branch (`w<N>-<id>-<slug>` for features, `docs/chg-NNN` for docs), open a PR, wait for all checks and the Vercel preview, verify the preview, then merge it yourself. No human approval is required unless the task says so.
- The PRD is only edited in docs-only PRs that add the matching `docs/changes/CHG-NNN.md` (CI: PRD guard). During an implementation task never edit the PRD: if the task needs a PRD change, stop and ask for a product decision.
- Supabase migrations follow expand/contract: a migration applied before its PR is merged must be backward-compatible with the code on `main` (additive only). Destructive steps (drop, rename, tighter constraints) go in a later migration, after the code that stops depending on the old shape is merged. Commit every applied migration to `supabase/migrations/` in the same PR. See ADR-0004.
