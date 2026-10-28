import { Dashboard } from "@/components/dashboard";

export default function Desempenho() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">Desempenho</h1>
        <p className="text-sm text-muted-foreground">
          Bloco de demonstração com dados de exemplo. Os números reais do @itsnumeiro entram quando a app ficar ligada ao Supabase.
        </p>
      </div>
      <Dashboard />
    </div>
  );
}
