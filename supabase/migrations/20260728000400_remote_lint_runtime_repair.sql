begin;

-- ---------------------------------------------------------------------------
-- Commercial audit columns required by contextual reports and linked workflow
-- updates. These normalized tables predated the shared ERP audit columns.
-- ---------------------------------------------------------------------------
alter table public.erp_sales_orders_cloud
  add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id) on delete set null default auth.uid();

alter table public.erp_sales_order_items_cloud
  add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id) on delete set null default auth.uid();

alter table public.erp_purchase_orders_cloud
  add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id) on delete set null default auth.uid();

alter table public.erp_purchase_order_items_cloud
  add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id) on delete set null default auth.uid();

alter table public.erp_commercial_workflow_documents
  add column if not exists created_by uuid references auth.users(id) on delete set null default auth.uid(),
  add column if not exists updated_by uuid references auth.users(id) on delete set null default auth.uid();

create or replace function public.erp_stamp_commercial_audit_user()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    new.created_by:=coalesce(new.created_by,auth.uid());
    new.updated_by:=coalesce(new.updated_by,new.created_by,auth.uid());
  else
    new.created_by:=coalesce(new.created_by,old.created_by);
    new.updated_by:=coalesce(auth.uid(),new.updated_by,old.updated_by);
  end if;
  return new;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_sales_orders_cloud',
    'erp_sales_order_items_cloud',
    'erp_purchase_orders_cloud',
    'erp_purchase_order_items_cloud',
    'erp_commercial_workflow_documents'
  ] loop
    execute format('drop trigger if exists erp_stamp_commercial_audit_user on public.%I',v_table);
    execute format(
      'create trigger erp_stamp_commercial_audit_user before insert or update on public.%I '
      'for each row execute function public.erp_stamp_commercial_audit_user()',
      v_table
    );
  end loop;
end;
$$;

-- Backfill updater with creator where older records already have a creator.
update public.erp_sales_orders_cloud set updated_by=created_by
where updated_by is null and created_by is not null;
update public.erp_sales_order_items_cloud set updated_by=created_by
where updated_by is null and created_by is not null;
update public.erp_purchase_orders_cloud set updated_by=created_by
where updated_by is null and created_by is not null;
update public.erp_purchase_order_items_cloud set updated_by=created_by
where updated_by is null and created_by is not null;
update public.erp_commercial_workflow_documents set updated_by=created_by
where updated_by is null and created_by is not null;

-- ---------------------------------------------------------------------------
-- Compatibility random-byte function for legacy phase-26 API-token creation.
-- The Supabase pgcrypto function may live in the `extensions` schema while the
-- legacy command has search_path=public.
-- ---------------------------------------------------------------------------
do $block$
begin
  if to_regprocedure('public.gen_random_bytes(integer)') is null then
    execute $function$
      create function public.gen_random_bytes(p_length integer)
      returns bytea
      language plpgsql
      volatile
      security invoker
      set search_path=public
      as $body$
      declare
        v_bytes bytea:=''::bytea;
      begin
        if p_length is null or p_length < 0 then
          raise exception 'byte length must be zero or greater';
        end if;
        while octet_length(v_bytes) < p_length loop
          v_bytes:=v_bytes||decode(replace(gen_random_uuid()::text,'-',''),'hex');
        end loop;
        return substring(v_bytes from 1 for p_length);
      end;
      $body$
    $function$;
  end if;
end;
$block$;

