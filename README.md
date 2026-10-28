# Estúdio Numeiro

Página estática com os guiões do dia e o teleprompter. `index.html` é a app inteira.

- `data/guioes-AAAA-MM-DD.json`: os guiões do dia, no formato do motor (`numeiro-engine`).
- `seed_from_engine.py`: converte esse JSON em documentos (um por guião).
- `make_snapshot.py`: mete os documentos dentro de `index.html`, para a página funcionar sem base de dados.

Publicar um dia novo:

```
python seed_from_engine.py data/guioes-2026-10-29.json 2026-10-29 /tmp/docs/scripts
python make_snapshot.py /tmp/docs/scripts
git commit -am "guiões 2026-10-29" && git push      # o Vercel publica sozinho
```

No Vercel: Framework preset "Other", sem build. A versão no claude.ai (com validação pelo Numeiro) usa a base de dados do artifact; esta versão no Vercel é só de leitura, com o teleprompter.
