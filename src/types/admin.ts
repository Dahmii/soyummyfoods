export const APP_ROLES = ['owner', 'manager', 'staff'] as const;

export type AppRole = (typeof APP_ROLES)[number];

export interface AdminProfile {
  id: string;
  display_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface UserRole {
  user_id: string;
  role: AppRole;
  granted_by: string | null;
  granted_at: string;
}
