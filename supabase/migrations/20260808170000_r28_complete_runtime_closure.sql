
begin;

-- R28 canonical cashbox read: only PostgreSQL row state is authoritative.
create or replace function public.erp_r28_list_cash_accounts(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select ca.data
    || jsonb_build_object(
      'id', ca.id,
      'accountId', nullif(btrim(coalesce(ca.data->>'account_id',ca.data->>'accountId','')),''),
      'account_id', nullif(btrim(coalesce(ca.data->>'account_id',ca.data->>'accountId','')),''),
      'createdAt', ca.created_at,
      'created_at', ca.created_at,
      'updatedAt', ca.updated_at,
      'updated_at', ca.updated_at,
      '_cloudCreatedAt', ca.created_at,
      '_cloudUpdatedAt', ca.updated_at,
      '_cloudVersion', ca.version,
      'ledgerAccountCode', a.code,
      'ledgerAccountName', a.name,
      'ledgerAccountCurrency', a.currency,
      'schemaVersion', 28,
      'schema_version', 28
    )
  from public.erp_cash_accounts ca
  left join public.erp_accounts a
    on a.organization_id=ca.company_id
   and a.account_id=nullif(btrim(coalesce(ca.data->>'account_id',ca.data->>'accountId','')),'')
  where ca.company_id=p_company_id
    and not ca.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true') desc,
           lower(coalesce(ca.data->>'name','')),ca.id
$$;
revoke all on function public.erp_r28_list_cash_accounts(uuid) from public,anon;
grant execute on function public.erp_r28_list_cash_accounts(uuid) to authenticated,service_role;

-- R28 save: the account selected by the current form always wins. We lock the
-- row, refresh the concurrency token from PostgreSQL, validate currency/type,
-- and write both aliases from the same ledger id.
create or replace function public.erp_r28_save_cash_account(p_company_id uuid,p_account jsonb)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_in jsonb:=coalesce(p_account,'{}'::jsonb);
  v_id text:=btrim(coalesce(v_in->>'id',''));
  v_current jsonb;
  v_current_updated timestamptz;
  v_ledger text;
  v_currency text;
  v_type text;
  v_ledger_currency text;
  v_ledger_type text;
  v_payload jsonb;
  v_saved jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied' using errcode='42501';
  end if;
  if v_id='' then raise exception 'cashbox_id_required'; end if;

  select ca.data,ca.updated_at
    into v_current,v_current_updated
  from public.erp_cash_accounts ca
  where ca.company_id=p_company_id and ca.id=v_id and not ca.is_deleted
  for update;

  if v_current is null then
    v_current:='{}'::jsonb;
    v_current_updated:=clock_timestamp();
  end if;

  v_ledger:=nullif(btrim(coalesce(nullif(v_in->>'account_id',''),nullif(v_in->>'accountId',''))),'');
  if v_ledger is null then raise exception 'cashbox_ledger_account_required'; end if;

  v_currency:=upper(coalesce(nullif(btrim(v_in->>'currency'),''),
                             nullif(btrim(v_current->>'currency'),''),
                             'USD'));
  v_type:=coalesce(nullif(btrim(v_in->>'type'),''),
                   nullif(btrim(v_current->>'type'),''),
                   'cash');

  select upper(a.currency),lower(a.account_type)
    into v_ledger_currency,v_ledger_type
  from public.erp_accounts a
  where a.organization_id=p_company_id
    and a.account_id=v_ledger
    and a.is_active;

  if v_ledger_currency is null then
    raise exception 'cashbox_ledger_account_not_found:%',v_ledger using errcode='23503';
  end if;
  if v_ledger_type<>'asset' then
    raise exception 'cashbox_ledger_account_must_be_asset:%',v_ledger using errcode='23514';
  end if;
  if v_ledger_currency not in (v_currency,'MULTI') then
    raise exception 'cashbox_ledger_currency_mismatch:%:%',v_currency,v_ledger_currency using errcode='23514';
  end if;

  if exists(
    select 1
    from public.erp_cash_accounts x
    where x.company_id=p_company_id
      and x.id<>v_id
      and not x.is_deleted
      and public.erp_try_boolean(coalesce(x.data->>'isActive',x.data->>'is_active'),'true')
      and nullif(btrim(coalesce(x.data->>'account_id',x.data->>'accountId','')),'')=v_ledger
  ) then
    raise exception 'cashbox_ledger_account_already_bound:%',v_ledger using errcode='23505';
  end if;

  v_payload:=v_current || v_in || jsonb_build_object(
    'id',v_id,
    'type',v_type,
    'currency',v_currency,
    'accountId',v_ledger,
    'account_id',v_ledger,
    -- Force the row timestamp that was locked above. This prevents a stale
    -- embedded alias from rejecting the user's current save.
    'updatedAt',v_current_updated,
    'updated_at',v_current_updated,
    'schemaVersion',28,
    'schema_version',28
  );

  perform public.erp_save_cloud_cash_account(p_company_id,v_payload);

  select ca.data || jsonb_build_object(
      'id',ca.id,
      'accountId',nullif(btrim(coalesce(ca.data->>'account_id',ca.data->>'accountId','')),''),
      'account_id',nullif(btrim(coalesce(ca.data->>'account_id',ca.data->>'accountId','')),''),
      'createdAt',ca.created_at,'created_at',ca.created_at,
      'updatedAt',ca.updated_at,'updated_at',ca.updated_at,
      '_cloudCreatedAt',ca.created_at,'_cloudUpdatedAt',ca.updated_at,
      '_cloudVersion',ca.version,'schemaVersion',28,'schema_version',28)
    into v_saved
  from public.erp_cash_accounts ca
  where ca.company_id=p_company_id and ca.id=v_id and not ca.is_deleted;

  return coalesce(v_saved,'{}'::jsonb);
end $$;
revoke all on function public.erp_r28_save_cash_account(uuid,jsonb) from public,anon;
grant execute on function public.erp_r28_save_cash_account(uuid,jsonb) to authenticated,service_role;

-- R28 cash transaction read: operational date and audit creation date are two
-- different authoritative timestamps. Never synthesize Unix epoch.
create or replace function public.erp_r28_list_cash_transactions(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select ct.data || jsonb_build_object(
    'id',ct.id,
    'transactionDate',coalesce(
      nullif(ct.data->>'transactionDate',''),
      nullif(ct.data->>'transaction_date',''),
      ct.created_at::text
    ),
    'createdAt',ct.created_at,
    'created_at',ct.created_at,
    'updatedAt',ct.updated_at,
    'updated_at',ct.updated_at,
    '_cloudCreatedAt',ct.created_at,
    '_cloudUpdatedAt',ct.updated_at,
    '_cloudVersion',ct.version,
    'performedBy',coalesce(pr.full_name,ct.created_by::text)
  )
  from public.erp_cash_transactions ct
  left join public.profiles pr on pr.id=ct.created_by
  where ct.company_id=p_company_id
    and not ct.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by public.erp_try_timestamptz(
    coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date'),
    ct.created_at
  ) desc,ct.created_at desc,ct.id desc
$$;
revoke all on function public.erp_r28_list_cash_transactions(uuid) from public,anon;
grant execute on function public.erp_r28_list_cash_transactions(uuid) to authenticated,service_role;

-- R28 movement log keeps the proven R27 commercial semantics while exposing
-- a stable versioned endpoint for the UI.
create or replace function public.erp_r28_inventory_movement_log(
  p_company_id uuid,p_product_id text default null
) returns setof jsonb
language sql stable security definer set search_path=public
as $$ select * from public.erp_r27_inventory_movement_log($1,$2) $$;
revoke all on function public.erp_r28_inventory_movement_log(uuid,text) from public,anon;
grant execute on function public.erp_r28_inventory_movement_log(uuid,text) to authenticated,service_role;

-- R28 complete commercial details. Preserve the mature V2300 payload and
-- enrich workflow rows with approver/user names and complete allocations.
create or replace function public.erp_r28_get_commercial_order_complete_details(
  p_company_id uuid,p_order_id uuid,p_purchase boolean
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v jsonb;
  v_module text:=case when p_purchase then 'purchases' else 'sales' end;
  v_logistics jsonb;
  v_invoices jsonb;
  v_payments jsonb;
  v_movements jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied' using errcode='42501';
  end if;
  v:=public.erp_v2300_get_commercial_order_complete_details(
    p_company_id,p_order_id,p_purchase);

  select coalesce(jsonb_agg(
    coalesce(e.value,'{}'::jsonb) ||
    jsonb_build_object(
      'payload',coalesce(d.payload,'{}'::jsonb),
      'allocations',coalesce(d.payload->'allocations','[]'::jsonb),
      'warehouseIds',coalesce(d.payload->'warehouseIds','[]'::jsonb),
      'createdAt',d.created_at,'updatedAt',d.updated_at,'effectiveAt',d.effective_at,
      'performedBy',coalesce(pc.full_name,d.created_by::text),
      'approvedBy',coalesce(pa.full_name,aa.performed_by::text),
      'approvedAt',aa.performed_at,
      'approvalAction',aa.action,
      'sourceName',case
        when p_purchase then coalesce(v->'order'->>'partnerName','Supplier')
        else coalesce(
          nullif(e.value->>'warehouseName',''),
          nullif(d.payload->>'warehouseName',''),
          'Warehouse'
        )
      end,
      'destinationName',case
        when p_purchase then coalesce(
          nullif(e.value->>'warehouseName',''),
          nullif(d.payload->>'warehouseName',''),
          'Warehouse'
        )
        else coalesce(v->'order'->>'partnerName','Customer')
      end
    )
    order by e.ordinality),'[]'::jsonb)
  into v_logistics
  from jsonb_array_elements(coalesce(v->'logistics','[]'::jsonb))
       with ordinality e(value,ordinality)
  left join public.erp_commercial_workflow_documents d
    on d.company_id=p_company_id and d.id::text=e.value->>'id'
  left join public.profiles pc on pc.id=d.created_by
  left join lateral (
    select a.performed_by,a.performed_at,a.action
    from public.erp_commercial_workflow_audit a
    where a.company_id=p_company_id
      and a.document_id=d.id
      and lower(coalesce(a.to_status,'')) in ('approved','received','delivered','completed')
    order by a.performed_at desc,a.id desc limit 1
  ) aa on true
  left join public.profiles pa on pa.id=aa.performed_by;

  select coalesce(jsonb_agg(
    coalesce(e.value,'{}'::jsonb) ||
    jsonb_build_object(
      'payload',coalesce(d.payload,'{}'::jsonb),
      'createdAt',d.created_at,'updatedAt',d.updated_at,'effectiveAt',d.effective_at,
      'createdByName',coalesce(pc.full_name,d.created_by::text),
      'approvedBy',coalesce(pa.full_name,aa.performed_by::text),
      'approvedAt',coalesce(aa.performed_at,public.erp_try_timestamptz(d.payload->>'approvedAt',null))
    )
    order by e.ordinality),'[]'::jsonb)
  into v_invoices
  from jsonb_array_elements(coalesce(v->'invoices','[]'::jsonb))
       with ordinality e(value,ordinality)
  left join public.erp_commercial_workflow_documents d
    on d.company_id=p_company_id and d.id::text=e.value->>'id'
  left join public.profiles pc on pc.id=d.created_by
  left join lateral (
    select a.performed_by,a.performed_at
    from public.erp_commercial_workflow_audit a
    where a.company_id=p_company_id and a.document_id=d.id
      and lower(coalesce(a.to_status,'')) in ('approved','paid','completed')
    order by a.performed_at desc,a.id desc limit 1
  ) aa on true
  left join public.profiles pa on pa.id=aa.performed_by;

  select coalesce(jsonb_agg(
    coalesce(e.value,'{}'::jsonb) ||
    jsonb_build_object(
      'transactionDate',coalesce(
        nullif(ct.data->>'transactionDate',''),
        nullif(ct.data->>'transaction_date',''),
        e.value->>'paymentDate',
        ct.created_at::text
      ),
      'createdAt',ct.created_at,
      'createdBy',coalesce(pr.full_name,ct.created_by::text),
      'voucherNumber',coalesce(ct.data->>'voucherNumber',e.value->>'voucherNumber'),
      'cashAccountName',coalesce(ca.data->>'name',e.value->>'cashAccountName'),
      'cashAccountCurrency',coalesce(ca.data->>'currency',e.value->>'paymentCurrency')
    )
    order by e.ordinality),'[]'::jsonb)
  into v_payments
  from jsonb_array_elements(coalesce(v->'payments','[]'::jsonb))
       with ordinality e(value,ordinality)
  left join public.erp_cash_transactions ct
    on ct.company_id=p_company_id
   and ct.id=coalesce(e.value->>'cashTransactionId',e.value->>'paymentId')
   and not ct.is_deleted
  left join public.erp_cash_accounts ca
    on ca.company_id=p_company_id
   and ca.id=coalesce(ct.data->>'cashAccountId',e.value->>'cashAccountId')
   and not ca.is_deleted
  left join public.profiles pr on pr.id=ct.created_by;

  select coalesce(jsonb_agg(
    coalesce(m.value,'{}'::jsonb) ||
    coalesce((
      select x from public.erp_r28_inventory_movement_log(p_company_id,null) x
      where x->>'id'=m.value->>'id' limit 1
    ),'{}'::jsonb)
    order by m.ordinality),'[]'::jsonb)
  into v_movements
  from jsonb_array_elements(coalesce(v->'movements','[]'::jsonb))
       with ordinality m(value,ordinality);

  return jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(coalesce(v,'{}'::jsonb),'{logistics}',coalesce(v_logistics,'[]'::jsonb),true),
        '{invoices}',coalesce(v_invoices,'[]'::jsonb),true),
      '{payments}',coalesce(v_payments,'[]'::jsonb),true),
    '{movements}',coalesce(v_movements,'[]'::jsonb),true);
end $$;
revoke all on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean) from public,anon;
grant execute on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean) to authenticated,service_role;

grant usage on schema public to authenticated,service_role;
notify pgrst,'reload schema';
commit;
