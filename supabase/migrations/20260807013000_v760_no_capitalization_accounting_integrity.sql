begin;

-- V7.6.0: operational sales, purchases, maintenance and expenses never post
-- to capitalization accounts. Purchase inventory valuation is normalized to
-- item/vehicle/service definitions. Cross-currency purchases use explicit FX
-- settlement accounts only because one balanced journal cannot mix currencies.

create or replace function public.erp_v760_is_credit_nature(p_account_type text)
returns boolean language sql immutable as $$
  select lower(btrim(coalesce(p_account_type,''))) in
    ('liability','payable','equity','revenue','income')
$$;

create or replace function public.erp_v759_normal_balance(
  p_account_type text,p_opening numeric,p_debit numeric,p_credit numeric
) returns numeric language sql immutable as $$
  select case when public.erp_v760_is_credit_nature(p_account_type)
    then coalesce(p_opening,0)+coalesce(p_credit,0)-coalesce(p_debit,0)
    else coalesce(p_opening,0)+coalesce(p_debit,0)-coalesce(p_credit,0)
  end
$$;

create or replace function public.erp_v760_ensure_purchase_fx_settlement_accounts(
  p_company_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_iqd text; v_usd text; v_parent text;
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;
  select account_id into v_parent from public.erp_accounts
   where organization_id=p_company_id and account_type='asset' and parent_account_id is null
   order by code limit 1;
  v_iqd:=public.erp_deterministic_uuid(p_company_id::text||':purchase-fx-settlement:IQD')::text;
  v_usd:=public.erp_deterministic_uuid(p_company_id::text||':purchase-fx-settlement:USD')::text;
  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,currency,
    opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values
    (p_company_id,v_iqd,'1393','تسوية تحويل عملة المشتريات - دينار','asset',v_parent,'IQD',0,true,now(),now(),auth.uid()),
    (p_company_id,v_usd,'1394','تسوية تحويل عملة المشتريات - دولار','asset',v_parent,'USD',0,true,now(),now(),auth.uid())
  on conflict(organization_id,account_id) do update set
    name=excluded.name,account_type='asset',currency=excluded.currency,is_active=true,
    source_updated_at=now(),synced_at=now(),synced_by=auth.uid();
  return jsonb_build_object('IQD',v_iqd,'USD',v_usd);
end;
$$;

create or replace function public.erp_v760_normalize_purchase_invoice_posting(
  p_company_id uuid,p_invoice_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_currency text; v_total numeric; v_order_rate numeric; v_supplier text;
  v_supplier_account text; v_subtotal numeric; v_factor numeric:=1; v_effective timestamptz;
  r record; ac jsonb; v_cost_currency text; v_amount numeric; v_converted numeric;
  v_by_currency jsonb:='{}'::jsonb; v_invoice_lines jsonb:='[]'::jsonb;
  v_entry text; v_entries jsonb:='[]'::jsonb; v_settlement jsonb; v_settlement_id text;
  v_old_ids text[]:=array[]::text[]; x jsonb; k text; lines jsonb;
begin
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module='purchases'
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status<>'approved' then raise exception 'workflow_invoice_not_approved'; end if;
  if public.erp_try_boolean(d.payload->>'v760NoCapitalizationNormalized','false') then
    return jsonb_build_object('ok',true,'alreadyNormalized',true);
  end if;

  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_effective:=coalesce(d.effective_at,d.created_at,now());
  select supplier_id,subtotal,exchange_rate into v_supplier,v_subtotal,v_order_rate
    from public.erp_purchase_orders_cloud
   where company_id=p_company_id and id=d.parent_id and not is_deleted;
  if not found or v_currency not in ('IQD','USD') or v_total<=0 then
    raise exception 'purchase_invoice_header_invalid';
  end if;
  v_supplier_account:=public.erp_workflow_partner_account(
    p_company_id,'supplier',v_supplier,v_currency);
  v_factor:=case when coalesce(v_subtotal,0)>0 then v_total/v_subtotal else 1 end;

  for r in select * from public.erp_purchase_order_items_cloud
    where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
  loop
    ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
    v_cost_currency:=upper(ac->>'costCurrency');
    perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',v_cost_currency);
    v_amount:=r.line_total*v_factor;
    v_converted:=public.erp_v736_convert_currency(v_amount,v_currency,v_cost_currency,v_order_rate);
    lines:=coalesce(v_by_currency->v_cost_currency,'[]'::jsonb)||jsonb_build_array(jsonb_build_object(
      'accountId',ac->>'assetAccountId','debit',v_converted,'credit',0,
      'description','مخزون شراء - '||r.description,'itemType',r.item_type,'itemId',r.item_id));
    v_by_currency:=jsonb_set(v_by_currency,array[v_cost_currency],lines,true);
  end loop;

  -- Retire journals generated by legacy capitalization-labelled engines. Their
  -- inventory layers and valuation snapshots remain; only accounting is replaced.
  if nullif(d.payload->>'journalEntryId','') is not null then
    v_old_ids:=array_append(v_old_ids,d.payload->>'journalEntryId');
  end if;
  for x in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
    if nullif(x->>'journalEntryId','') is not null then v_old_ids:=array_append(v_old_ids,x->>'journalEntryId'); end if;
  end loop;
  update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and data->>'entryId'=any(v_old_ids) and not is_deleted;
  update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=any(v_old_ids) and not is_deleted;

  if jsonb_object_length(v_by_currency)=1 and v_by_currency ? v_currency then
    v_invoice_lines:=(v_by_currency->v_currency)||jsonb_build_array(jsonb_build_object(
      'accountId',v_supplier_account,'debit',0,'credit',v_total,
      'description','ذمة المورد - فاتورة شراء'));
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'purchase_invoice',p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'purchase_invoice_journal','PIJ',v_effective),
      'فاتورة شراء مباشرة إلى حسابات المخزون '||d.document_number,v_currency,v_invoice_lines,v_effective);
    v_entries:=jsonb_build_array(jsonb_build_object('currency',v_currency,'journalEntryId',v_entry,'mode','direct'));
  else
    v_settlement:=public.erp_v760_ensure_purchase_fx_settlement_accounts(p_company_id);
    v_settlement_id:=v_settlement->>v_currency;
    v_invoice_lines:=jsonb_build_array(
      jsonb_build_object('accountId',v_settlement_id,'debit',v_total,'credit',0,'description','تسوية عملة فاتورة الشراء'),
      jsonb_build_object('accountId',v_supplier_account,'debit',0,'credit',v_total,'description','ذمة المورد - فاتورة شراء'));
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'purchase_invoice_fx_settlement',p_invoice_id::text||':invoice',
      public.erp_next_document_number(p_company_id,'purchase_invoice_journal','PIJ',v_effective),
      'فاتورة شراء متعددة العملات '||d.document_number,v_currency,v_invoice_lines,v_effective);
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object('currency',v_currency,'journalEntryId',v_entry,'mode','supplier'));
    for k,lines in select key,value from jsonb_each(v_by_currency) loop
      v_settlement_id:=v_settlement->>k;
      lines:=lines||jsonb_build_array(jsonb_build_object(
        'accountId',v_settlement_id,'debit',0,
        'credit',(select coalesce(sum(public.erp_try_numeric(value->>'debit',0)),0) from jsonb_array_elements(lines)),
        'description','تسوية تحويل عملة المشتريات'));
      v_entry:=public.erp_phase2_insert_journal_at(
        p_company_id,'purchase_inventory_fx_settlement_'||lower(k),p_invoice_id::text||':'||k,
        public.erp_next_document_number(p_company_id,'purchase_inventory_journal_'||lower(k),'PIV',v_effective),
        'إثبات مخزون الشراء حسب التعريف '||d.document_number,k,lines,v_effective);
      v_entries:=v_entries||jsonb_build_array(jsonb_build_object('currency',k,'journalEntryId',v_entry,'mode','inventory'));
    end loop;
  end if;

  update public.erp_commercial_workflow_documents set
    payload=(payload-'journalEntryId'-'costJournalEntries')||jsonb_build_object(
      'journalEntryId',v_entries->0->>'journalEntryId','costJournalEntries',v_entries,
      'v760NoCapitalizationNormalized',true,'v760NormalizedAt',now(),
      'accountingPolicy','definition_accounts_no_capitalization'),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=p_invoice_id;
  return jsonb_build_object('ok',true,'journalEntries',v_entries);
