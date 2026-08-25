-- Phase 2: authoritative per-item inventory accounting.
-- Purchase: inventory asset Dr / supplier Cr.
-- Sale delivery: configured cost expense Dr / inventory asset Cr.
-- Scrap/consumption: warehouse expense Dr / inventory asset Cr.

create or replace function public.erp_phase2_account_guard(
  p_company_id uuid,p_account_id text,p_expected_type text,p_currency text default null
) returns text language plpgsql security definer set search_path=public as $$
declare a public.erp_accounts%rowtype;
begin
  if nullif(btrim(p_account_id),'') is null then raise exception 'الحساب المحاسبي مطلوب'; end if;
  select * into a from public.erp_accounts where organization_id=p_company_id and account_id=p_account_id and is_active limit 1;
  if not found then raise exception 'الحساب المحاسبي غير موجود أو غير فعال'; end if;
  if lower(coalesce(a.account_type,''))<>lower(p_expected_type) then
    raise exception 'نوع الحساب غير صحيح؛ النوع المطلوب %',p_expected_type;
  end if;
  if p_currency is not null and upper(coalesce(a.currency,'MULTI')) not in ('MULTI',upper(p_currency)) then
    raise exception 'عملة الحساب لا تطابق عملة العملية';
  end if;
  return a.account_id;
end $$;

