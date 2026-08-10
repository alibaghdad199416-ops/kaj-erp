begin;

-- 17.61.0: compatibility-safe completion of accounting/assets/warehouse/opportunity repairs.

-- A) Re-create the accepted fixed-asset tables when an earlier cleanup removed
-- the legacy asset module, then upgrade existing installations in place.
create table if not exists public.erp_fixed_assets (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  asset_number text not null,
  category_id uuid,
  name_ar text not null,
  acquisition_date date not null default current_date,
  acquisition_cost numeric(20,2) not null default 0,
  residual_value numeric(20,2) not null default 0,
  useful_life_months integer not null default 60,
  current_book_value numeric(20,2) not null default 0,
  status text not null default 'active',
  is_deleted boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id,asset_number)
);

create table if not exists public.erp_asset_depreciation_entries (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null,
  asset_id uuid not null references public.erp_fixed_assets(id) on delete restrict,
  period_date date not null,
  opening_book_value numeric(20,2) not null,
  depreciation_amount numeric(20,2) not null,
  closing_book_value numeric(20,2) not null,
  created_at timestamptz not null default now(),
  unique(company_id,asset_id,period_date)
);

alter table public.erp_fixed_assets add column if not exists asset_code text;
alter table public.erp_fixed_assets add column if not exists name text;
alter table public.erp_fixed_assets add column if not exists salvage_value numeric(20,2);
alter table public.erp_fixed_assets add column if not exists depreciation_method text;
alter table public.erp_fixed_assets add column if not exists declining_rate numeric(12,6);
alter table public.erp_fixed_assets add column if not exists currency text;
alter table public.erp_fixed_assets add column if not exists asset_account_id text;
alter table public.erp_fixed_assets add column if not exists accumulated_depreciation_account_id text;
alter table public.erp_fixed_assets add column if not exists depreciation_expense_account_id text;
alter table public.erp_fixed_assets add column if not exists accumulated_depreciation numeric(20,2);
alter table public.erp_fixed_assets add column if not exists last_depreciation_date date;
alter table public.erp_fixed_assets add column if not exists is_active boolean;
alter table public.erp_fixed_assets add column if not exists notes text;

update public.erp_fixed_assets
set asset_code=coalesce(nullif(asset_code,''),asset_number,id::text),
    name=coalesce(nullif(name,''),name_ar,asset_number,id::text),
    salvage_value=coalesce(salvage_value,residual_value,0),
    depreciation_method=coalesce(nullif(depreciation_method,''),'straight_line'),
    currency=coalesce(nullif(upper(currency),''),'USD'),
    accumulated_depreciation=coalesce(accumulated_depreciation,greatest(coalesce(acquisition_cost,0)-coalesce(current_book_value,acquisition_cost,0),0)),
    is_active=coalesce(is_active,status='active',true)
where asset_code is null or name is null or salvage_value is null or depreciation_method is null
   or currency is null or accumulated_depreciation is null or is_active is null;

alter table public.erp_fixed_assets alter column category_id drop not null;
alter table public.erp_fixed_assets alter column asset_code set not null;
alter table public.erp_fixed_assets alter column name set not null;
alter table public.erp_fixed_assets alter column salvage_value set default 0;
alter table public.erp_fixed_assets alter column salvage_value set not null;
alter table public.erp_fixed_assets alter column depreciation_method set default 'straight_line';
alter table public.erp_fixed_assets alter column depreciation_method set not null;
alter table public.erp_fixed_assets alter column currency set default 'USD';
alter table public.erp_fixed_assets alter column currency set not null;
alter table public.erp_fixed_assets alter column accumulated_depreciation set default 0;
alter table public.erp_fixed_assets alter column accumulated_depreciation set not null;
alter table public.erp_fixed_assets alter column is_active set default true;
alter table public.erp_fixed_assets alter column is_active set not null;

create unique index if not exists erp_fixed_assets_company_asset_code_uq
on public.erp_fixed_assets(company_id,asset_code) where not is_deleted;

