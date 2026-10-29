"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

/** O painel da agência passou para a entrada da app (/). */
export default function AgenciaLegacy() {
  const router = useRouter();
  useEffect(() => { router.replace("/"); }, [router]);
  return null;
}
