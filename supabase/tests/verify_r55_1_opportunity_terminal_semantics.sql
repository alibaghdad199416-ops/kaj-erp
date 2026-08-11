\set ON_ERROR_STOP on
\pset pager off

begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  '00000000-0000-0000-0000-000000000000','55100000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r55-1-runtime@local.invalid','',now(),'{}','{}',now(),now()
);
insert into public.companies(id,slug,name_ar,name_en,is_active) values (
  '55100000-0000-4000-8000-000000000010','r55-1-runtime','R55.1 محلي','R55.1 local',true
);
insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values (
  '55100000-0000-4000-8000-000000000010','55100000-0000-4000-8000-000000000001',
  '55100000-0000-4000-8000-000000000001','r55-1-runtime@local.invalid','admin',true,true
);
set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"55100000-0000-4000-8000-000000000001","role":"authenticated"}',true
);

do $verify$
declare
  opportunity jsonb;
  lost jsonb;
begin
  opportunity:=public.erp_r49_opportunity_command('save',jsonb_build_object(
    'create_only',true,'record',jsonb_build_object(
      'id','r55-1-opportunity','customerName','R55.1 Customer',
      'stage','qualified','status','pending','currency','IQD','expectedValue',500,
      'assignedUserId','55100000-0000-4000-8000-000000000001',
      'assignedUserName','R55.1 Admin'
    )
  ));

  begin
    perform public.erp_r49_opportunity_command('save',jsonb_build_object(
      'create_only',false,'expected_updated_at',opportunity->>'updatedAt',
      'record',opportunity||jsonb_build_object('stage','won')
    ));
    raise exception 'r55_1_forged_won_was_accepted';
  exception when sqlstate '42501' then null;
  end;

  opportunity:=public.erp_r49_opportunity_command('list','{}'::jsonb)->0;
  if opportunity->>'stage'<>'qualified' or opportunity->>'status'<>'pending' then
    raise exception 'r55_1_forged_won_changed_state:%',opportunity;
  end if;

  lost:=public.erp_r49_opportunity_command('mark_lost',jsonb_build_object(
    'id','r55-1-opportunity','expected_updated_at',opportunity->>'updatedAt'
  ));
  if lost->>'stage'<>'lost' or lost->>'status'<>'lost'
     or coalesce((lost->>'probability')::numeric,-1)<>0 then
    raise exception 'r55_1_canonical_lost_inconsistent:%',lost;
  end if;
  if (select count(*) from public.erp_enterprise_notifications
      where company_id='55100000-0000-4000-8000-000000000010'
        and data->>'type'='opportunity_follow_up'
        and data->>'referenceId'='r55-1-opportunity'
        and data->>'userId'='55100000-0000-4000-8000-000000000001')<>1 then
    raise exception 'r55_1_lost_notification_not_exactly_once';
  end if;
end
$verify$;

rollback;