alter table public.erp_asset_depreciation_entries add column if not exists journal_entry_id text;
alter table public.erp_asset_depreciation_entries add column if not exists depreciation_method text;

create or replace function public.erp_save_fixed_asset(p_company_id uuid,p_asset jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=coalesce(nullif(p_asset->>'id','')::uuid,gen_random_uuid());
  v_code text:=btrim(coalesce(p_asset->>'assetCode',''));
  v_name text:=btrim(coalesce(p_asset->>'name',''));
  v_cost numeric:=coalesce((p_asset->>'acquisitionCost')::numeric,0);
  v_salvage numeric:=coalesce((p_asset->>'salvageValue')::numeric,0);
  v_life int:=coalesce((p_asset->>'usefulLifeMonths')::int,0);
  v_method text:=coalesce(nullif(p_asset->>'depreciationMethod',''),'straight_line');
  v_currency text:=upper(coalesce(nullif(p_asset->>'currency',''),'USD'));
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'لا توجد صلاحية على الشركة'; end if;
  if v_code='' or v_name='' then raise exception 'رمز الأصل واسمه مطلوبان'; end if;
  if v_cost<0 or v_salvage<0 or v_salvage>v_cost then raise exception 'قيم كلفة الأصل والخردة غير صحيحة'; end if;
  if v_life<=0 then raise exception 'العمر الإنتاجي يجب أن يكون أكبر من صفر'; end if;
  if v_method not in ('straight_line','declining_balance') then raise exception 'طريقة الإهلاك غير مدعومة'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'عملة الأصل غير مدعومة'; end if;
  if nullif(btrim(coalesce(p_asset->>'assetAccountId','')),'') is null
     or nullif(btrim(coalesce(p_asset->>'accumulatedDepreciationAccountId','')),'') is null
     or nullif(btrim(coalesce(p_asset->>'depreciationExpenseAccountId','')),'') is null then
    raise exception 'يجب تحديد حساب الأصل ومجمع الإهلاك ومصروف الإهلاك';
  end if;

  insert into public.erp_fixed_assets(
    id,company_id,asset_number,name_ar,asset_code,name,acquisition_date,
    acquisition_cost,residual_value,salvage_value,useful_life_months,
    current_book_value,status,depreciation_method,declining_rate,currency,
    asset_account_id,accumulated_depreciation_account_id,depreciation_expense_account_id,
    accumulated_depreciation,is_active,notes,updated_at,is_deleted,deleted_at)
  values(
    v_id,p_company_id,v_code,v_name,v_code,v_name,(p_asset->>'acquisitionDate')::date,
    v_cost,v_salvage,v_salvage,v_life,v_cost,'active',v_method,
    nullif(p_asset->>'decliningRate','')::numeric,v_currency,
    p_asset->>'assetAccountId',p_asset->>'accumulatedDepreciationAccountId',p_asset->>'depreciationExpenseAccountId',
    0,coalesce((p_asset->>'isActive')::boolean,true),nullif(p_asset->>'notes',''),now(),false,null)
  on conflict(id) do update set
    asset_number=excluded.asset_number,name_ar=excluded.name_ar,asset_code=excluded.asset_code,name=excluded.name,
    acquisition_date=excluded.acquisition_date,acquisition_cost=excluded.acquisition_cost,
    residual_value=excluded.residual_value,salvage_value=excluded.salvage_value,
    useful_life_months=excluded.useful_life_months,
    current_book_value=greatest(excluded.acquisition_cost-public.erp_fixed_assets.accumulated_depreciation,excluded.salvage_value),
    status=case when excluded.is_active then 'active' else 'inactive' end,
    depreciation_method=excluded.depreciation_method,declining_rate=excluded.declining_rate,currency=excluded.currency,
    asset_account_id=excluded.asset_account_id,
    accumulated_depreciation_account_id=excluded.accumulated_depreciation_account_id,
    depreciation_expense_account_id=excluded.depreciation_expense_account_id,
    is_active=excluded.is_active,notes=excluded.notes,updated_at=now(),is_deleted=false,deleted_at=null;
  return v_id;
end $$;

create or replace function public.erp_post_fixed_asset_depreciation(p_company_id uuid,p_asset_id uuid,p_posting_date date default current_date)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  a public.erp_fixed_assets%rowtype; v_amount numeric; v_book numeric;
  v_entry jsonb; v_lines jsonb; v_entry_id text:=gen_random_uuid()::text; v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'لا توجد صلاحية على الشركة'; end if;
  select * into a from public.erp_fixed_assets where company_id=p_company_id and id=p_asset_id and not is_deleted for update;
  if not found or not coalesce(a.is_active,true) then raise exception 'الأصل غير موجود أو غير فعال'; end if;
  if a.last_depreciation_date is not null and date_trunc('month',a.last_depreciation_date)=date_trunc('month',p_posting_date) then
    raise exception 'تم توليد إهلاك هذا الأصل للشهر المحدد مسبقاً';
  end if;
  if a.asset_account_id is null or a.accumulated_depreciation_account_id is null or a.depreciation_expense_account_id is null then
    raise exception 'حسابات الأصل المحاسبية غير مكتملة';
  end if;
  v_book:=greatest(a.acquisition_cost-coalesce(a.accumulated_depreciation,0),a.salvage_value);
  if v_book<=a.salvage_value then raise exception 'الأصل مهلك بالكامل'; end if;
  if a.depreciation_method='straight_line' then
    v_amount:=(a.acquisition_cost-a.salvage_value)/a.useful_life_months;
  else
    v_amount:=v_book*coalesce(a.declining_rate,2.0/a.useful_life_months);
  end if;
  v_amount:=round(least(v_amount,v_book-a.salvage_value),2);
  if v_amount<=0 then raise exception 'قيمة الإهلاك غير صحيحة'; end if;
  v_number:='DEP-'||a.asset_code||'-'||to_char(p_posting_date,'YYYYMM');
  v_entry:=jsonb_build_object('id',v_entry_id,'entryNumber',v_number,'entryDate',p_posting_date,
    'description','إهلاك الأصل: '||a.name,'referenceType','fixed_asset_depreciation','referenceId',a.id::text,
    'currency',a.currency,'createdAt',now());
  v_lines:=jsonb_build_array(
    jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',a.depreciation_expense_account_id,'debit',v_amount,'credit',0,'description','مصروف إهلاك '||a.name,'currency',a.currency),
    jsonb_build_object('id',gen_random_uuid()::text,'entryId',v_entry_id,'accountId',a.accumulated_depreciation_account_id,'debit',0,'credit',v_amount,'description','مجمع إهلاك '||a.name,'currency',a.currency));
  perform public.erp_post_cloud_manual_journal(p_company_id,v_entry,v_lines);
  insert into public.erp_asset_depreciation_entries(company_id,asset_id,period_date,opening_book_value,depreciation_amount,closing_book_value,journal_entry_id,depreciation_method)
  values(p_company_id,a.id,date_trunc('month',p_posting_date)::date,v_book,v_amount,v_book-v_amount,v_entry_id,a.depreciation_method);
  update public.erp_fixed_assets set accumulated_depreciation=coalesce(accumulated_depreciation,0)+v_amount,
    current_book_value=v_book-v_amount,last_depreciation_date=p_posting_date,updated_at=now() where id=a.id;
  return v_entry_id::uuid;
end $$;

-- B) Purchase-order opportunity status also reacts to physical DELETE, not only soft-delete updates.
create or replace function public.erp_sync_opportunity_from_deleted_purchase_order()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if nullif(btrim(coalesce(old.opportunity_id,'')),'') is not null then
    update public.erp_records
       set payload=payload||jsonb_build_object('status','lost','purchaseOrderId',old.id::text,
         'purchaseOrderNumber',coalesce(old.order_number,''),'closedAt',now(),'updatedAt',now()),
           updated_at=now()
     where company_id=old.company_id and entity_type='opportunities'
       and record_id=old.opportunity_id and deleted_at is null;
  end if;
  return old;
