-- Quality Line ERP 18.8.0
-- Final remote PostgreSQL lint repair after the 18.8.0 operational migrations.
-- This migration is additive and must not replace or edit migrations already applied.

begin;

-- 1) Manual journal editor: use the normalized chart-of-accounts table.
create or replace function public.erp_update_cloud_manual_journal(
  p_company_id uuid,
  p_entry jsonb,
  p_lines jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry_id text := nullif(btrim(p_entry->>'id'), '');
  v_currency text := upper(coalesce(nullif(btrim(p_entry->>'currency'), ''), ''));
  v_debit numeric := 0;
  v_credit numeric := 0;
  v_line jsonb;
  v_account_id text;
  v_account_currency text;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if v_entry_id is null then raise exception 'entry id required'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'invalid currency'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 2 then
    raise exception 'journal requires at least two lines';
  end if;
  if not exists (
    select 1 from public.erp_journal_entries
    where company_id=p_company_id and not is_deleted and data->>'id'=v_entry_id
  ) then raise exception 'journal entry not found'; end if;
  if coalesce(p_entry->>'referenceType','') <> '' then
    raise exception 'system generated journal cannot be edited manually';
  end if;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    if v_line->>'entryId' <> v_entry_id then raise exception 'line entry mismatch'; end if;
    v_account_id := nullif(btrim(v_line->>'accountId'), '');
    if v_account_id is null then raise exception 'account required'; end if;
    select upper(coalesce(account.currency, '')) into v_account_currency
    from public.erp_accounts account
    where account.organization_id = p_company_id
      and account.account_id = v_account_id
      and account.is_active
    limit 1;
    if v_account_currency is null then raise exception 'account not found'; end if;
    if v_account_currency not in (v_currency,'MULTI') then raise exception 'account currency mismatch'; end if;
    if coalesce((v_line->>'debit')::numeric,0) < 0 or coalesce((v_line->>'credit')::numeric,0) < 0 then
      raise exception 'negative journal amount';
    end if;
    if (coalesce((v_line->>'debit')::numeric,0) > 0) = (coalesce((v_line->>'credit')::numeric,0) > 0) then
      raise exception 'each line must have debit xor credit';
    end if;
    v_debit := v_debit + coalesce((v_line->>'debit')::numeric,0);
    v_credit := v_credit + coalesce((v_line->>'credit')::numeric,0);
  end loop;
  if v_debit <= 0 or abs(v_debit-v_credit) > 0.01 then raise exception 'journal is not balanced'; end if;

  update public.erp_journal_entries
  set data = p_entry || jsonb_build_object(
        'totalDebit', v_debit,
        'totalCredit', v_credit,
        'updatedAt', now()
      ), updated_at=now()
  where company_id=p_company_id and not is_deleted and data->>'id'=v_entry_id;

  update public.erp_journal_lines
  set is_deleted=true, updated_at=now()
  where company_id=p_company_id and not is_deleted and data->>'entryId'=v_entry_id;

  for v_line in select value from jsonb_array_elements(p_lines) loop
    insert into public.erp_journal_lines(company_id,id,data,is_deleted)
    values(
      p_company_id,
      coalesce(nullif(v_line->>'id','')::uuid, gen_random_uuid()),
      v_line,
      false
    );
  end loop;
end $$;

-- 2) Purchase order opportunity overload: keep the eight-argument RPC exact.
-- Removing defaults from the overload prevents seven-argument calls from being ambiguous.
drop function if exists public.erp_create_cloud_purchase_order(
  uuid, text, text, numeric, jsonb, numeric, text, text
);

