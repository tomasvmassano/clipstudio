"use client";

import { ChevronLeftIcon, ChevronRightIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import { addDays, dayLabel, niceDate } from "@/lib/data";

export function DayNav({ date, onChange }: { date: string; onChange: (d: string) => void }) {
  return (
    <div className="flex items-center gap-1">
      <Button size="icon-sm" variant="outline" aria-label="Dia anterior" onClick={() => onChange(addDays(date, -1))}>
        <ChevronLeftIcon />
      </Button>
      <div className="min-w-[10rem] text-center leading-tight">
        <div className="font-semibold">{dayLabel(date)}</div>
        <div className="text-xs text-muted-foreground">{niceDate(date)} · Dubai</div>
      </div>
      <Button size="icon-sm" variant="outline" aria-label="Dia seguinte" onClick={() => onChange(addDays(date, 1))}>
        <ChevronRightIcon />
      </Button>
    </div>
  );
}
