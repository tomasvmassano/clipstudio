"use client";

import { catchError, type ErrorInfo } from "next/error";
import { RotateCwIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

/** Um widget que rebenta mostra o seu próprio erro e não leva a página consigo (ADR-0019). */
function WidgetFallback(props: { label: string; className?: string }, { error, retry }: ErrorInfo) {
  console.error("[clipstudio] widget", props.label, error);
  return (
    <Card className={`shadow-none dark:ring-0 ${props.className ?? ""}`} role="alert">
      <CardContent className="flex flex-col items-start gap-2 text-sm">
        <span><b>{props.label}</b> não carregou.</span>
        <Button size="sm" variant="outline" onClick={() => retry()}><RotateCwIcon /> Tentar de novo</Button>
      </CardContent>
    </Card>
  );
}

export const WidgetBoundary = catchError(WidgetFallback);
