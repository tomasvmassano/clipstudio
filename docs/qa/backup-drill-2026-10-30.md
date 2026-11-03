# Ensaio de backup e restauro (QA-15), 2026-10-30

Gerado por `scripts/backup/drill.sh` (ADR-0042) numa instância Postgres descartável com `scripts/db/bootstrap.sql`, todas as migrações, o seed de teste e atividade de amostra em dois clientes (`bk_a`, `bk_b`) feita pelas RPCs. **Não é produção**: os tempos medem este ensaio e servem para comparar execuções, não para prometer o RTO de produção (ver `docs/runbooks/restauro.md`).

**Resultado:** tudo verificado.

## Ambiente

- Postgres do servidor 16, pg_dump 16; 84 migrações; 200 guiões por cliente na amostra (fontes e tarefas: metade), escritos pelas RPCs; 1000000 linhas extra de auditoria sintética só para volume.
- Base de origem: 412.98 MB; `public.dump` 35.00 MB; `platform.dump` 0.02 MB; export de `bk_a` 135.90 MB.

## Tempos

| Fase | Segundos |
|---|---:|
| Preparar a origem (migrações, seed, atividade; fora do RTO) | 32.62 |
| Backup (`pg_dump` public + plataforma + publicação) | 8.07 |
| Manifesto (checksums e catálogo da origem) | 17.47 |
| Restauro completo para base nova | 13.33 |
| Verificação (checksums, catálogo, RPCs) | 12.39 |
| **RTO do ensaio** (backup + restauro + verificação) | **33.79** |
| Export de um cliente (`bk_a`) | 12.44 |
| Restauro desse cliente para base nova | 9.77 |

## Restauro completo

- Tabelas comparadas: 90 (1006237 linhas); diferentes: 0.
- RPCs depois do restauro: `RESULT ok=18 fail=0`.

Catálogo (origem → restauro):

| Categoria | Objetos | Diferenças |
|---|---:|---:|
| constraint | 546 | 0 |
| cron | 2 | 0 |
| default_acl | 3 | 0 |
| extension | 4 | 0 |
| function | 350 | 0 |
| index | 199 | 0 |
| policy | 47 | 0 |
| publication | 1 | 0 |
| rls | 90 | 0 |
| schema | 6 | 0 |
| sequence | 23 | 0 |
| table | 90 | 0 |
| trigger | 57 | 0 |
| view | 6 | 0 |

Verificações de funcionamento e isolamento (`scripts/backup/verify_rpc.sql`):

- PASS A a forçar o cliente B na pesquisa: 42501
- PASS A encontra o termo de A
- PASS A não cria tarefas em B: 42501
- PASS B encontra o termo de B
- PASS B não encontra o termo exclusivo de A
- PASS QA-12: A não encontra o termo exclusivo de B
- PASS anónimo sem acesso às tabelas
- PASS capacidade desconhecida recusada
- PASS cliente A não lê B
- PASS cliente A restaurado
- PASS cliente B restaurado
- PASS escrever depois do restauro: id novo acima do máximo restaurado
- PASS fluxo editorial depois do restauro
- PASS guiões de A restaurados
- PASS my_context de A só lista A
- PASS staff A lê A
- PASS staff A não lê B
- PASS tabela de acessos fechada à API depois do restauro (42501)

<details><summary>Contagem e checksum por tabela</summary>

