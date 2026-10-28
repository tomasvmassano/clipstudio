import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

export type Member = {
  user_id: string; email: string; affiliation: "agency_staff" | "client_staff"; role: string;
  job_title: string | null; status: string; expires_at: string | null; since: string;
};
export type Invitation = { id: string; email: string; affiliation: "agency_staff" | "client_staff"; role: string; expires_at: string; created_at: string };
export type Team = { members: Member[]; invitations: Invitation[]; can_invite: boolean; can_invite_agency: boolean };

/** Papéis que se podem convidar, do mais baixo ao mais alto (o servidor recusa acima do teu). */
export const INVITE_ROLES = ["viewer", "reviewer", "contributor", "manager", "workspace_admin", "workspace_owner"] as const;

async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase().rpc(fn, args);
  if (error) throw new Error(friendlyError(error.message));
  return data as T;
}

export const fetchTeam = (ws: string) => call<Team>("workspace_team", { p_ws: ws });
export const inviteMember = (ws: string, email: string, role: string, affiliation: "agency_staff" | "client_staff") =>
  call<string>("invite_member", { p_ws: ws, p_email: email.trim(), p_role: role, p_affiliation: affiliation });
export const revokeInvitation = (id: string) => call<void>("revoke_invitation", { p_id: id });
