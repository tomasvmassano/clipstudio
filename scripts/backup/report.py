#!/usr/bin/env python3
"""scripts/backup/report.py: relatório do ensaio de backup (QA-15), chamado por scripts/backup/drill.sh.

Lê os ficheiros da pasta de trabalho (WORK) e as variáveis de ambiente que o drill exporta, escreve o relatório
Markdown (com o JSON do resultado no fim) no caminho dado (ou não escreve se for "-") e imprime um resumo curto.
"""
import collections
import datetime
import json
import os
import sys

E = os.environ
W = E["WORK"]


def lines(name):
    path = os.path.join(W, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.rstrip("\n") for l in f if l.strip()]


def checksums(name):
    out = {}
    for l in lines(name):
        tbl, rows, md5 = l.split("|")
        out[tbl] = (int(rows), md5)
    return out


def size(name):
    p = os.path.join(W, name)
    return os.path.getsize(p) if os.path.exists(p) else 0


def mb(n):
    return f"{n / 1048576:.2f} MB"


src, dst = checksums("src.checksums"), checksums("dst.checksums")
src_ws, part_ws = checksums("src_ws.checksums"), checksums("part_ws.checksums")
fp_src = lines("src.fingerprint")
fp_cat = collections.Counter(l.split("|", 1)[0] for l in fp_src)
fp_diff = [l for l in lines("fingerprint.diff") if l[:1] in "<>"]
fp_diff_cat = collections.Counter(l[2:].split("|", 1)[0] for l in fp_diff)
part_fp_diff = [l for l in lines("part_fp.diff") if l[:1] in "<>"]
mismatch = sorted(t for t in set(src) | set(dst) if src.get(t) != dst.get(t))
part_mismatch = sorted(t for t in set(src_ws) | set(part_ws) if src_ws.get(t) != part_ws.get(t))
rpc = lines("rpc.txt")
part_rpc = lines("part_rpc.txt")
problems = [p for p in E.get("PROBLEMS", "").split("\n") if p]
ok = E["fail"] == "0"
now = datetime.datetime.now(datetime.timezone.utc)

result = {
    "qa": "QA-15",
    "date_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "ok": ok,
    "problems": problems,
    "environment": {"server_major": int(E["srv_major"]), "pg_dump_major": int(E["dump_major"]),
                    "migrations": int(E["migrations"]), "sample_rows_per_client": int(E["DRILL_ROWS"]),
                    "bulk_audit_rows": int(E.get("DRILL_BULK", "0"))},
    "sizes_bytes": {"database": int(E["db_bytes"]), "public_dump": size("public.dump"),
                    "platform_dump": size("platform.dump"), "workspace_export": int(E["ws_bytes"])},
    "timings_s": {"prepare_not_in_rto": float(E["t_prepare"]), "dump": float(E["t_dump"]),
                  "manifest": float(E["t_manifest"]), "restore": float(E["t_restore"]),
                  "verify": float(E["t_verify"]), "rto_dump_restore_verify": float(E["rto"]),
                  "workspace_export": float(E["t_export"]), "workspace_restore": float(E["t_part_restore"])},
    "full_restore": {"tables": len(src), "rows": sum(r for r, _ in src.values()),
                     "table_mismatches": mismatch, "catalog_objects": dict(sorted(fp_cat.items())),
                     "catalog_differences": dict(sorted(fp_diff_cat.items())), "rpc": E.get("rpc_res", "")},
    "workspace_restore": {"workspace": E["WS"], "tables": len(src_ws), "rows": sum(r for r, _ in src_ws.values()),
                          "table_mismatches": part_mismatch, "catalog_differences": len(part_fp_diff),
                          "foreign_keys_ok": E["part_post_ok"] == "1",
                          "leak_files": E.get("leaks", "").split(), "rpc": E.get("part_rpc_res", "")},
}

summary = (f"QA-15 {'OK' if ok else 'FALHOU'}: {len(src)} tabelas, {result['full_restore']['rows']} linhas, "
           f"{sum(fp_cat.values())} objetos de catálogo, {len(mismatch)} tabelas e {len(fp_diff)} objetos diferentes; "
           f"RPCs {E.get('rpc_res', '?')}; RTO do ensaio {E['rto']} s "
           f"(dump {E['t_dump']} + restauro {E['t_restore']} + verificação {E['t_verify']}); "
           f"parcial {E['WS']}: {len(src_ws)} tabelas, {result['workspace_restore']['rows']} linhas, "
           f"{len(part_mismatch)} diferentes, fugas: {E.get('leaks') or 'nenhuma'}.")

