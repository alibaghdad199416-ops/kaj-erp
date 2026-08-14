begin;

-- R62 proved that the established reversal helpers also pass through input
-- field guards when the cancelled order is restored for audit.  Permit those
-- nested writes only while the inaccessible R62 transaction marker exists.
create or replace function public.erp_r9_guard_input_fields()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company_id uuid;
  v_resource text:=coalesce(TG_ARGV[0],'');
  v_insert_permission text:=nullif(coalesce(TG_ARGV[1],''),'');
  v_update_permission text:=nullif(coalesce(TG_ARGV[2],''),'');
  v_base_permission text;
  v_new jsonb:=to_jsonb(new);
  v_old jsonb:=case when TG_OP='UPDATE' then to_jsonb(old) else '{}'::jsonb end;
  v_pair text; v_column text; v_field text; v_index integer; v_changed boolean;
  v_any_user_field_changed boolean:=false;
  v_reconciliation_bridge_eligible boolean:=true;
begin
  if coalesce(current_setting('request.jwt.claim.role',true),'')='service_role' then return new; end if;
  v_company_id:=nullif(v_new->>'company_id','')::uuid;
  if v_company_id is null then
    raise exception 'field_permission_company_required' using errcode='22023';
  end if;
  if auth.uid() is not null and exists(
    select 1 from erp_private.commercial_cancel_contexts c
    where c.transaction_id=txid_current() and c.user_id=auth.uid()
      and c.company_id=v_company_id
  ) then return new; end if;

  if TG_NARGS>3 then
    for v_index in 3..TG_NARGS-1 loop
      v_pair:=TG_ARGV[v_index]; v_column:=split_part(v_pair,'=',1); v_field:=split_part(v_pair,'=',2);
      if v_column='' or v_field='' then continue; end if;
      if TG_OP='INSERT' then
        v_changed:=v_new ? v_column and jsonb_typeof(v_new->v_column) is distinct from 'null';
      else v_changed:=(v_old->v_column) is distinct from (v_new->v_column); end if;
      if not v_changed then continue; end if;
      v_any_user_field_changed:=true;
      if v_column<>'opportunity_id' then v_reconciliation_bridge_eligible:=false; end if;
      if not public.erp_cloud_user_can_edit_field(v_company_id,v_resource,v_field,null) then
        raise exception 'field_permission_denied:%.%',v_resource,v_field using errcode='42501';
      end if;
    end loop;
  end if;
  if not v_any_user_field_changed then return new; end if;
  v_base_permission:=case when TG_OP='INSERT' then v_insert_permission else v_update_permission end;
  if v_base_permission is not null
     and not public.erp_cloud_user_has_permission(v_company_id,v_base_permission)
     and not (TG_OP='UPDATE' and v_resource='sales' and v_reconciliation_bridge_eligible
       and current_setting('qualityline.r51_reconciliation_permission',true)='customer_service.update'
       and public.erp_cloud_user_has_permission(v_company_id,'customer_service.update')) then
    raise exception 'permission_denied:%',v_base_permission using errcode='42501';
  end if;
  return new;
end;
$$;

revoke all on function public.erp_r9_guard_input_fields() from public,anon,authenticated;

commit;