end;
$$;

create or replace function public.erp_v760_approve_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
  r:=public.erp_v750_approve_workflow_invoice_resilient(p_company_id,p_invoice_id,p_module);
  if p_module='purchases' then
    r:=coalesce(r,'{}'::jsonb)||jsonb_build_object(
      'noCapitalization',public.erp_v760_normalize_purchase_invoice_posting(p_company_id,p_invoice_id));
  end if;
  return r;
end;
$$;

create or replace function public.erp_approve_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin perform public.erp_v760_approve_workflow_invoice(p_company_id,p_invoice_id,'sales'); end $$;

create or replace function public.erp_approve_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid
) returns void language plpgsql security definer set search_path=public as $$
begin perform public.erp_v760_approve_workflow_invoice(p_company_id,p_invoice_id,'purchases'); end $$;

create or replace function public.erp_manage_commercial_order_component_v2(
  p_company_id uuid,p_module text,p_order_id uuid,p_component_type text,
  p_component_id uuid,p_action text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; v_result jsonb;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  if p_component_type='order' and p_action='delete' and p_module='sales' then
    return public.erp_delete_cloud_sales_order_v4(p_company_id,p_order_id);
  end if;
  if p_component_type='invoice' then
    select * into d from public.erp_commercial_workflow_documents
     where company_id=p_company_id and id=p_component_id and parent_id=p_order_id
       and module=p_module and document_type='invoice' and not is_deleted for update;
    if not found then raise exception 'workflow_component_not_found'; end if;
    if p_action='approve' then
      return public.erp_v760_approve_workflow_invoice(p_company_id,p_component_id,p_module);
    elsif p_action='delete' and d.status='draft' then
      update public.erp_commercial_workflow_documents set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
        payload=payload||jsonb_build_object('deleteReason',coalesce(nullif(btrim(p_reason),''),'Draft invoice deleted'))
       where company_id=p_company_id and id=p_component_id;
      perform public.erp_v73_recompute_commercial_order_status(p_company_id,p_module,p_order_id);
      return jsonb_build_object('ok',true,'componentType','invoice','action','delete','draftDeleted',true);
    end if;
  end if;
  return public.erp_manage_commercial_order_component(
    p_company_id,p_module,p_order_id,p_component_type,p_component_id,p_action,p_reason);
end;
$$;

create or replace function public.erp_cloud_trial_balance(p_company_id uuid,p_currency text)
returns jsonb language sql security definer set search_path=public as $$
  with line_totals as (
    select jl.data->>'accountId' account_id,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) movement_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) movement_credit
    from public.erp_journal_lines jl
    join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      and not je.is_deleted and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
    where jl.company_id=p_company_id and not jl.is_deleted
      and upper(coalesce(jl.data->>'currency',je.data->>'currency',''))=upper(p_currency)
    group by jl.data->>'accountId'
  ), balances as (
    select a.account_id,a.account_type,coalesce(a.opening_balance,0) opening_balance,
      coalesce(l.movement_debit,0) movement_debit,coalesce(l.movement_credit,0) movement_credit,
      public.erp_v759_normal_balance(a.account_type,a.opening_balance,l.movement_debit,l.movement_credit) natural_balance
    from public.erp_accounts a left join line_totals l on l.account_id=a.account_id
    where a.organization_id=p_company_id and a.is_active and upper(a.currency)=upper(p_currency)
      and public.is_active_company_member(p_company_id)
  ), sides as (
    select *,case when public.erp_v760_is_credit_nature(account_type)
      then greatest(-natural_balance,0) else greatest(natural_balance,0) end closing_debit,
      case when public.erp_v760_is_credit_nature(account_type)
      then greatest(natural_balance,0) else greatest(-natural_balance,0) end closing_credit
    from balances
  )
  select jsonb_build_object(
    'debit',coalesce(sum(closing_debit),0),'credit',coalesce(sum(closing_credit),0),
    'movementDebit',coalesce(sum(movement_debit),0),'movementCredit',coalesce(sum(movement_credit),0),
    'difference',coalesce(sum(closing_debit),0)-coalesce(sum(closing_credit),0),
    'absoluteDifference',abs(coalesce(sum(closing_debit),0)-coalesce(sum(closing_credit),0))
  ) from sides;
