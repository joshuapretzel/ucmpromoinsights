-- Let managers approve people who have signed up, instead of an admin editing
-- the profiles table by hand in the Supabase dashboard.
--
-- This is done as a SECURITY DEFINER function rather than an UPDATE policy on
-- profiles, because the rules are about *which* role you may grant, and that is
-- awkward to express as a row policy. The existing
-- "users update own profile" policy already blocks self-role-changes and stays
-- untouched.
--
-- Guardrails, enforced here so the UI can't be the only thing standing between
-- a manager and an admin token:
--   * only admin/manager may call it at all
--   * nobody may grant 'admin' except an existing admin
--   * nobody may change their own role (no self-escalation, no self-lockout)
--   * only an admin may change an existing admin's role
CREATE OR REPLACE FUNCTION "public"."app_set_user_role"("target_user" "uuid", "new_role" "text")
    RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  caller_role text := public.app_role();
  target_role text;
begin
  if caller_role is null or caller_role not in ('admin', 'manager') then
    raise exception 'Only admins and managers can change roles';
  end if;

  if new_role is not null and new_role not in ('admin', 'manager', 'promoter', 'client') then
    raise exception 'Unknown role: %', new_role;
  end if;

  if new_role = 'admin' and caller_role <> 'admin' then
    raise exception 'Only an admin can grant the admin role';
  end if;

  if target_user = auth.uid() then
    raise exception 'You cannot change your own role';
  end if;

  select role into target_role from profiles where id = target_user;
  if not found then
    raise exception 'No such user';
  end if;

  if target_role = 'admin' and caller_role <> 'admin' then
    raise exception 'Only an admin can change another admin''s role';
  end if;

  update profiles set role = new_role, updated_at = now() where id = target_user;
end;
$$;

ALTER FUNCTION "public"."app_set_user_role"("uuid", "text") OWNER TO "postgres";

-- anon deliberately omitted: an unauthenticated caller has no business here,
-- and app_role() would be null for them anyway.
GRANT EXECUTE ON FUNCTION "public"."app_set_user_role"("uuid", "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."app_set_user_role"("uuid", "text") TO "service_role";
