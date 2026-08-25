begin;

create table if not exists public.erp_user_ui_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  locale_code text not null default 'ar'
    check (locale_code in ('ar', 'en')),
  theme_mode text not null default 'light'
    check (theme_mode in ('light', 'dark')),
  navigation_position text not null default 'top'
    check (navigation_position in ('top', 'side')),
  side_navigation_collapsed boolean not null default false,
  favorite_routes text[] not null default '{}'::text[],
  collapsed_navigation_groups text[] not null default '{}'::text[],
  side_navigation_scroll_offset double precision not null default 0
    check (side_navigation_scroll_offset >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.erp_user_ui_preferences is
  'Private UI preferences for each authenticated user. Theme, locale and navigation state never leak between accounts.';

alter table public.erp_user_ui_preferences enable row level security;
alter table public.erp_user_ui_preferences force row level security;

drop policy if exists erp_user_ui_preferences_select_own
  on public.erp_user_ui_preferences;
create policy erp_user_ui_preferences_select_own
  on public.erp_user_ui_preferences
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists erp_user_ui_preferences_insert_own
  on public.erp_user_ui_preferences;
create policy erp_user_ui_preferences_insert_own
  on public.erp_user_ui_preferences
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists erp_user_ui_preferences_update_own
  on public.erp_user_ui_preferences;
create policy erp_user_ui_preferences_update_own
  on public.erp_user_ui_preferences
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists erp_user_ui_preferences_delete_own
  on public.erp_user_ui_preferences;
create policy erp_user_ui_preferences_delete_own
  on public.erp_user_ui_preferences
  for delete
  to authenticated
  using (user_id = auth.uid());

grant select, insert, update, delete
  on public.erp_user_ui_preferences
  to authenticated;
revoke all on public.erp_user_ui_preferences from anon;

create or replace function public.erp_touch_user_ui_preferences()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.erp_touch_user_ui_preferences() from public;
grant execute on function public.erp_touch_user_ui_preferences() to authenticated;

drop trigger if exists erp_touch_user_ui_preferences
  on public.erp_user_ui_preferences;
create trigger erp_touch_user_ui_preferences
before update on public.erp_user_ui_preferences
for each row execute function public.erp_touch_user_ui_preferences();

commit;
