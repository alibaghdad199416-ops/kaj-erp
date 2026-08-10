-- Retire the pre-Supabase local username/password authentication path.
-- This migration intentionally runs after authenticated access bootstrap.
drop function if exists public.authenticate_local_erp_user(text, text, text);

-- Login-attempt data belonged only to the retired local authentication flow.
drop table if exists public.erp_login_attempts;
