import { Suspense } from "react";
import { InvitePage } from "@/components/invite-page";

export const metadata = { title: "Convite · ClipStudio", referrer: "no-referrer" };

export default function ConvitePage() {
  return <Suspense><InvitePage /></Suspense>;
}