create or replace function public.erp_create_cloud_purchase_order(
  p_company_id uuid,p_supplier_id text,p_currency text,p_exchange_rate numeric,
  p_items jsonb,p_discount numeric,p_notes text,p_opportunity_id text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_existing uuid;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is not null then
    select id into v_existing from public.erp_purchase_orders_cloud
    where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
    order by updated_at desc limit 1;
    if v_existing is not null then return v_existing; end if;
  end if;
  v_id:=public.erp_create_cloud_purchase_order(p_company_id,p_supplier_id,p_currency,p_exchange_rate,p_items,p_discount,p_notes);
  update public.erp_purchase_orders_cloud set opportunity_id=nullif(btrim(coalesce(p_opportunity_id,'')),'') where id=v_id;
  return v_id;
end $$;

-- 3) Operational readiness: use Supabase Auth rather than the retired Firebase helper.
create or replace function public.erp_operational_readiness(
  p_company_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_modules jsonb;
begin
  if p_company_id is null then
    raise exception 'company_id_required' using errcode = '22023';
  end if;

  if v_user_id is null or not public.erp_is_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode = '42501';
  end if;

  v_modules := jsonb_build_object(
    'cars', to_regclass('public.erp_cars') is not null,
    'customers', to_regclass('public.erp_customers') is not null,
    'suppliers', to_regclass('public.erp_suppliers') is not null,
    'sales', to_regclass('public.erp_sales') is not null,
    'purchases', to_regclass('public.erp_purchases') is not null
      and to_regclass('public.erp_purchase_items') is not null,
    'installments', to_regclass('public.erp_installments') is not null,
    'inventory', to_regclass('public.erp_inventory') is not null
      and to_regclass('public.erp_warehouse_stock') is not null,
    'accounting', to_regclass('public.erp_accounts') is not null
      and to_regclass('public.erp_journal_entries') is not null,
    'cashbox', to_regclass('public.erp_cash_transactions') is not null,
    'documents', to_regclass('public.erp_commercial_workflow_documents') is not null
  );

  return jsonb_build_object(
    'ok', not exists (
      select 1 from jsonb_each(v_modules) item where item.value <> 'true'::jsonb
    ),
    'company_id', p_company_id,
    'user_id', v_user_id,
    'firebase_uid', v_user_id::text,
    'modules', v_modules,
    'checked_at', timezone('utc', now())
  );
end;
$$;

-- 4) Inventory accounting: nested numeric fallback instead of a text default.
create or replace function public.erp_phase2_post_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare doc public.erp_commercial_workflow_documents%rowtype; ord public.erp_sales_orders_cloud%rowtype;
 a record; ac jsonb; lines jsonb:='[]'; amount numeric; cost numeric; eid text; oldid text;
