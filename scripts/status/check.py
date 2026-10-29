#!/usr/bin/env python3
"""Registo de estado dos requisitos (CHG-004): docs/status.md.

  check.py                 valida o registo contra o PRD (CI)
  check.py --fix           reescreve o resumo e a lista de pendentes a partir das linhas
  check.py --seed A.tsv    cria/atualiza linhas a partir de um TSV (id, estado, falta, evidencia), mantendo as que já existem
  check.py --pr BASE HEAD  falha se o PR mexe na app (src/, supabase/migrations/) sem mexer no registo

Regras: cada ID do PRD aparece uma vez; estados válidos; "parcial" e "bloqueado" dizem o que falta;
"adiado" diz a decisão; IDs que saíram do PRD são assinalados. O resumo do topo é gerado (não se edita à mão).
"""
import os, re, subprocess, sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PRD = os.path.join(ROOT, "docs", "ClipStudio_PRD_Master_v2.1.md")
STATUS = os.path.join(ROOT, "docs", "status.md")
STATES = ["feito", "parcial", "por começar", "bloqueado", "adiado"]
BEGIN, END = "<!-- resumo:inicio -->", "<!-- resumo:fim -->"
ROW = re.compile(r"^\| (?P<id>[A-Z]{1,6}(?:-[0-9]{2})?-[0-9]{2,3}) \| (?P<estado>[^|]+?) \| (?P<falta>[^|]*?) \| (?P<evid>[^|]*?) \| (?P<verif>[^|]*?) \|$")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def prd_ids():
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "prd_ids.py"), PRD], capture_output=True, text=True, check=True).stdout
    ids = OrderedDict()
    for line in out.splitlines():
        i, p, s, t = (line.split("\t") + ["", "", ""])[:4]
        ids[i] = {"p": p, "s": s, "t": t}
    return ids


def read_rows(text):
    rows = OrderedDict()
    if BEGIN in text and END in text:  # o bloco gerado (resumo, pendentes) não conta como linhas do registo
        text = text.split(BEGIN)[0] + text.split(END, 1)[1]
    for line in text.splitlines():
        m = ROW.match(line.strip())
        if m:
            rows.setdefault(m["id"], []).append({k: m[k].strip() for k in ("estado", "falta", "evid", "verif")})
    return rows


def esc(s):
    return (s or "").replace("|", "/").replace("\n", " ").strip()


def render(ids, rows):
    """Reescreve o ficheiro inteiro: resumo gerado + uma tabela por secção do PRD, pela ordem do PRD."""
    head = []
    if os.path.exists(STATUS):
        txt = open(STATUS, encoding="utf-8").read()
        head = txt.split(BEGIN)[0].rstrip().splitlines() if BEGIN in txt else []
    if not head:
        head = ["# Registo de estado dos requisitos", "",
                "Fonte única do que está feito, parcial, por começar, bloqueado ou adiado (CHG-004). Uma linha por ID do PRD.",
                "Cada PR que mexe na app atualiza as linhas dos IDs que toca; o CI (`scripts/status/check.py`) valida contra o PRD.",
                "O resumo e os pendentes abertos são gerados: `python3 scripts/status/check.py --fix`. \"Verificado\" é a data da última verificação com conta real (R-15).",
                ]
    while head and not head[-1].strip():
        head.pop()
    head = head + [""]
    counts = OrderedDict((s, 0) for s in STATES)
    open_items = []
    for i, meta in ids.items():
        r = rows.get(i, [{"estado": "por começar", "falta": "", "evid": "", "verif": "—"}])[0]
        counts[r["estado"]] = counts.get(r["estado"], 0) + 1
        if r["estado"] in ("parcial", "bloqueado"):
            open_items.append((0 if r["estado"] == "bloqueado" else 1, {"P0": 0, "P1": 1, "P2": 2}.get(meta["p"], 3), i, meta, r))
    open_items.sort(key=lambda x: (x[0], x[1]))
    lines = head + [BEGIN, "", "## Resumo", "",
                    "| Estado | Requisitos |", "|---|---|"] + [f"| {s} | {n} |" for s, n in counts.items()] + [
                    f"| **total** | **{sum(counts.values())}** |", "",
                    "## Pendentes abertos (bloqueados primeiro, depois por prioridade)", "",
                    "| ID | P | Estado | O que falta | Título |", "|---|---|---|---|---|"]
    lines += [f"| {i} | {m['p'] or '—'} | {r['estado']} | {esc(r['falta'])} | {esc(m['t'])[:80]} |" for _, _, i, m, r in open_items]
    lines += ["", END, ""]
    section = None
    for i, meta in ids.items():
        if meta["s"] != section:
            section = meta["s"]
            lines += ["", f"## {section}", "", "| ID | Estado | O que falta | Evidência | Verificado |", "|---|---|---|---|---|"]
        r = rows.get(i, [{"estado": "por começar", "falta": "", "evid": "", "verif": "—"}])[0]
        lines.append(f"| {i} | {r['estado']} | {esc(r['falta'])} | {esc(r['evid'])} | {esc(r['verif']) or '—'} |")
    gone = [i for i in rows if i not in ids]
    if gone:
        lines += ["", "## Já não estão no PRD (rever e apagar)", "", "| ID | Estado | O que falta | Evidência | Verificado |", "|---|---|---|---|---|"]
        lines += [f"| {i} | {rows[i][0]['estado']} | {esc(rows[i][0]['falta'])} | {esc(rows[i][0]['evid'])} | {esc(rows[i][0]['verif'])} |" for i in gone]
    return "\n".join(lines) + "\n"


