import { supabase } from "@/lib/supabase";
import { createChannelHub } from "@/lib/realtime-hub";

type Ch = ReturnType<ReturnType<typeof supabase>["channel"]>;
/** Único sítio da app que abre canais (ver realtime-hub.ts). */
export const realtime = createChannelHub<Ch>((ch) => { void supabase().removeChannel(ch); });
