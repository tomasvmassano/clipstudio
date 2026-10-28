export default function Hoje() {
  const stages = [
    { label: "Ideias", value: "novas" },
    { label: "Guiões", value: "30 / 30" },
    { label: "Gravados", value: "0 / 30" },
    { label: "Edição (v1)", value: "—", later: true },
    { label: "Revisão (v1)", value: "—", later: true },
  ];
  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Hoje</h1>
          <p className="text-sm text-muted-foreground">Quarta, 28 out · hora de Dubai</p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        {stages.map((s) => (
          <div key={s.label} className={`rounded-lg border bg-background p-4 ${s.later ? "border-dashed opacity-70" : ""}`}>
            <div className="text-xs text-muted-foreground">{s.label}</div>
            <div className="mt-1 text-lg font-semibold tabular-nums">{s.value}</div>
          </div>
        ))}
      </div>
      <div className="grid gap-4 md:grid-cols-2">
        <section className="rounded-lg border bg-background p-4">
          <h2 className="font-medium">Execução de hoje</h2>
          <p className="mt-2 text-sm text-muted-foreground">Os guiões de hoje estão na página de guiões. A execução automática entra com a ligação ao motor.</p>
          <a href="/legacy/index.html" className="mt-3 inline-block text-sm underline underline-offset-4">Abrir os guiões e o teleprompter de hoje</a>
        </section>
        <section className="rounded-lg border bg-background p-4">
          <h2 className="font-medium">O que pede atenção</h2>
          <ul className="mt-2 space-y-1 text-sm text-muted-foreground">
            <li>Guiões que o Numeiro rejeitou</li>
            <li>Ideias novas por aprovar</li>
            <li>Citações por verificar</li>
          </ul>
        </section>
      </div>
    </div>
  );
}
