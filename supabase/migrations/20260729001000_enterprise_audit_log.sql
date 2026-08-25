-- Quality Line ERP 17.74.0
-- Immutable, tenant-scoped audit trail for inserts, updates, deletes and restores.

create table if not exists public.erp_audit_log (
  id bigint generated always as identity primary key,
  company_id uuid not null references public.companies(id) on delete restrict,
  occurred_at timestamptz not null default clock_timestamp(),
  actor_uid text not null default 'unknown',
  actor_role text,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE','RESTORE','LOGIN','LOGOUT','EXPORT','OTHER')),
  schema_name text not null default 'public',
  table_name text not null,
  record_id text,
  old_data jsonb,
  new_data jsonb,
  changed_fields text[] not null default '{}',
  request_id text,
  source text not null default 'database_trigger',
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists erp_audit_log_company_time_idx
  on public.erp_audit_log(company_id, occurred_at desc, id desc);
create index if not exists erp_audit_log_company_table_idx
  on public.erp_audit_log(company_id, table_name, occurred_at desc);
create index if not exists erp_audit_log_record_idx
  on public.erp_audit_log(company_id, table_name, record_id, occurred_at desc)
  where record_id is not null;
create index if not exists erp_audit_log_actor_idx
  on public.erp_audit_log(company_id, actor_uid, occurred_at desc);

alter table public.erp_audit_log enable row level security;
revoke all on public.erp_audit_log from anon, authenticated;
grant select on public.erp_audit_log to authenticated;

drop policy if exists erp_audit_log_admin_select on public.erp_audit_log;
create policy erp_audit_log_admin_select on public.erp_audit_log
for select to authenticated using (public.is_company_admin(company_id));

create or replace function public.erp_audit_actor_uid()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(auth.uid()::text, public.current_external_uid(), 'unknown');
$$;

create or replace function public.erp_audit_changed_fields(p_old jsonb, p_new jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(key order by key), '{}'::text[])
  from (
    select key from jsonb_object_keys(coalesce(p_old, '{}'::jsonb)) key
    union
    select key from jsonb_object_keys(coalesce(p_new, '{}'::jsonb)) key
  ) keys
  where coalesce(p_old -> key, 'null'::jsonb) is distinct from coalesce(p_new -> key, 'null'::jsonb);
$$;

create or replace function public.erp_capture_audit_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_company uuid;
  v_record_id text;
  v_request_id text := nullif(current_setting('request.headers', true)::jsonb ->> 'x-request-id', '');
begin
  if tg_table_name = 'erp_audit_log' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  v_old := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_company := coalesce((v_new ->> 'company_id')::uuid, (v_old ->> 'company_id')::uuid);
  if v_company is null then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  v_record_id := coalesce(v_new ->> 'id', v_old ->> 'id', v_new ->> 'uuid', v_old ->> 'uuid');

  insert into public.erp_audit_log(
    company_id, actor_uid, operation, schema_name, table_name, record_id,
    old_data, new_data, changed_fields, request_id
  ) values (
    v_company, public.erp_audit_actor_uid(), tg_op, tg_table_schema, tg_table_name,
    v_record_id, v_old, v_new, public.erp_audit_changed_fields(v_old, v_new), v_request_id
  );
  if tg_op = 'DELETE' then return old; else return new; end if;
exception when others then
  -- Auditing must not make the business transaction unavailable.
  raise warning 'ERP audit capture failed for %.%: %', tg_table_schema, tg_table_name, sqlerrm;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

create or replace function public.erp_install_audit_triggers()
returns integer language plpgsql security definer set search_path = public as $$
declare v record; v_count integer := 0; v_trigger text;
begin
  for v in
    select c.relname table_name
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and c.relname not in ('erp_audit_log','erp_backup_snapshots')
      and exists (select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='company_id' and not a.attisdropped)
  loop
    v_trigger := 'erp_audit_' || left(md5(v.table_name), 16);
    execute format('drop trigger if exists %I on public.%I', v_trigger, v.table_name);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.erp_capture_audit_change()', v_trigger, v.table_name);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

select public.erp_install_audit_triggers();

create or replace function public.erp_record_audit_event(
  p_company_id uuid, p_operation text, p_table_name text,
  p_record_id text default null, p_metadata jsonb default '{}'::jsonb,
  p_source text default 'application'
) returns bigint language plpgsql security definer set search_path = public as $$
declare v_id bigint;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'audit_company_access_denied' using errcode='42501'; end if;
  insert into public.erp_audit_log(company_id, actor_uid, operation, table_name, record_id, metadata, source)
  values(p_company_id, public.erp_audit_actor_uid(), upper(p_operation), p_table_name, p_record_id, coalesce(p_metadata,'{}'::jsonb), p_source)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.erp_list_audit_log(
  p_company_id uuid, p_limit integer default 100, p_offset integer default 0,
  p_table_name text default null, p_operation text default null,
  p_actor_uid text default null, p_from timestamptz default null, p_to timestamptz default null
) returns setof public.erp_audit_log language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_company_admin(p_company_id) then raise exception 'audit_admin_required' using errcode='42501'; end if;
  return query select a.* from public.erp_audit_log a
  where a.company_id=p_company_id
    and (p_table_name is null or a.table_name=p_table_name)
    and (p_operation is null or a.operation=upper(p_operation))
    and (p_actor_uid is null or a.actor_uid=p_actor_uid)
    and (p_from is null or a.occurred_at>=p_from)
    and (p_to is null or a.occurred_at<=p_to)
  order by a.occurred_at desc, a.id desc
  limit greatest(1, least(coalesce(p_limit,100),500)) offset greatest(coalesce(p_offset,0),0);
end;
$$;

create or replace function public.erp_audit_log_health(p_company_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_rows bigint; v_triggers integer; v_tables integer;
begin
  if not public.is_company_admin(p_company_id) then raise exception 'audit_admin_required' using errcode='42501'; end if;
  select count(*) into v_rows from public.erp_audit_log where company_id=p_company_id;
  select count(*) into v_tables from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and c.relkind='r' and c.relname not in ('erp_audit_log','erp_backup_snapshots')
   and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='company_id' and not a.attisdropped);
  select count(*) into v_triggers from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public' and not t.tgisinternal and t.tgname like 'erp_audit_%';
  return jsonb_build_object('ok',v_triggers>=v_tables,'company_id',p_company_id,'audit_rows',v_rows,
    'tenant_tables',v_tables,'audit_triggers',v_triggers,'checked_at',now());
end;
$$;

-- Audit restore executions explicitly because backup payload restoration may disable/rebuild data.
create or replace function public.erp_audit_backup_restore_event()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.restore_count > old.restore_count then
    insert into public.erp_audit_log(company_id,actor_uid,operation,table_name,record_id,old_data,new_data,changed_fields,source,metadata)
    values(new.company_id,public.erp_audit_actor_uid(),'RESTORE','erp_backup_snapshots',new.id::text,to_jsonb(old),to_jsonb(new),
      array['restore_count','restored_at','restored_by'],'backup_restore',jsonb_build_object('backup_name',new.backup_name));
  end if;
  return new;
end;
$$;
drop trigger if exists erp_audit_backup_restore on public.erp_backup_snapshots;
create trigger erp_audit_backup_restore after update of restore_count on public.erp_backup_snapshots
for each row execute function public.erp_audit_backup_restore_event();

grant execute on function public.erp_list_audit_log(uuid,integer,integer,text,text,text,timestamptz,timestamptz) to authenticated;
grant execute on function public.erp_record_audit_event(uuid,text,text,text,jsonb,text) to authenticated;
grant execute on function public.erp_audit_log_health(uuid) to authenticated;
revoke execute on function public.erp_install_audit_triggers() from public, anon, authenticated;