end $$;

drop trigger if exists erp_purchase_order_opportunity_delete_sync on public.erp_purchase_orders_cloud;
create trigger erp_purchase_order_opportunity_delete_sync
after delete on public.erp_purchase_orders_cloud for each row
execute function public.erp_sync_opportunity_from_deleted_purchase_order();

-- C) Automatically account for product transfers into/out of a scrap-consumption warehouse.
create or replace function public.erp_account_scrap_inventory_movement()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_wh public.erp_warehouses%rowtype; v_type text; v_qty numeric; v_cost numeric; v_amount numeric;
  v_currency text; v_inventory_account text; v_expense_account text; v_direction text;
begin
  if new.is_deleted then return new; end if;
  v_type:=lower(coalesce(new.data->>'movementType',''));
  if v_type not in ('transfer_in','transfer_out') then return new; end if;
  select * into v_wh from public.erp_warehouses
   where company_id=new.company_id and id=new.data->>'warehouseId' and not is_deleted;
  if not found or coalesce(v_wh.data->>'warehouseType','normal')<>'scrap_consumption' then return new; end if;
  v_inventory_account:=nullif(coalesce(v_wh.data->>'inventoryAccountId',v_wh.data->>'inventory_account_id'),'');
  v_expense_account:=nullif(coalesce(v_wh.data->>'scrapExpenseAccountId',v_wh.data->>'scrap_expense_account_id'),'');
  if v_inventory_account is null or v_expense_account is null then
    raise exception 'يجب تحديد حساب المخزون وحساب مصروف التوالف لمخزن التوالف والاستهلاك';
  end if;
  v_qty:=abs(public.erp_try_numeric(new.data->>'quantity',0));
  v_cost:=abs(public.erp_try_numeric(new.data->>'unitCost',0));
  v_amount:=round(v_qty*v_cost,2);
  if v_amount<=0 then return new; end if;
  select upper(coalesce(currency,'USD')) into v_currency from public.erp_accounts
   where organization_id=new.company_id and account_id=v_inventory_account and is_active;
  v_currency:=coalesce(v_currency,'USD');
  v_direction:=case when v_type='transfer_in' then 'in' else 'out' end;
  perform public.erp_post_scrap_warehouse_value(new.company_id,new.id,new.data->>'warehouseId',v_direction,
    v_amount,v_currency,v_inventory_account,v_expense_account,
    coalesce(new.data->>'notes','حركة مخزن توالف واستهلاك'));
  return new;
