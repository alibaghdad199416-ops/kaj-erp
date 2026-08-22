\set ON_ERROR_STOP on
\pset pager off

begin;

insert into public.companies(id,slug,name_ar,name_en,is_active) values
  ('55000000-0000-4000-8000-000000000001','r55-notifications','R55 محلي','R55 local',true),
  ('55000000-0000-4000-8000-000000000002','r55-other','R55 أخرى','R55 other',true);
insert into public.erp_records(company_id,entity_type,record_id,payload) values
  ('r55-notifications','users','r55-user','{"fullName":"R55 User","isActive":true}'),
  ('r55-other','users','other-user','{"fullName":"Other User","isActive":true}');

insert into public.erp_records(company_id,entity_type,record_id,payload) values(
  'r55-notifications','opportunities','r55-opportunity',
  '{"opportunityNumber":"OPP-R55","customerName":"R55 Customer","stage":"qualified","status":"pending","assignedUserId":"r55-user"}'
);

do $verify$
declare v_count integer;
begin
  select count(*) into v_count
  from public.erp_enterprise_notifications
  where company_id='55000000-0000-4000-8000-000000000001'
    and data->>'type'='opportunity_assignment'
    and data->>'referenceId'='r55-opportunity'
    and data->>'userId'='r55-user';
  if v_count<>1 then raise exception 'r55_assignment_notification_missing:%',v_count; end if;

  update public.erp_records set payload=payload||'{"notes":"retry-safe"}'::jsonb
  where company_id='r55-notifications' and entity_type='opportunities'
    and record_id='r55-opportunity';
  select count(*) into v_count from public.erp_enterprise_notifications
  where company_id='55000000-0000-4000-8000-000000000001'
    and data->>'type'='opportunity_assignment' and data->>'referenceId'='r55-opportunity';
  if v_count<>1 then raise exception 'r55_assignment_retry_duplicated:%',v_count; end if;

  update public.erp_records set payload=payload||'{"stage":"proposal"}'::jsonb
  where company_id='r55-notifications' and entity_type='opportunities'
    and record_id='r55-opportunity';
  select count(*) into v_count from public.erp_enterprise_notifications
  where company_id='55000000-0000-4000-8000-000000000001'
    and data->>'type'='opportunity_follow_up' and data->>'referenceId'='r55-opportunity'
    and data->>'userId'='r55-user';
  if v_count<>1 then raise exception 'r55_follow_up_notification_missing:%',v_count; end if;

  begin
    update public.erp_records
       set payload=payload||'{"assignedUserId":"other-user"}'::jsonb
     where company_id='r55-notifications' and entity_type='opportunities'
       and record_id='r55-opportunity';
    raise exception 'r55_cross_tenant_assignee_was_accepted';
  exception when foreign_key_violation then null;
  end;
end
$verify$;

rollback;
