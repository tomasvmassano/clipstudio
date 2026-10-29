import { ToClient } from "@/components/to-client";

/** Rota sem cliente: abre a mesma página dentro do último cliente (ADR-0018). */
export default function Legacy() {
  return <ToClient sub="/edicao" />;
}