def validate(ids, text):
    rows, errs = read_rows(text), []
    for i in ids:
        if i not in rows:
            errs.append(f"{i}: está no PRD mas não no registo (corre --fix e preenche o estado)")
    for i, rs in rows.items():
        if len(rs) > 1:
            errs.append(f"{i}: aparece {len(rs)} vezes")
        r = rs[0]
        if r["estado"] not in STATES:
            errs.append(f"{i}: estado '{r['estado']}' inválido (usa: {', '.join(STATES)})")
        if r["estado"] in ("parcial", "bloqueado", "adiado") and not r["falta"]:
            errs.append(f"{i}: '{r['estado']}' sem dizer o que falta, de quem depende ou que decisão")
        if r["estado"] == "feito" and not r["evid"]:
            errs.append(f"{i}: 'feito' sem evidência (PR, teste ou ficheiro)")
        if i not in ids:
            errs.append(f"{i}: já não está no PRD (rever e apagar a linha)")
    if text != render(ids, rows):
        errs.append("resumo ou ordem desatualizados: corre `python3 scripts/status/check.py --fix`")
    return errs


def main(argv):
    ids = prd_ids()
    if len(argv) >= 3 and argv[0] == "--pr":
        files = subprocess.run(["git", "diff", "--name-only", argv[1], argv[2]], capture_output=True, text=True, cwd=ROOT).stdout.split()
        app = [f for f in files if f.startswith("src/") or f.startswith("supabase/migrations/")]
        if app and "docs/status.md" not in files:
            print("::error::Este PR mexe na app (" + ", ".join(app[:5]) + ("…" if len(app) > 5 else "") +
                  ") sem atualizar docs/status.md. Atualiza as linhas dos requisitos que tocaste (CHG-004).")
            return 1
        print("Registo de estado: PR consistente.")
        return 0
    if argv[:1] == ["--seed"]:
        rows = read_rows(open(STATUS, encoding="utf-8").read()) if os.path.exists(STATUS) else OrderedDict()
        for line in open(argv[1], encoding="utf-8").read().splitlines()[1:]:
            c = (line.split("\t") + ["", "", "", ""])[:4]
            if c[0] and c[0] not in rows:
                rows[c[0]] = [{"estado": c[1].strip(), "falta": c[2].strip(), "evid": c[3].strip(), "verif": "—"}]
        open(STATUS, "w", encoding="utf-8").write(render(ids, rows))
        print(f"Registo semeado: {len(rows)} linhas.")
        return 0
    if argv[:1] == ["--fix"]:
        rows = read_rows(open(STATUS, encoding="utf-8").read()) if os.path.exists(STATUS) else OrderedDict()
        open(STATUS, "w", encoding="utf-8").write(render(ids, rows))
        print("Resumo e pendentes atualizados.")
        return 0
    if not os.path.exists(STATUS):
        print("::error::Falta docs/status.md")
        return 1
    errs = validate(ids, open(STATUS, encoding="utf-8").read())
    for e in errs:
        print(f"::error::{e}")
    if not errs:
        print(f"Registo de estado: OK ({len(ids)} requisitos).")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