| Tabela | Linhas | md5 (origem) | Igual |
|---|---:|---|:---:|
| accounts | 7 | `12d5c8340a85` | sim |
| agency_costs | 0 | `-` | sim |
| agency_memberships | 2 | `5e9014ad582a` | sim |
| agent_config_versions | 1 | `24b3aff588b2` | sim |
| agent_definitions | 13 | `b1606ac1453d` | sim |
| agent_job_attempts | 0 | `-` | sim |
| agent_job_outputs | 0 | `-` | sim |
| agent_jobs | 0 | `-` | sim |
| agent_log | 0 | `-` | sim |
| agent_models | 3 | `81e8b8ce424f` | sim |
| agent_tool_prices | 1 | `5153f81e0411` | sim |
| agent_workers | 0 | `-` | sim |
| audit_events | 1001300 | `813a2c1d0c30` | sim |
| auth.mfa_factors | 0 | `-` | sim |
| auth.users | 4 | `abbf937dd624` | sim |
| biz_metrics | 16 | `1b37c10f77fd` | sim |
| capabilities | 68 | `42be3476ec00` | sim |
| client_contracts | 0 | `-` | sim |
| clients | 3 | `bc311f9b76ce` | sim |
| comment_analysis | 0 | `-` | sim |
| content_briefs | 0 | `-` | sim |
| content_bulk_ops | 0 | `-` | sim |
| content_checklist | 0 | `-` | sim |
| content_comments | 0 | `-` | sim |
| content_sources | 0 | `-` | sim |
| content_transition_reasons | 0 | `-` | sim |
| content_transitions | 730 | `12da1ca90655` | sim |
| content_versions | 430 | `275068bde871` | sim |
| cron.job | 2 | `0acfc5320d47` | sim |
| daily_reports | 0 | `-` | sim |
| dashboard_layouts | 0 | `-` | sim |
| dashboard_widgets | 17 | `19d00f40337d` | sim |
| domain_events | 1130 | `2d8cadbdfb6b` | sim |
| edit_presets | 1 | `1e27aeca6d84` | sim |
| edit_style_versions | 13 | `af5f1124ff32` | sim |
| edit_styles | 13 | `9644c26fc6a7` | sim |
| feature_flag_defs | 12 | `9332fbe5d47d` | sim |
| feature_flags | 2 | `279800448642` | sim |
| fx_rates | 0 | `-` | sim |
| generated | 0 | `-` | sim |
| guioes | 430 | `ecbc7615ecdb` | sim |
| ideas | 214 | `1cbbce413f88` | sim |
| inbox_item_states | 0 | `-` | sim |
| invitations | 1 | `907b2aa9fbf5` | sim |
| learn_experiments | 0 | `-` | sim |
| learn_repeat_links | 0 | `-` | sim |
| member_availability | 0 | `-` | sim |
| member_presence | 0 | `-` | sim |
| meta | 0 | `-` | sim |
| notifications | 0 | `-` | sim |
| organizations | 1 | `68eec40923d5` | sim |
| perf_accounts | 1 | `59fa43da8535` | sim |
| perf_readings | 363 | `8b49962d0306` | sim |
| permission_grants | 0 | `-` | sim |
| privacy_requests | 0 | `-` | sim |
| profiles | 2 | `2a7e0d36cd2d` | sim |
| projects | 0 | `-` | sim |
| pub_approval_policies | 0 | `-` | sim |
| pub_approvals | 0 | `-` | sim |
| pub_platform_limits | 3 | `d5591e8fb6b7` | sim |
| pub_publications | 0 | `-` | sim |
| pub_variants | 0 | `-` | sim |
| publicacoes | 0 | `-` | sim |
| publication_lineage | 0 | `-` | sim |
| quotes | 0 | `-` | sim |
| realtime.messages | 200 | `64cd8c4b4ea4` | sim |
| recording_marks | 0 | `-` | sim |
| recording_session_items | 0 | `-` | sim |
| recording_sessions | 0 | `-` | sim |
| reel_themes | 0 | `-` | sim |
| reels | 148 | `0b6fa74cafba` | sim |
| reference_items | 0 | `-` | sim |
| reference_links | 0 | `-` | sim |
| rework_reasons | 0 | `-` | sim |
| role_capabilities | 230 | `521262e4a0ea` | sim |
| script_analysis | 60 | `2165018893ee` | sim |
| social_accounts | 1 | `f605253b5776` | sim |
| storage.buckets | 2 | `4cb54eec13c9` | sim |
| storage.objects | 4 | `a097ed8dc584` | sim |
| studio_tokens | 1 | `6617fdcbe363` | sim |
| takes | 0 | `-` | sim |
| task_comments | 200 | `2c7b4dd632e4` | sim |
| task_dependencies | 0 | `-` | sim |
| task_events | 400 | `9490395fb6a6` | sim |
| task_rules | 0 | `-` | sim |
| task_templates | 0 | `-` | sim |
| tasks | 200 | `7312365e64a6` | sim |
| teleprompter_prefs | 0 | `-` | sim |
| themes | 5 | `5f0a0d764ce0` | sim |
| workspace_access | 3 | `71bd273b3019` | sim |

</details>

## Restauro de um só cliente (`bk_a`)

- Tabelas exportadas: 89 (502830 linhas); diferentes depois do restauro: 0.
- Chaves estrangeiras, índices, triggers e políticas recriados depois da carga: sim (o export é referencialmente completo).
- Catálogo igual ao da origem (sem sequências e cron): sim.
- Marcas de outros clientes no export (`bk_b`, termo exclusivo de B, email de B, `numeiro`): nenhuma.
- RPCs no restauro parcial: `RESULT ok=18 fail=0`.

- PASS A a forçar o cliente B na pesquisa: 42501
- PASS A encontra o termo de A
- PASS A não cria tarefas em B: 42501
- PASS QA-12: A não encontra o termo exclusivo de B
- PASS anónimo sem acesso às tabelas
- PASS capacidade desconhecida recusada
- PASS cliente A não lê B
- PASS cliente A restaurado
- PASS escrever depois do restauro: id novo acima do máximo restaurado
- PASS fluxo editorial depois do restauro
- PASS guiões de A restaurados
- PASS my_context de A só lista A
- PASS restauro parcial: cliente B ausente
- PASS restauro parcial: nenhuma linha de outro cliente
- PASS restauro parcial: pessoa de B ausente
- PASS staff A lê A
- PASS staff A não lê B
- PASS tabela de acessos fechada à API depois do restauro (42501)

## JSON

```json
{
  "qa": "QA-15",
  "date_utc": "2026-10-30T09:08:52Z",
  "ok": true,
  "problems": [],
  "environment": {
    "server_major": 16,
    "pg_dump_major": 16,
    "migrations": 84,
    "sample_rows_per_client": 200,
    "bulk_audit_rows": 1000000
  },
  "sizes_bytes": {
    "database": 433044503,
    "public_dump": 36695649,
    "platform_dump": 24914,
    "workspace_export": 142496486
  },
  "timings_s": {
    "prepare_not_in_rto": 32.62,
    "dump": 8.07,
    "manifest": 17.47,
    "restore": 13.33,
    "verify": 12.39,
    "rto_dump_restore_verify": 33.79,
    "workspace_export": 12.44,
    "workspace_restore": 9.77
  },
  "full_restore": {
    "tables": 90,
    "rows": 1006237,
    "table_mismatches": [],
    "catalog_objects": {
      "constraint": 546,
      "cron": 2,
      "default_acl": 3,
      "extension": 4,
      "function": 350,
      "index": 199,
      "policy": 47,
      "publication": 1,
      "rls": 90,
      "schema": 6,
      "sequence": 23,
      "table": 90,
      "trigger": 57,
      "view": 6
    },
    "catalog_differences": {},
    "rpc": "RESULT ok=18 fail=0"
  },
  "workspace_restore": {
    "workspace": "bk_a",
    "tables": 89,
    "rows": 502830,
    "table_mismatches": [],
    "catalog_differences": 0,
    "foreign_keys_ok": true,
    "leak_files": [],
    "rpc": "RESULT ok=18 fail=0"
  }
}
```