$$;

create or replace function public.erp_v759_accounting_integrity_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  with entries as (
    select je.id,upper(coalesce(je.data->>'currency','')) currency,
      public.erp_try_numeric(je.data->>'totalDebit',0) header_debit,
      public.erp_try_numeric(je.data->>'totalCredit',0) header_credit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'debit',0)),0) lines_debit,
      coalesce(sum(public.erp_try_numeric(jl.data->>'credit',0)),0) lines_credit,
      count(*) filter(where public.erp_try_numeric(jl.data->>'debit',0)<0 or public.erp_try_numeric(jl.data->>'credit',0)<0
        or (public.erp_try_numeric(jl.data->>'debit',0)>0 and public.erp_try_numeric(jl.data->>'credit',0)>0)) invalid_lines
    from public.erp_journal_entries je left join public.erp_journal_lines jl
      on jl.company_id=je.company_id and jl.data->>'entryId'=je.id and not jl.is_deleted
    where je.company_id=p_company_id and not je.is_deleted
      and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
    group by je.id,je.data
  ), bad as (
    select * from entries where abs(lines_debit-lines_credit)>0.01 or invalid_lines>0
      or abs(header_debit-header_credit)>0.01
      or (header_debit>0 and abs(header_debit-lines_debit)>0.01)
      or (header_credit>0 and abs(header_credit-lines_credit)>0.01)
  ) select jsonb_build_object(
    'balanced',not exists(select 1 from bad),'unbalancedEntryCount',(select count(*) from bad),
    'unbalancedEntryIds',coalesce((select jsonb_agg(id) from bad),'[]'::jsonb),
    'invalidLineCount',coalesce((select sum(invalid_lines) from entries),0)
  );
$$;

-- Remove obsolete capitalization accounts when safe. Referenced historical
-- accounts are retained only as inactive audit records and are never selectable.
delete from public.erp_accounts a where a.code in ('1391','1392') and not exists(
  select 1 from public.erp_journal_lines jl where jl.company_id=a.organization_id
    and jl.data->>'accountId'=a.account_id and not jl.is_deleted);
update public.erp_accounts set is_active=false,
  name='حساب تاريخي متوقف - غير مستخدم تشغيلياً',source_updated_at=now()
 where code in ('1391','1392');

revoke all on function public.erp_v760_ensure_purchase_fx_settlement_accounts(uuid) from public,anon;
revoke all on function public.erp_v760_normalize_purchase_invoice_posting(uuid,uuid) from public,anon;
revoke all on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text) from public,anon;
grant execute on function public.erp_v760_is_credit_nature(text) to authenticated,service_role;
grant execute on function public.erp_v760_ensure_purchase_fx_settlement_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_v760_normalize_purchase_invoice_posting(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v760_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated,service_role;
grant execute on function public.erp_v759_accounting_integrity_audit(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
commit;
