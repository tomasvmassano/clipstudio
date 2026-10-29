"use client";

import { useEffect } from "react";

/** Último recurso, quando até a moldura da app rebenta (ADR-0019). Sem estilos da app: tudo inline, tema escuro. */
export default function GlobalError({ error, retry }: { error: unknown; retry: () => void }) {
  useEffect(() => { console.error("[clipstudio] erro global", error); }, [error]);
  return (
    <html lang="pt">
      <body style={{ margin: 0, minHeight: "100vh", display: "grid", placeItems: "center", background: "#0a0a0a", color: "#fafafa", fontFamily: "system-ui, sans-serif" }}>
        <title>ClipStudio</title>
        <main style={{ maxWidth: 420, padding: 24 }}>
          <h1 style={{ fontSize: 20, margin: "0 0 8px" }}>A app não carregou</h1>
          <p style={{ color: "#a1a1aa", margin: "0 0 16px", lineHeight: 1.5 }}>Algo correu mal do nosso lado; nada do que fizeste se perdeu. Tenta de novo ou volta ao início.</p>
          <div style={{ display: "flex", gap: 8 }}>
            <button onClick={() => retry()} style={{ padding: "8px 14px", borderRadius: 8, border: 0, background: "#fafafa", color: "#0a0a0a", cursor: "pointer" }}>Tentar de novo</button>
            {/* eslint-disable-next-line @next/next/no-html-link-for-pages -- a app está partida: recarregar de raiz de propósito */}
            <a href="/" style={{ padding: "8px 14px", borderRadius: 8, border: "1px solid #3f3f46", color: "#fafafa", textDecoration: "none" }}>Voltar ao início</a>
          </div>
        </main>
      </body>
    </html>
  );
}
