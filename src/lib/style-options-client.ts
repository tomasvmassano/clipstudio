"use client";

import { useEffect, useState } from "react";
import type { Access } from "./access";
import { fetchCatalog } from "./edit-styles";
import { CAP_STYLES } from "./caption-plan";
import { styleOptions, type StyleOption } from "./style-options";

/** Lê o catálogo do cliente uma vez e devolve as opções de estilo (W10-41). Sem catálogo, os estilos do motor e o erro. */
export function useStyleOptions(access: Access, current?: string | null): { options: StyleOption[]; error: string; loading: boolean } {
  const [cat, setCat] = useState<{ key: string; name: string; status: string }[] | null | undefined>(undefined);
  const [error, setError] = useState("");
  useEffect(() => {
    let alive = true;
    fetchCatalog(access)
      .then((c) => { if (alive) { setCat(c.styles); setError(""); } })
      .catch((e: Error) => { if (alive) { setCat(null); setError(e.message); } });
    return () => { alive = false; };
  }, [access]);
  // a carregar: só o estilo atual, para o <select> não piscar com a lista de recurso
  if (cat === undefined) return { options: current ? [{ id: current, label: current }] : [], error: "", loading: true };
  return { options: styleOptions(CAP_STYLES, cat, current), error, loading: false };
}

/** O motor já desenha este estilo? (aparece no editor quando ativo) */
export const isRenderable = (key: string) => Object.hasOwn(CAP_STYLES, key);
