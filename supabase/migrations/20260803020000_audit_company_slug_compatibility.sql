-- Phase 2 follow-up: make enterprise audit capture compatible with both
-- UUID company identifiers and the legacy erp_records company slug.

begin;

create or replace function public.erp_audit_company_id_from_payload(p_payload jsonb)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_raw text;
  v_company_id uuid;
begin
  v_raw := nullif(btrim(coalesce(p_payload ->> 'company_id', p_payload ->> 'companyId')), '');
  if v_raw is null then
    return null;
  end if;

  begin
    v_company_id := v_raw::uuid;
    return v_company_id;
  exception
    when invalid_text_representation then
      null;
  end;

  select c.id
    into v_company_id
  from public.companies c
  where c.slug = v_raw
  limit 1;

  return v_company_id;
end;
$$;

revoke all on function public.erp_audit_company_id_from_payload(jsonb) from public;
grant execute on function public.erp_audit_company_id_from_payload(jsonb) to authenticated;

create or replace function public.erp_capture_audit_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_company uuid;
  v_record_id text;
  v_request_id text;
  v_headers text;
begin
  if tg_table_name = 'erp_audit_log' then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  v_old := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;

  v_company := coalesce(
    public.erp_audit_company_id_from_payload(v_new),
    public.erp_audit_company_id_from_payload(v_old)
  );
  if v_company is null then
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;

  v_record_id := coalesce(
    v_new ->> 'id', v_old ->> 'id',
    v_new ->> 'uuid', v_old ->> 'uuid',
    v_new ->> 'record_id', v_old ->> 'record_id',
    v_new ->> 'recordId', v_old ->> 'recordId'
  );

  v_headers := nullif(current_setting('request.headers', true), '');
  if v_headers is not null then
    begin
      v_request_id := nullif(v_headers::jsonb ->> 'x-request-id', '');
    exception when others then
      v_request_id := null;
    end;
  end if;

  insert into public.erp_audit_log(
    company_id, actor_uid, operation, schema_name, table_name, record_id,
    old_data, new_data, changed_fields, request_id
  ) values (
    v_company, public.erp_audit_actor_uid(), tg_op, tg_table_schema, tg_table_name,
    v_record_id, v_old, v_new, public.erp_audit_changed_fields(v_old, v_new), v_request_id
  );

  if tg_op = 'DELETE' then return old; else return new; end if;
exception when others then
  raise warning 'ERP audit capture failed for %.%: %', tg_table_schema, tg_table_name, sqlerrm;
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

select public.erp_install_audit_triggers();

commit;