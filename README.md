# Estúdio Numeiro (clipstudio)

App Next.js 16 + Tailwind 4 + shadcn/ui, com os blocos `@efferd/app-shell-5` (shell com sidebar, header, pesquisa, tema) e `@efferd/dashboard-5` (cartões e gráficos). É o design system de todas as páginas: componentes em `src/components/ui`, tokens em `src/app/globals.css`, navegação em `src/components/app-shared.tsx`.

Rotas: `/` Hoje · `/desempenho` dashboard (dados de exemplo até à ligação ao Supabase) · `/legacy/index.html` a página de guiões e teleprompter de hoje (estática, com os 30 guiões dentro).

Adicionar componentes: `npx shadcn@latest add <nome>` ou `npx shadcn@latest add @efferd/<bloco>`.

Publicar um dia novo na página estática:

```
python scripts/seed_from_engine.py data/guioes-AAAA-MM-DD.json AAAA-MM-DD /tmp/docs/scripts
python scripts/make_snapshot.py /tmp/docs/scripts
git commit -am "guiões AAAA-MM-DD" && git push      # o Vercel publica sozinho
```

Desenvolvimento: `npm run dev`. Deploy: Vercel, preset Next.js, sem variáveis por agora.
