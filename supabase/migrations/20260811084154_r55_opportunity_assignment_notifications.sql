-- R55 forward-only repair: tenant-scoped, retry-idempotent Opportunity
-- assignment and meaningful follow-up notifications. Historical migrations
-- remain unchanged.
begin;

create or replace function public.erp_r55_upsert_opportunity_notification(
  p_company_id uuid,
  p_company_slug text,
  p_user_id text,
  p_event_type text,
  p_reference_id text,
  p_opportunity jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user_id text:=nullif(btrim(coalesce(p_user_id,'')),'');
  v_event_type text:=nullif(btrim(coalesce(p_event_type,'')),'');
  v_reference_id text:=nullif(btrim(coalesce(p_reference_id,'')),'');
  v_hash text;
  v_id uuid;
  v_customer text:=nullif(btrim(coalesce(
    p_opportunity->>'customerName',p_opportunity->>'customer_name',''
  )), '');
  v_number text:=nullif(btrim(coalesce(
    p_opportunity->>'opportunityNumber',p_opportunity->>'opportunity_number',''
  )), '');
  v_title_ar text;
  v_title_en text;
  v_body_ar text;
  v_body_en text;
begin
  if p_company_id is null or nullif(btrim(coalesce(p_company_slug,'')),'') is null
     or v_user_id is null or v_event_type is null or v_reference_id is null then
    raise exception 'opportunity_notification_context_required' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.companies c
    where c.id=p_company_id and c.slug=p_company_slug and c.is_active
  ) then
    raise exception 'opportunity_notification_company_mismatch' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records u
    where u.company_id=p_company_slug and u.entity_type='users'
      and u.record_id=v_user_id and not u.is_deleted and u.deleted_at is null
      and lower(coalesce(u.payload->>'isActive',u.payload->>'is_active','true'))
          not in ('false','0')
  ) and not exists(
    select 1 from public.company_memberships m
    where m.company_id=p_company_id and m.is_active
      and v_user_id in (coalesce(m.user_id::text,''),coalesce(m.user_uid,''))
  ) then
    raise exception 'opportunity_assignee_not_found' using errcode='23503';
  end if;

  if v_event_type='opportunity_assignment' then
    v_title_ar:='تم إسناد فرصة تجارية إليك';
    v_title_en:='Opportunity assigned to you';
    v_body_ar:=concat_ws(' — ',v_number,v_customer);
    v_body_en:=concat_ws(' — ',v_number,v_customer);
  else
    v_title_ar:='تم تحديث متابعة فرصة تجارية';
    v_title_en:='Opportunity follow-up updated';
    v_body_ar:=concat_ws(' — ',v_number,v_customer);
    v_body_en:=concat_ws(' — ',v_number,v_customer);
  end if;

  -- A deterministic tenant/event/reference/target identifier makes a retry an
  -- update of the same notification even under concurrent requests.
  v_hash:=md5(p_company_id::text||'|'||v_event_type||'|'||v_reference_id||'|'||v_user_id);
  v_id:=(substr(v_hash,1,8)||'-'||substr(v_hash,9,4)||'-'||substr(v_hash,13,4)||'-'||
        substr(v_hash,17,4)||'-'||substr(v_hash,21,12))::uuid;

  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(
    p_company_id,v_id,jsonb_build_object(
      'userId',v_user_id,'roleId',null,
      'titleAr',v_title_ar,'titleEn',v_title_en,
      'bodyAr',v_body_ar,'bodyEn',v_body_en,
      'type',v_event_type,'referenceType','opportunity',
      'referenceId',v_reference_id,'isRead',false,
      'createdAt',now(),'opportunityStage',coalesce(
        p_opportunity->>'stage',p_opportunity->>'status',''
      )
    )
  )
  on conflict(company_id,id) do update
    set data=public.erp_enterprise_notifications.data ||
             (excluded.data-'createdAt') ||
             jsonb_build_object('isRead',false,'readAt',null,'updatedAt',now()),
        is_deleted=false,deleted_at=null,updated_at=now();

  update public.erp_notification_user_states
     set is_read=false,archived=false,read_at=null,archived_at=null,updated_at=now()
   where company_id=p_company_id and notification_id=v_id;
  return v_id;
end
$$;

create or replace function public.erp_r55_notify_opportunity_change()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_user_id text:=nullif(btrim(coalesce(
    new.payload->>'assignedUserId',new.payload->>'assigned_user_id',''
  )), '');
  v_old_user_id text;
  v_meaningful_change boolean:=false;
begin
  if new.entity_type<>'opportunities' or new.is_deleted or new.deleted_at is not null then
    return new;
  end if;
  select c.id into v_company_id
  from public.companies c where c.slug=new.company_id and c.is_active;
  if v_company_id is null then
    raise exception 'opportunity_company_not_found' using errcode='23503';
  end if;

  if tg_op='UPDATE' then
    v_old_user_id:=nullif(btrim(coalesce(
      old.payload->>'assignedUserId',old.payload->>'assigned_user_id',''
    )), '');
    v_meaningful_change:=
      coalesce(new.payload->>'stage','') is distinct from coalesce(old.payload->>'stage','') or
      coalesce(new.payload->>'status','') is distinct from coalesce(old.payload->>'status','') or
      coalesce(new.payload->>'followUpDate',new.payload->>'follow_up_date','') is distinct from
        coalesce(old.payload->>'followUpDate',old.payload->>'follow_up_date','') or
      coalesce(new.payload->>'saleId',new.payload->>'sale_id','') is distinct from
        coalesce(old.payload->>'saleId',old.payload->>'sale_id','');
  end if;

  if v_user_id is not null and (tg_op='INSERT' or v_user_id is distinct from v_old_user_id) then
    perform public.erp_r55_upsert_opportunity_notification(
      v_company_id,new.company_id,v_user_id,'opportunity_assignment',new.record_id,new.payload
    );
  end if;
  if v_user_id is not null and tg_op='UPDATE' and v_meaningful_change then
    perform public.erp_r55_upsert_opportunity_notification(
      v_company_id,new.company_id,v_user_id,'opportunity_follow_up',new.record_id,new.payload
    );
  end if;
  return new;
end
$$;

drop trigger if exists erp_r55_opportunity_notification_trg on public.erp_records;
create trigger erp_r55_opportunity_notification_trg
after insert or update of payload,is_deleted,deleted_at on public.erp_records
for each row execute function public.erp_r55_notify_opportunity_change();

revoke all on function public.erp_r55_upsert_opportunity_notification(uuid,text,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_r55_notify_opportunity_change()
  from public,anon,authenticated;
grant execute on function public.erp_r55_upsert_opportunity_notification(uuid,text,text,text,text,jsonb)
  to service_role;
grant execute on function public.erp_r55_notify_opportunity_change()
  to service_role;

notify pgrst,'reload schema';
commit;
