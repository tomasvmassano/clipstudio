"use client";

import { useParams } from "next/navigation";
import { RouteError } from "@/components/route-error";
import { clientPath } from "@/lib/ws-path";

/** Erros dentro de um cliente: volta ao Início desse cliente. */
export default function ClientError({ error, retry }: { error: unknown; retry: () => void }) {
  const params = useParams<{ ws: string }>();
  return <RouteError error={error} retry={retry} home={params?.ws ? clientPath(decodeURIComponent(params.ws)) : "/"} homeLabel="Voltar ao Início do cliente" />;
}