-- ---------------------------------------------------------------------------
-- Legacy purchase deletion: erp_records.company_id is text and the loop value
-- must remain text, otherwise PostgreSQL attempts text = uuid.
-- ---------------------------------------------------------------------------
create or replace function public.erp_delete_cloud_purchase(
  p_company_id uuid,p_purchase_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_car_id text;
  v_now timestamptz:=clock_timestamp();
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'access denied';
  end if;

  perform 1
  from public.erp_purchases
  where company_id=p_company_id and id=p_purchase_id and not is_deleted
  for update;
  if not found then raise exception 'فاتورة الشراء غير موجودة'; end if;

  for v_car_id in
    select nullif(data->>'carId','')
    from public.erp_purchase_items
    where company_id=p_company_id and not is_deleted
      and data->>'purchaseId'=p_purchase_id
      and nullif(data->>'carId','') is not null
  loop
    if exists(
      select 1 from public.erp_sales
      where company_id=p_company_id and not is_deleted
        and data->>'carId'=v_car_id
    ) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات تم بيعها لاحقاً';
    end if;

    if exists(
      select 1 from public.erp_records
      where company_id=p_company_id::text
        and entity_type='reservations'
        and deleted_at is null
        and payload->>'carId'=v_car_id
        and payload->>'status'='active'
    ) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات قيد البيع حالياً';
    end if;
  end loop;

  for v_car_id in
    select nullif(data->>'carId','')
    from public.erp_purchase_items
    where company_id=p_company_id and not is_deleted
      and data->>'purchaseId'=p_purchase_id
      and nullif(data->>'carId','') is not null
  loop
    update public.erp_cars
    set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
          'status','معرفة',
          'warehouseId',null,
          'warehouse_id',null,
          'updatedAt',v_now
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where company_id=p_company_id and id=v_car_id and not is_deleted;
  end loop;

  update public.erp_purchase_items
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and not is_deleted
    and data->>'purchaseId'=p_purchase_id;

  update public.erp_purchases
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_purchase_id and not is_deleted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Document transition: both CASE branches must be jsonb.
-- ---------------------------------------------------------------------------
create or replace function public.erp_transition_cloud_document(
  p_company_id uuid,p_document_id uuid,p_to_status text,
  p_actor_id text,p_description text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  d public.erp_document_records%rowtype;
  ok boolean:=false;
  v_archived_at jsonb;
begin
  select * into d
  from public.erp_document_records
  where company_id=p_company_id and id=p_document_id and not is_deleted
  for update;
  if not found then raise exception 'document not found'; end if;

  ok:=case d.data->>'status'
    when 'draft' then p_to_status in ('in_review','cancelled')
    when 'in_review' then p_to_status in ('approved','draft','cancelled')
    when 'approved' then p_to_status in ('active','archived','cancelled')
    when 'active' then p_to_status in ('archived','expired','cancelled')
    when 'expired' then p_to_status='archived'
    else false
  end;
  if not ok then raise exception 'invalid document transition'; end if;

  v_archived_at:=case
    when p_to_status='archived' then to_jsonb(clock_timestamp())
    else d.data->'archivedAt'
  end;

  update public.erp_document_records
  set data=data||jsonb_build_object(
        'status',p_to_status,
        'archivedAt',v_archived_at,
        'updatedAt',clock_timestamp()
      ),
      updated_at=clock_timestamp()
  where company_id=p_company_id and id=p_document_id;

  insert into public.erp_document_events(company_id,id,data)
  values(
    p_company_id,
    gen_random_uuid(),
    jsonb_build_object(
      'documentId',p_document_id,
      'eventType','status_changed',
      'fromStatus',d.data->>'status',
      'toStatus',p_to_status,
      'actorId',p_actor_id,
      'description',p_description,
      'createdAt',clock_timestamp()
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Specialized maintenance report: the normalized maintenance table has real
-- columns rather than a `data` jsonb column. Export the complete row.
-- ---------------------------------------------------------------------------
create or replace function public.erp_cloud_specialized_report(
  p_company_id uuid,p_module text,p_filter jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  q jsonb;
  v_module text:=lower(btrim(coalesce(p_module,'')));
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  case v_module
    when 'sales' then
      select coalesce(jsonb_agg(
        s.data||jsonb_build_object(
          'id',s.id,
          'brand',c.data->>'brand',
          'model',c.data->>'model',
          'chassis',c.data->>'chassis',
          'customerName',cu.data->>'name'
        ) order by s.created_at desc
      ),'[]'::jsonb)
      into q
      from public.erp_sales s
      left join public.erp_cars c
        on c.company_id=s.company_id and c.id=s.data->>'carId'
      left join public.erp_customers cu
        on cu.company_id=s.company_id and cu.id=s.data->>'customerId'
      where s.company_id=p_company_id and not coalesce(s.is_deleted,false);

    when 'inventory' then
      select coalesce(jsonb_agg(
        i.data||jsonb_build_object('id',i.id) order by i.created_at desc
      ),'[]'::jsonb)
      into q
      from public.erp_inventory i
      where i.company_id=p_company_id and not coalesce(i.is_deleted,false);

    when 'expenses' then
      select coalesce(jsonb_agg(
        e.data||jsonb_build_object('id',e.id) order by e.created_at desc
      ),'[]'::jsonb)
      into q
      from public.erp_expenses e
      where e.company_id=p_company_id and not coalesce(e.is_deleted,false);

    when 'maintenance' then
      select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at desc),'[]'::jsonb)
      into q
      from public.erp_maintenance_orders m
      where m.company_id=p_company_id and not coalesce(m.is_deleted,false);

    else
      q:='[]'::jsonb;
  end case;

  return q;
end;
$$;

grant execute on function public.erp_delete_cloud_purchase(uuid,text) to authenticated;
grant execute on function public.erp_transition_cloud_document(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.erp_cloud_specialized_report(uuid,text,jsonb) to authenticated;

commit;