begin
 select * into doc from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_delivery_id and module='sales' and document_type='delivery' and not is_deleted;
 if not found or doc.status<>'approved' then raise exception 'يجب تصديق أمر التجهيز أولاً'; end if;
 select * into ord from public.erp_sales_orders_cloud where company_id=p_company_id and id=doc.parent_id and not is_deleted;
 oldid:=doc.payload->>'costJournalEntryId';
 if oldid is not null then
   update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and data->>'entryId'=oldid and not is_deleted;
   update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=oldid and not is_deleted;
 end if;
 for a in select x.item_type,x.item_id,x.description,x.quantity from public.erp_sales_order_items_cloud x where x.company_id=p_company_id and x.order_id=ord.id and not x.is_deleted loop
   ac:=public.erp_phase2_item_accounts(p_company_id,a.item_type,a.item_id,ord.currency);
   if a.item_type='car' then select coalesce(public.erp_try_numeric(data->>'purchasePrice',0),0) into cost from public.erp_cars where company_id=p_company_id and id=a.item_id;
   else select coalesce(public.erp_try_numeric(data->>'averageUnitCost', public.erp_try_numeric(data->>'purchasePrice', 0)),0) into cost from public.erp_inventory where company_id=p_company_id and id=a.item_id; end if;
   amount:=a.quantity*cost;
   if amount>0 then lines:=lines||jsonb_build_array(
    jsonb_build_object('accountId',ac->>'costExpenseAccountId','debit',amount,'credit',0,'description','تكلفة بيع '||a.description,'itemId',a.item_id),
    jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج مخزون '||a.description,'itemId',a.item_id)); end if;
 end loop;
 if jsonb_array_length(lines)=0 then return null; end if;
 eid:=public.erp_phase2_insert_journal(p_company_id,'sales_inventory_cost',p_delivery_id::text,
  'COGS-'||replace(p_delivery_id::text,'-',''),'تكلفة تجهيز مبيعات '||doc.document_number,ord.currency,lines);
 update public.erp_commercial_workflow_documents set payload=(payload-'costJournalEntryId')||jsonb_build_object('costJournalEntryId',eid,'accountingPostedAt',now()),updated_at=now() where id=p_delivery_id;
 return eid;
end $$;

create or replace function public.erp_phase2_post_scrap(
 p_company_id uuid,p_warehouse_id text,p_reference_id text,p_currency text,p_items jsonb,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare w public.erp_warehouses%rowtype; i jsonb; ac jsonb; qty numeric; cost numeric; amount numeric; lines jsonb:='[]'; expense text; eid text;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 select * into w from public.erp_warehouses where company_id=p_company_id and id=p_warehouse_id and not is_deleted for update;
 if not found then raise exception 'مخزن التوالف غير موجود'; end if;
 expense:=nullif(coalesce(w.data->>'scrapExpenseAccountId',w.data->>'scrap_expense_account_id'),'');
 perform public.erp_phase2_account_guard(p_company_id,expense,'expense',p_currency);
 for i in select value from jsonb_array_elements(p_items) loop
   qty:=public.erp_try_numeric(i->>'quantity',0); if qty<=0 then raise exception 'كمية التلف غير صحيحة'; end if;
   ac:=public.erp_phase2_item_accounts(p_company_id,coalesce(i->>'itemType','product'),i->>'itemId',p_currency);
   if coalesce(i->>'itemType','product')='car' then select public.erp_try_numeric(data->>'purchasePrice',0) into cost from public.erp_cars where company_id=p_company_id and id=i->>'itemId';
   else select public.erp_try_numeric(data->>'averageUnitCost', public.erp_try_numeric(data->>'purchasePrice', 0)) into cost from public.erp_inventory where company_id=p_company_id and id=i->>'itemId'; end if;
   amount:=qty*coalesce(cost,0);
   lines:=lines||jsonb_build_array(
    jsonb_build_object('accountId',expense,'debit',amount,'credit',0,'description','تالف/استهلاك '||coalesce(i->>'description',i->>'itemId')),
    jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج أصل مخزني'));
 end loop;
 eid:=public.erp_phase2_insert_journal(p_company_id,'inventory_scrap',p_reference_id,'SCRAP-'||replace(p_reference_id,'-',''),'قيد تلف واستهلاك '||coalesce(p_notes,''),p_currency,lines);
 return eid;
end $$;

-- 5) Maintenance lines: nested numeric fallback instead of a text default.
create or replace function public.erp_phase3_prepare_maintenance_lines(
  p_company_id uuid,p_order_id uuid,p_currency text,p_lines jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x jsonb; v_product text; v_warehouse text; v_qty numeric; v_name text;
 v_cost numeric; v_price numeric; v_available numeric; v_type text; v_stock public.erp_warehouse_stock%rowtype;
 v_cost_total numeric:=0; v_price_total numeric:=0; v_seen text[]:=array[]::text[];
begin
 if upper(coalesce(p_currency,'')) not in ('USD','IQD') then raise exception 'عملة أمر الصيانة غير مدعومة'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 then raise exception 'أضف بند صيانة واحداً على الأقل'; end if;
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 for x in select value from jsonb_array_elements(p_lines) loop
   v_product:=nullif(x->>'product_id',''); v_warehouse:=nullif(x->>'warehouse_id','');
   v_qty:=public.erp_try_numeric(x->>'quantity',0); v_price:=public.erp_try_numeric(x->>'unit_price',0);
   if v_product is null or v_qty<=0 or trunc(v_qty)<>v_qty or v_price<0 then raise exception 'بيانات بند الصيانة غير صحيحة'; end if;
   if v_product=any(v_seen) then raise exception 'لا يمكن تكرار المادة أو الخدمة في أمر الصيانة'; end if;
   v_seen:=array_append(v_seen,v_product);
   select coalesce(data->>'name',data->>'nameAr'),lower(coalesce(data->>'itemType',data->>'item_type','stock')),
          public.erp_try_numeric(data->>'unitCost', public.erp_try_numeric(data->>'purchasePrice', 0))
     into v_name,v_type,v_cost from public.erp_inventory
    where company_id=p_company_id and id=v_product and not is_deleted
      and coalesce((data->>'isActive')::boolean,true);
   if not found then raise exception 'بند الصيانة غير موجود أو غير فعال'; end if;
   if v_type='service' then
     v_warehouse:=null; v_cost:=0;
   else
     if v_warehouse is null then raise exception 'يجب اختيار مخزن لكل مادة مخزنية'; end if;
     if not exists(select 1 from public.erp_warehouses where company_id=p_company_id and id=v_warehouse and not is_deleted) then
       raise exception 'مخزن السحب غير موجود';
     end if;
     select * into v_stock from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted
       and data->>'warehouseId'=v_warehouse and data->>'productId'=v_product for update;
     v_available:=case when found then public.erp_try_numeric(v_stock.data->>'quantity',0) else 0 end;
     if v_available<v_qty then raise exception 'الرصيد غير كافٍ للمادة %',coalesce(v_name,v_product); end if;
     if found and public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)>0 then
       v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
     end if;
     perform public.erp_phase2_item_accounts(p_company_id,'product',v_product,upper(p_currency));
   end if;
   insert into public.erp_maintenance_parts(company_id,maintenance_order_id,product_id,product_name,warehouse_id,quantity,unit_cost,total_cost,line_type,unit_price,line_total_price)
   values(p_company_id,p_order_id,v_product::uuid,coalesce(v_name,v_product),v_warehouse::uuid,v_qty::integer,coalesce(v_cost,0),coalesce(v_cost,0)*v_qty,v_type,v_price,v_price*v_qty);
   v_cost_total:=v_cost_total+coalesce(v_cost,0)*v_qty; v_price_total:=v_price_total+v_price*v_qty;
 end loop;
 return jsonb_build_object('costTotal',v_cost_total,'priceTotal',v_price_total);
end $$;

-- 6) Partner card documents: count the canonical workflow documents.
create or replace function public.erp_business_partner_card_summary(
  p_company_id uuid,
  p_partner_kind text,
  p_partner_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_kind text := lower(coalesce(p_partner_kind, ''));
  v_partner jsonb := '{}'::jsonb;
  v_documents jsonb := '[]'::jsonb;
  v_currencies jsonb := '[]'::jsonb;
  v_document_count bigint := 0;
  v_transaction_count bigint := 0;
  v_payment_count bigint := 0;
  v_total numeric := 0;
  v_paid numeric := 0;
  v_outstanding numeric := 0;
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied';
  end if;

  if v_kind = 'customer' then
    select coalesce(data, '{}'::jsonb) into v_partner
    from public.erp_customers
    where company_id = p_company_id and id = p_partner_id and not is_deleted;

    select
      count(*),
      coalesce(sum(public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0)), 0),
      coalesce(sum(public.erp_try_numeric(data->>'paidAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) -
          public.erp_try_numeric(data->>'paidAmount', 0)
      )), 0),
      coalesce(sum(case when jsonb_typeof(data->'payments') = 'array'
        then jsonb_array_length(data->'payments') else 0 end), 0)
    into v_transaction_count, v_total, v_paid, v_outstanding, v_payment_count
    from public.erp_sales
    where company_id = p_company_id and not is_deleted
      and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc), '[]'::jsonb)
    into v_documents
    from (
      select
        coalesce(nullif(data->>'invoiceNumber',''), nullif(data->>'saleNumber',''), id) document_number,
        coalesce(data->>'saleDate', data->>'createdAt', created_at::text) document_date,
        upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency,
        public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) total_amount,
        public.erp_try_numeric(data->>'paidAmount', 0) paid_amount,
        public.erp_try_numeric(
          data->>'remainingAmount',
          public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) -
            public.erp_try_numeric(data->>'paidAmount', 0)
        ) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''), nullif(data->>'status',''), 'open') status
      from public.erp_sales
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id
      order by coalesce(data->>'saleDate', data->>'createdAt', created_at::text) desc
      limit 12
    ) x;

    select coalesce(jsonb_agg(currency order by currency), '[]'::jsonb)
    into v_currencies
    from (
      select distinct upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency
      from public.erp_sales
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id
    ) currencies;

    select count(*)
    into v_document_count
    from public.erp_commercial_workflow_documents document
    join public.erp_sales_orders_cloud sales_order
      on sales_order.company_id = document.company_id
     and sales_order.id = document.parent_id
     and not sales_order.is_deleted
    where document.company_id = p_company_id
      and document.module = 'sales'
      and not document.is_deleted
      and sales_order.customer_id = p_partner_id;
  elsif v_kind = 'supplier' then
    select coalesce(data, '{}'::jsonb) into v_partner
    from public.erp_suppliers
    where company_id = p_company_id and id = p_partner_id and not is_deleted;

    select
      count(*),
      coalesce(sum(public.erp_try_numeric(data->>'totalAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(data->>'paidAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(data->>'totalAmount', 0) - public.erp_try_numeric(data->>'paidAmount', 0)
      )), 0),
      coalesce(sum(case when jsonb_typeof(data->'payments') = 'array'
        then jsonb_array_length(data->'payments') else 0 end), 0)
    into v_transaction_count, v_total, v_paid, v_outstanding, v_payment_count
    from public.erp_purchases
    where company_id = p_company_id and not is_deleted
      and coalesce(data->>'supplierId', '') = p_partner_id;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc), '[]'::jsonb)
    into v_documents
    from (
      select
        coalesce(nullif(data->>'invoiceNumber',''), nullif(data->>'purchaseNumber',''), id) document_number,
        coalesce(data->>'purchaseDate', data->>'createdAt', created_at::text) document_date,
        upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency,
        public.erp_try_numeric(data->>'totalAmount', 0) total_amount,
        public.erp_try_numeric(data->>'paidAmount', 0) paid_amount,
        public.erp_try_numeric(
          data->>'remainingAmount',
          public.erp_try_numeric(data->>'totalAmount', 0) - public.erp_try_numeric(data->>'paidAmount', 0)
        ) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''), nullif(data->>'status',''), 'open') status
      from public.erp_purchases
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'supplierId', '') = p_partner_id
      order by coalesce(data->>'purchaseDate', data->>'createdAt', created_at::text) desc
      limit 12
    ) x;

    select coalesce(jsonb_agg(currency order by currency), '[]'::jsonb)
    into v_currencies
    from (
      select distinct upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency
      from public.erp_purchases
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'supplierId', '') = p_partner_id
    ) currencies;

    select count(*)
    into v_document_count
    from public.erp_commercial_workflow_documents document
    join public.erp_purchase_orders_cloud purchase_order
      on purchase_order.company_id = document.company_id
     and purchase_order.id = document.parent_id
     and not purchase_order.is_deleted
    where document.company_id = p_company_id
      and document.module = 'purchases'
      and not document.is_deleted
      and purchase_order.supplier_id = p_partner_id;
  else
    raise exception 'unsupported_partner_kind';
  end if;

  return jsonb_build_object(
    'partnerKind', v_kind,
    'partnerId', p_partner_id,
    'accountId', coalesce(
      v_partner->>'ledgerAccountId',
      v_partner->>'accountId',
      v_partner->>'receivableAccountId',
      v_partner->>'payableAccountId'
    ),
    'openingBalance', public.erp_try_numeric(coalesce(v_partner->>'openingBalance', v_partner->>'opening_balance'), 0),
    'defaultCurrency', upper(coalesce(nullif(v_partner->>'currency',''), 'USD')),
    'currencies', v_currencies,
    'transactionCount', v_transaction_count,
    'transactionTotal', v_total,
    'paidTotal', v_paid,
    'outstandingTotal', v_outstanding,
    'paymentCount', v_payment_count,
    'linkedDocumentCount', v_document_count,
    'recentDocuments', v_documents
  );
