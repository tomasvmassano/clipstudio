"use client";

import Link from "next/link";
import type { ComponentProps } from "react";
import { useSession } from "@/components/session-provider";
import { clientPath } from "@/lib/ws-path";

/** Link para uma página do cliente aberto: href="/guioes" vira /c/<cliente>/guioes. */
export function WsLink({ href, ...props }: Omit<ComponentProps<typeof Link>, "href"> & { href: string }) {
  const { ws } = useSession();
  return <Link href={ws ? clientPath(ws.id, href) : href} {...props} />;
}

/** O mesmo, para quem precisa só da string (ex.: render={<a href=…/>}). */
export function useWsHref() {
  const { ws } = useSession();
  return (sub: string) => (ws ? clientPath(ws.id, sub) : sub);
}