end $$;

drop trigger if exists erp_inventory_scrap_accounting on public.erp_inventory_movements;
create trigger erp_inventory_scrap_accounting
after insert on public.erp_inventory_movements for each row
execute function public.erp_account_scrap_inventory_movement();

create index if not exists erp_fixed_assets_company_status_idx
  on public.erp_fixed_assets(company_id,status) where not is_deleted;
create index if not exists erp_asset_depreciation_company_asset_idx
  on public.erp_asset_depreciation_entries(company_id,asset_id,period_date desc);

alter table public.erp_fixed_assets enable row level security;
alter table public.erp_asset_depreciation_entries enable row level security;

drop policy if exists erp_fixed_assets_company_access on public.erp_fixed_assets;
create policy erp_fixed_assets_company_access on public.erp_fixed_assets
  for all to authenticated
  using (public.erp_is_company_member(company_id))
  with check (public.erp_is_company_member(company_id));

drop policy if exists erp_asset_depreciation_company_access on public.erp_asset_depreciation_entries;
create policy erp_asset_depreciation_company_access on public.erp_asset_depreciation_entries
  for all to authenticated
  using (public.erp_is_company_member(company_id))
  with check (public.erp_is_company_member(company_id));

grant select,insert,update,delete on public.erp_fixed_assets to authenticated;
grant select,insert,update,delete on public.erp_asset_depreciation_entries to authenticated;

grant execute on function public.erp_save_fixed_asset(uuid,jsonb) to authenticated;
grant execute on function public.erp_post_fixed_asset_depreciation(uuid,uuid,date) to authenticated;

commit;
