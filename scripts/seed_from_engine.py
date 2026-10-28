"""Converte o JSON de guiões (motor ou agente) em documentos da coleção `scripts` da app.

Uso: python seed_from_engine.py day1_scripts.json 2026-10-28 out_dir
Cada documento: scripts/<data>-<nn>.json
"""
import json
import pathlib
import sys

src, date, out = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)
items = json.loads(pathlib.Path(src).read_text())
for i, s in enumerate(items, 1):
    hooks = [{"text": (h.get("text") or h.get("hook") or "").strip(), "mecanismo": h.get("mecanismo", "")}
             for h in s.get("hooks", [])][:3]
    doc = {"date": date, "n": s.get("n", i), "formato": s.get("formato", ""), "tema": s.get("tema", ""),
           "hooks": hooks, "corpo": (s.get("corpo") or "").strip(), "status": "aprovado", "gravado": False,
           "critic_score": s.get("critic_score"), "fonte": s.get("fonte", ""), "legenda": s.get("legenda", ""),
           "comentario_fixado": s.get("comentario_fixado", ""), "history": [], "origem": s.get("origem", "motor")}
    (out / f"{date}-{doc['n']:02d}.json").write_text(json.dumps(doc, ensure_ascii=False))
print(len(items), "documentos em", out)
