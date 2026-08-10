-- Stage 20: universal recycle-bin capture for every business-table deletion.
-- Existing soft-delete behavior is preserved. Hard deletes are archived before
-- removal so no user-created ERP record disappears without a recovery stage.

create table if not exists public.erp_universal_recycle_bin (
  id uuid primary key default gen_random_uuid(),
  company_id uuid,
  source_table text not null,
  record_id text not null,
  payload jsonb not null,
  deletion_mode text not null check (deletion_mode in ('soft','hard')),
  deleted_at timestamptz not null default now(),
  deleted_by uuid default auth.uid(),
  restored_at timestamptz,
  restored_by uuid,
  purged_at timestamptz,
  unique(source_table, record_id, deleted_at)
);

create index if not exists erp_universal_recycle_company_deleted_idx
  on public.erp_universal_recycle_bin(company_id, deleted_at desc)
  where purged_at is null and restored_at is null;

alter table public.erp_universal_recycle_bin enable row level security;

drop policy if exists erp_universal_recycle_member_read on public.erp_universal_recycle_bin;
create policy erp_universal_recycle_member_read
on public.erp_universal_recycle_bin for select to authenticated
using (company_id is null or public.is_company_member(company_id));

create or replace function public.erp_capture_deleted_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payload jsonb := to_jsonb(old);
  v_company uuid;
  v_record_id text;
begin
  if tg_table_name in ('erp_universal_recycle_bin','erp_records') then
    return old;
  end if;
  begin
    v_company := nullif(coalesce(v_payload->>'company_id', v_payload->>'companyId'), '')::uuid;
  exception when others then
    v_company := null;
  end;
  v_record_id := coalesce(v_payload->>'id', v_payload->>'record_id', v_payload->>'recordId');
  if v_record_id is null or trim(v_record_id) = '' then
    v_record_id := md5(v_payload::text || clock_timestamp()::text);
  end if;
  insert into public.erp_universal_recycle_bin(
    company_id, source_table, record_id, payload, deletion_mode, deleted_at, deleted_by
  ) values (
    v_company, tg_table_name, v_record_id, v_payload, 'hard', now(), auth.uid()
  );
  return old;
end;
$$;

create or replace function public.erp_capture_soft_deleted_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new jsonb := to_jsonb(new);
  v_old jsonb := to_jsonb(old);
  v_company uuid;
  v_record_id text;
  v_became_deleted boolean;
begin
  if tg_table_name in ('erp_universal_recycle_bin','erp_records') then return new; end if;
  v_became_deleted :=
    (coalesce((v_new->>'is_deleted')::boolean, (v_new->>'isDeleted')::boolean, false)
      and not coalesce((v_old->>'is_deleted')::boolean, (v_old->>'isDeleted')::boolean, false))
    or (coalesce(v_new->>'deleted_at', v_new->>'deletedAt') is not null
      and coalesce(v_old->>'deleted_at', v_old->>'deletedAt') is null);
  if not v_became_deleted then return new; end if;
  begin
    v_company := nullif(coalesce(v_new->>'company_id', v_new->>'companyId'), '')::uuid;
  exception when others then v_company := null;
  end;
  v_record_id := coalesce(v_new->>'id', v_new->>'record_id', v_new->>'recordId');
  if v_record_id is null or trim(v_record_id) = '' then
    v_record_id := md5(v_new::text || clock_timestamp()::text);
  end if;
  if not exists (
    select 1 from public.erp_universal_recycle_bin
    where source_table=tg_table_name and record_id=v_record_id
      and restored_at is null and purged_at is null
  ) then
    insert into public.erp_universal_recycle_bin(
      company_id, source_table, record_id, payload, deletion_mode, deleted_at, deleted_by
    ) values (
      v_company, tg_table_name, v_record_id, v_new, 'soft',
      coalesce(nullif(coalesce(v_new->>'deleted_at',v_new->>'deletedAt'), '')::timestamptz, now()),
      auth.uid()
    );
  end if;
  return new;
end;
$$;

-- Attach capture triggers to all current public business tables. Future
-- migrations can rerun this block safely after creating additional tables.
do $$
declare r record; v_cols text;
begin
  for r in
    select c.relname table_name
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and c.relname not in ('schema_migrations','erp_universal_recycle_bin','erp_records')
  loop
    execute format('drop trigger if exists erp_capture_hard_delete on public.%I', r.table_name);
    execute format(
      'create trigger erp_capture_hard_delete before delete on public.%I for each row execute function public.erp_capture_deleted_record()',
      r.table_name
    );
    select string_agg(column_name, ',') into v_cols
    from information_schema.columns
    where table_schema='public' and table_name=r.table_name
      and column_name in ('is_deleted','deleted_at','data');
    if v_cols is not null then
      execute format('drop trigger if exists erp_capture_soft_delete on public.%I', r.table_name);
      execute format(
        'create trigger erp_capture_soft_delete after update on public.%I for each row execute function public.erp_capture_soft_deleted_record()',
        r.table_name
      );
    end if;
  end loop;
end $$;

create or replace function public.erp_recycle_bin_list(
  p_company_id uuid,
  p_query text default '',
  p_entity_type text default ''
)
returns table(entity_type text, record_id text, payload jsonb, deleted_at timestamptz, deleted_by text)
language sql stable security definer set search_path=public
as $$
  select x.entity_type,x.record_id,x.payload,x.deleted_at,x.deleted_by
  from (
    select r.entity_type,r.record_id,r.payload,r.deleted_at,
      coalesce(r.payload->>'deletedByUserName',r.payload->>'deletedBy','') deleted_by
    from public.erp_records r
    where r.company_id=p_company_id::text and r.deleted_at is not null
    union all
    select u.source_table,u.record_id,u.payload,u.deleted_at,coalesce(u.deleted_by::text,'')
    from public.erp_universal_recycle_bin u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null and u.purged_at is null
  ) x
  where public.is_company_member(p_company_id)
    and (coalesce(trim(p_entity_type),'')='' or x.entity_type=trim(p_entity_type))
    and (coalesce(trim(p_query),'')='' or x.record_id ilike '%'||trim(p_query)||'%'
      or x.entity_type ilike '%'||trim(p_query)||'%' or x.payload::text ilike '%'||trim(p_query)||'%')
  order by x.deleted_at desc;
$$;

grant select on public.erp_universal_recycle_bin to authenticated;
grant execute on function public.erp_capture_deleted_record() to authenticated;
grant execute on function public.erp_capture_soft_deleted_record() to authenticated;
