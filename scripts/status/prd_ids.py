#!/usr/bin/env python3
"""Lista os requisitos com ID definidos no PRD (CHG-004). Uso: prd_ids.py [PRD.md] -> TSV: id, prioridade, secção, título."""
import re, sys

PRD = sys.argv[1] if len(sys.argv) > 1 else "docs/ClipStudio_PRD_Master_v2.1.md"
DEF = [
    re.compile(r"^\*\*(?P<id>[A-Z]{2,6}(?:-[0-9]{2})?-[0-9]{2,3})\b\s*(?:\[(?P<p>P[0-3])\])?[^*]*\*\*\s*(?P<t>.*)"),
    re.compile(r"^- \*\*(?P<id>[A-Z]{2,6}(?:-[0-9]{2})?-[0-9]{2,3})\b\s*(?:\[(?P<p>P[0-3])\])?[^*]*\*\*\s*(?P<t>.*)"),
    re.compile(r"^\*\*(?P<id>R-[0-9]{2})\b[^*]*\*\*\s*(?P<t>.*)"),
    re.compile(r"^(?P<id>R-[0-9]{2})\b[^.]*\.\s*(?P<t>.*)"),
    re.compile(r"^\| (?P<id>(?:QA|[A-Z]{2,6})-[0-9]{2,3})(?: \([^)]*\))? \| (?P<t>[^|]*)\|"),
]
seen, section = {}, ""
for line in open(PRD, encoding="utf-8"):
    if line.startswith("## ") or line.startswith("### "):
        section = line.strip("# \n")[:60]
    for rx in DEF:
        m = rx.match(line)
        if m and m.group("id") not in seen and not m.group("id").startswith("CHG-"):
            gd = m.groupdict()
            title = re.sub(r"\*\*|`", "", gd.get("t") or "").strip()
            title = re.split(r"(?<=\.)\s", title, maxsplit=1)[0][:110]
            head = re.sub(r"^\*\*[^*]+\*\*\s*", "", line)  # título pode estar dentro do negrito
            inner = re.match(r"^\*\*[^\]]*\]?\s*[—-]?\s*([^*]*)\*\*", line.lstrip("- "))
            if inner and inner.group(1).strip(" .—-"):
                title = inner.group(1).strip(" .—-")[:110]
            seen[gd["id"]] = (gd.get("p") or "", section, title)
            break
for k, (p, s, t) in seen.items():
    print(f"{k}\t{p}\t{s}\t{t}")
