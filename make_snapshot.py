"""Mete os guiões de um dia dentro da página (para quem abre o link sem sessão).
Uso: python make_snapshot.py <pasta com os .json dos documentos>"""
import json,os,re,sys,pathlib
d=sys.argv[1]; docs=[]
for f in sorted(os.listdir(d)):
    x=json.load(open(os.path.join(d,f))); x["id"]=f[:-5]; docs.append(x)
p=pathlib.Path(__file__).with_name("index.html"); s=p.read_text()
snap=json.dumps(docs,ensure_ascii=False).replace("</","<\\/")
s=re.sub(r'<script id="snapshot" type="application/json">.*?</script>', lambda m: f'<script id="snapshot" type="application/json">{snap}</script>', s, count=1, flags=re.S)
p.write_text(s); print(len(docs),"guiões no snapshot")
