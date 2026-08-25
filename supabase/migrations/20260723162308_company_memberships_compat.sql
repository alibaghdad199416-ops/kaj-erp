begin;

alter table public.company_memberships
  add column if not exists updated_at timestamptz not null default now();

alter table public.company_memberships
  add column if not exists user_uid text;

alter table public.company_memberships
  add column if not exists user_email text;

alter table public.company_memberships
  add column if not exists local_user_id text;

update public.company_memberships
set updated_at = coalesce(updated_at, created_at, now());

commit;