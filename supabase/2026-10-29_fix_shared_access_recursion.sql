-- Fix: the owner SELECT policy on shared_binder_access referenced
-- shared_binders, whose viewer policy referenced shared_binder_access again.
-- That caused PostgreSQL error 42P17 (infinite recursion in policy).
drop policy if exists "shared_access_owner_select" on public.shared_binder_access;
