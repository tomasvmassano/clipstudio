import { Suspense } from "react";
import { ProfilePage } from "@/components/profile-page";

export default function Page() {
  return <Suspense><ProfilePage /></Suspense>;
}