out = sys.argv[1] if len(sys.argv) > 1 else "-"
if out != "-":
    md = []
    a = md.append
    a(f"# Ensaio de backup e restauro (QA-15), {now:%Y-%m-%d}")
    a("")
    a("Gerado por `scripts/backup/drill.sh` (ADR-0042) numa instância Postgres descartável com `scripts/db/bootstrap.sql`, "
      "todas as migrações, o seed de teste e atividade de amostra em dois clientes (`bk_a`, `bk_b`) feita pelas RPCs. "
      "**Não é produção**: os tempos medem este ensaio e servem para comparar execuções, não para prometer o RTO de produção "
      "(ver `docs/runbooks/restauro.md`).")
    a("")
    a(f"**Resultado:** {'tudo verificado' if ok else 'HÁ FALHAS'}.")
    for p in problems:
        a(f"- {p}")
    a("")
    a("## Ambiente")
    a("")
    a(f"- Postgres do servidor {E['srv_major']}, pg_dump {E['dump_major']}; {E['migrations']} migrações; "
      f"{E['DRILL_ROWS']} guiões por cliente na amostra (fontes e tarefas: metade), escritos pelas RPCs; "
      f"{E.get('DRILL_BULK', '0')} linhas extra de auditoria sintética só para volume.")
    a(f"- Base de origem: {mb(int(E['db_bytes']))}; `public.dump` {mb(size('public.dump'))}; "
      f"`platform.dump` {mb(size('platform.dump'))}; export de `{E['WS']}` {mb(int(E['ws_bytes']))}.")
    a("")
    a("## Tempos")
    a("")
    a("| Fase | Segundos |")
    a("|---|---:|")
    a(f"| Preparar a origem (migrações, seed, atividade; fora do RTO) | {E['t_prepare']} |")
    a(f"| Backup (`pg_dump` public + plataforma + publicação) | {E['t_dump']} |")
    a(f"| Manifesto (checksums e catálogo da origem) | {E['t_manifest']} |")
    a(f"| Restauro completo para base nova | {E['t_restore']} |")
    a(f"| Verificação (checksums, catálogo, RPCs) | {E['t_verify']} |")
    a(f"| **RTO do ensaio** (backup + restauro + verificação) | **{E['rto']}** |")
    a(f"| Export de um cliente (`{E['WS']}`) | {E['t_export']} |")
    a(f"| Restauro desse cliente para base nova | {E['t_part_restore']} |")
    a("")
    a("## Restauro completo")
    a("")
    a(f"- Tabelas comparadas: {len(src)} ({result['full_restore']['rows']} linhas); diferentes: {len(mismatch)}"
      + (f" ({', '.join(mismatch)})" if mismatch else "") + ".")
    a(f"- RPCs depois do restauro: `{E.get('rpc_res', '')}`.")
    a("")
    a("Catálogo (origem → restauro):")
    a("")
    a("| Categoria | Objetos | Diferenças |")
    a("|---|---:|---:|")
    for k, v in sorted(fp_cat.items()):
        a(f"| {k} | {v} | {fp_diff_cat.get(k, 0)} |")
    a("")
    a("Verificações de funcionamento e isolamento (`scripts/backup/verify_rpc.sql`):")
    a("")
    for l in rpc:
        a(f"- {l}")
    a("")
    a("<details><summary>Contagem e checksum por tabela</summary>")
    a("")
    a("| Tabela | Linhas | md5 (origem) | Igual |")
    a("|---|---:|---|:---:|")
    for t in sorted(src):
        r, m = src[t]
        a(f"| {t} | {r} | `{m[:12]}` | {'sim' if dst.get(t) == src[t] else '**não**'} |")
    a("")
    a("</details>")
    a("")
    a(f"## Restauro de um só cliente (`{E['WS']}`)")
    a("")
    a(f"- Tabelas exportadas: {len(src_ws)} ({result['workspace_restore']['rows']} linhas); diferentes depois do restauro: "
      f"{len(part_mismatch)}" + (f" ({', '.join(part_mismatch)})" if part_mismatch else "") + ".")
    a(f"- Chaves estrangeiras, índices, triggers e políticas recriados depois da carga: "
      f"{'sim (o export é referencialmente completo)' if E['part_post_ok'] == '1' else '**não**'}.")
    a(f"- Catálogo igual ao da origem (sem sequências e cron): {'sim' if not part_fp_diff else f'**não** ({len(part_fp_diff)})'}.")
    a(f"- Marcas de outros clientes no export (`bk_b`, termo exclusivo de B, email de B, `numeiro`): "
      f"{E.get('leaks') or 'nenhuma'}.")
    a(f"- RPCs no restauro parcial: `{E.get('part_rpc_res', '')}`.")
    a("")
    for l in part_rpc:
        a(f"- {l}")
    a("")
    a("## JSON")
    a("")
    a("```json")
    a(json.dumps(result, ensure_ascii=False, indent=2))
    a("```")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
with open(os.path.join(W, "result.json"), "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
print(summary)