create or replace function public.erp_phase2_item_accounts(
 p_company_id uuid,p_item_type text,p_item_id text,p_currency text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare d jsonb; asset_id text; expense_id text;
begin
 if lower(p_item_type)='car' then
   select data into d from public.erp_cars where company_id=p_company_id and id=p_item_id and not is_deleted;
 else
   select data into d from public.erp_inventory where company_id=p_company_id and id=p_item_id and not is_deleted;
 end if;
 if d is null then raise exception 'العنصر المخزني غير موجود'; end if;
 if lower(coalesce(d->>'itemType',d->>'item_type','stock'))='service' then raise exception 'الخدمة لا تقبل قيد مخزون'; end if;
 asset_id:=nullif(coalesce(d->>'inventoryAssetAccountId',d->>'inventory_asset_account_id'),'');
 expense_id:=nullif(coalesce(d->>'costOfSalesAccountId',d->>'costOfSaleAccountId',d->>'cost_of_sales_account_id',d->>'cost_of_sale_account_id'),'');
 perform public.erp_phase2_account_guard(p_company_id,asset_id,'asset',p_currency);
 perform public.erp_phase2_account_guard(p_company_id,expense_id,'expense',p_currency);
 return jsonb_build_object('assetAccountId',asset_id,'costExpenseAccountId',expense_id);
end $$;

create or replace function public.erp_phase2_void_reference_journals(
 p_company_id uuid,p_reference_type text,p_reference_id text
) returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
 for r in select id from public.erp_journal_entries where company_id=p_company_id and not is_deleted
   and data->>'referenceType'=p_reference_type and data->>'referenceId'=p_reference_id
 loop
   update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'entryId'=r.id;
   update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=r.id;
 end loop;
end $$;

create or replace function public.erp_phase2_insert_journal(
 p_company_id uuid,p_reference_type text,p_reference_id text,p_number text,p_description text,
 p_currency text,p_lines jsonb
) returns text language plpgsql security definer set search_path=public as $$
declare eid text:=gen_random_uuid()::text; l jsonb; td numeric:=0; tc numeric:=0;
begin
 if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then raise exception 'القيد يحتاج سطرين على الأقل'; end if;
 select coalesce(sum(public.erp_try_numeric(x->>'debit',0)),0),coalesce(sum(public.erp_try_numeric(x->>'credit',0)),0)
 into td,tc from jsonb_array_elements(p_lines)x;
 if td<=0 or abs(td-tc)>0.01 then raise exception 'القيد غير متوازن'; end if;
 perform public.erp_phase2_void_reference_journals(p_company_id,p_reference_type,p_reference_id);
 insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values
 (p_company_id,eid,jsonb_build_object('id',eid,'entryNumber',p_number,'entryDate',now(),'description',p_description,
 'currency',upper(p_currency),'referenceType',p_reference_type,'referenceId',p_reference_id,'status','posted',
 'totalDebit',td,'totalCredit',tc,'createdAt',now()),auth.uid(),auth.uid());
 for l in select value from jsonb_array_elements(p_lines) loop
   insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
   (p_company_id,gen_random_uuid()::text,l||jsonb_build_object('entryId',eid),auth.uid(),auth.uid());
 end loop;
 return eid;
end $$;

create or replace function public.erp_phase2_post_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare doc public.erp_commercial_workflow_documents%rowtype; ord public.erp_purchase_orders_cloud%rowtype;
 a record; ac jsonb; supplier_account text; lines jsonb:='[]'; total numeric:=0; amount numeric; eid text;
begin
 select * into doc from public.erp_commercial_workflow_documents where company_id=p_company_id and id=p_receipt_id and module='purchases' and document_type='receipt' and not is_deleted;
 if not found or doc.status<>'approved' then raise exception 'يجب تصديق أمر الاستلام أولاً'; end if;
 select * into ord from public.erp_purchase_orders_cloud where company_id=p_company_id and id=doc.parent_id and not is_deleted;
 select coalesce(pa.usd_account_id,pa.iqd_account_id) into supplier_account from public.erp_partner_accounts pa
 where pa.organization_id=p_company_id and pa.partner_type='supplier' and pa.partner_id=ord.supplier_id and pa.is_active limit 1;
 perform public.erp_phase2_account_guard(p_company_id,supplier_account,'liability',ord.currency);
 for a in select x.item_type,x.item_id,x.description,x.quantity,x.unit_cost from public.erp_purchase_order_items_cloud x
   where x.company_id=p_company_id and x.order_id=ord.id and not x.is_deleted
 loop
   ac:=public.erp_phase2_item_accounts(p_company_id,a.item_type,a.item_id,ord.currency);
   amount:=a.quantity*a.unit_cost; total:=total+amount;
   lines:=lines||jsonb_build_array(jsonb_build_object('accountId',ac->>'assetAccountId','debit',amount,'credit',0,
    'description','إثبات شراء '||a.description,'itemType',a.item_type,'itemId',a.item_id));
 end loop;
 lines:=lines||jsonb_build_array(jsonb_build_object('accountId',supplier_account,'debit',0,'credit',total,'description','ذمة المورد'));
 eid:=public.erp_phase2_insert_journal(p_company_id,'purchase_inventory',p_receipt_id::text,
  'PINV-'||replace(p_receipt_id::text,'-',''),'قيد استلام مشتريات '||doc.document_number,ord.currency,lines);
 update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object('inventoryJournalEntryId',eid,'accountingPostedAt',now()),updated_at=now() where id=p_receipt_id;
 return eid;
end $$;

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
   else select coalesce(public.erp_try_numeric(data->>'averageUnitCost',data->>'purchasePrice'),0) into cost from public.erp_inventory where company_id=p_company_id and id=a.item_id; end if;
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

create or replace function public.erp_phase2_approve_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
 perform public.erp_approve_cloud_purchase_receipt(p_company_id,p_receipt_id);
 perform public.erp_phase2_post_purchase_receipt(p_company_id,p_receipt_id);
end $$;
create or replace function public.erp_phase2_approve_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language plpgsql security definer set search_path=public as $$ begin
 perform public.erp_approve_cloud_sales_delivery(p_company_id,p_delivery_id);
 perform public.erp_phase2_post_sales_delivery(p_company_id,p_delivery_id);
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
   else select public.erp_try_numeric(data->>'averageUnitCost',data->>'purchasePrice') into cost from public.erp_inventory where company_id=p_company_id and id=i->>'itemId'; end if;
   amount:=qty*coalesce(cost,0);
   lines:=lines||jsonb_build_array(
    jsonb_build_object('accountId',expense,'debit',amount,'credit',0,'description','تالف/استهلاك '||coalesce(i->>'description',i->>'itemId')),
    jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',amount,'description','إخراج أصل مخزني'));
 end loop;
 eid:=public.erp_phase2_insert_journal(p_company_id,'inventory_scrap',p_reference_id,'SCRAP-'||replace(p_reference_id,'-',''),'قيد تلف واستهلاك '||coalesce(p_notes,''),p_currency,lines);
 return eid;
end $$;

grant execute on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_approve_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_post_purchase_receipt(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_post_sales_delivery(uuid,uuid) to authenticated;
grant execute on function public.erp_phase2_post_scrap(uuid,text,text,text,jsonb,text) to authenticated;