end;
$$;

revoke all on function public.erp_update_cloud_manual_journal(uuid, jsonb, jsonb) from public;
grant execute on function public.erp_update_cloud_manual_journal(uuid, jsonb, jsonb) to authenticated;

revoke all on function public.erp_create_cloud_purchase_order(
  uuid, text, text, numeric, jsonb, numeric, text, text
) from public;
grant execute on function public.erp_create_cloud_purchase_order(
  uuid, text, text, numeric, jsonb, numeric, text, text
) to authenticated;

revoke all on function public.erp_operational_readiness(uuid) from public;
grant execute on function public.erp_operational_readiness(uuid) to authenticated;

revoke all on function public.erp_phase2_post_sales_delivery(uuid, uuid) from public;
grant execute on function public.erp_phase2_post_sales_delivery(uuid, uuid) to authenticated;

revoke all on function public.erp_phase2_post_scrap(
  uuid, text, text, text, jsonb, text
) from public;
grant execute on function public.erp_phase2_post_scrap(
  uuid, text, text, text, jsonb, text
) to authenticated;

revoke all on function public.erp_phase3_prepare_maintenance_lines(
  uuid, uuid, text, jsonb
) from public;
grant execute on function public.erp_phase3_prepare_maintenance_lines(
  uuid, uuid, text, jsonb
) to authenticated;

revoke all on function public.erp_business_partner_card_summary(
  uuid, text, text
) from public;
grant execute on function public.erp_business_partner_card_summary(
  uuid, text, text
) to authenticated;

commit;
