"use client";

import { RouteError } from "@/components/route-error";

/** Erros nas páginas da agência e nas restantes rotas: a moldura (menu, topo) continua de pé. */
export default function AppError({ error, retry }: { error: unknown; retry: () => void }) {
  return <RouteError error={error} retry={retry} />;
}
