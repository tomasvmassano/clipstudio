import { supabase } from "@/lib/supabase";
import { friendlyError } from "@/lib/access";

export type Member = {
  user_id: string; email: string; affiliation: "agency_staff" | "client_staff"; role: string;
  job_title: string | null; status: "active" | "suspended"; expires_at: string | null; since: string;
  open_tasks?: number; can_manage?: boolean;
};
export type Invitation = { id: string; email: string; affiliation: "agency_staff" | "client_staff"; role: string; expires_at: string; created_at: string };
export type Team = {
  members: Member[]; invitations: Invitation[]; can_invite: boolean; can_invite_agency: boolean;
  can_manage?: boolean; my_rank?: number; agency_staff?: { user_id: string; email: string; role: string }[] | null;
};

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

export const updateMember = (ws: string, user: string, patch: Partial<{ role: string; status: "active" | "suspended"; job_title: string }>) =>
  call<{ role: string; status: string }>("member_update", { p_ws: ws, p_user: user, p_patch: patch });
export const removeMember = (ws: string, user: string, reassignTo: string | null) =>
  call<{ tasks_reassigned: number }>("member_remove", { p_ws: ws, p_user: user, p_reassign_to: reassignTo });
export const assignAgencyStaff = (ws: string, user: string, role: string) =>
  call<{ role: string }>("agency_staff_assign", { p_ws: ws, p_user: user, p_role: role });

/* ---------- Equipa da agência (espaço da agência, W1-13; ADR-0020) ---------- */

export type AgencyStaff = {
  user_id: string; email: string; agency_role: string; status: "active" | "suspended"; since: string; last_sign_in: string | null;
  clients: { id: string; name: string; role: string; status: string; open_tasks: number }[]; open_tasks: number;
};
export type AgencyTeam = {
  me: string; can: { invite: boolean; manage: boolean }; staff: AgencyStaff[];
  clients: { id: string; name: string }[];
  invites: { id: string; email: string; agency_role: string; expires_at: string; created_at: string }[];
};
export const AGENCY_ROLES = ["agency_member", "agency_manager", "agency_admin"] as const;
export const AGENCY_ROLE_LABEL: Record<string, string> = {
  agency_owner: "Dono da agência", agency_admin: "Admin da agência", agency_manager: "Gestor da agência", agency_member: "Membro da agência",
};
export const fetchAgencyTeam = () => call<AgencyTeam>("agency_team", {});
export const inviteAgency = (email: string, role: string) => call<string>("agency_invite", { p_email: email.trim(), p_role: role });
export const revokeAgencyInvite = (id: string) => call<void>("agency_invite_revoke", { p_id: id });
export const updateAgencyMember = (user: string, patch: Partial<{ agency_role: string; status: "active" | "suspended" }>) =>
  call<{ agency_role: string; status: string }>("agency_member_update", { p_user: user, p_patch: patch });
