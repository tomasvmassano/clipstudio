# CLAUDE.md

Read and follow these at the start of every implementation task, before touching code:

@AGENTS.md

Product source of truth: `docs/ClipStudio_PRD_Master_v2.1.md`. It is long, so read the sections whose requirement IDs the task touches (grep the FR/R/NFR IDs) rather than loading it whole, and always re-read sections 2, 3, 22, 30 and 33 when a change affects auth, tenancy, permissions or a new capability.

If a request conflicts with the PRD or AGENTS.md, stop and ask for a product decision. End every task with the reporting template in AGENTS.md section 13.
