begin;

-- R42: canonical cashbox ledger identity must be enforced at the table boundary,
-- not only through one save RPC. Every non-deleted cashbox carries the same
-- ledger id in every supported alias and an active ledger can belong to only
-- one active cashbox per company.
create or replace function public.erp_r23_cashbox_ledger_account_id(p_data jsonb)
returns text
language sql immutable
set search_path=public
as $$
  select nullif(btrim(coalesce(
    $1->>'canonical',
    $1->>'account_id',
    $1->>'accountId',
    $1->>'ledgerAccountId',
    ''
  )), '')
$$;

-- Repair the known EBL rows from their own chart-of-account definitions. This
-- intentionally resolves by company + normalized account name + currency +
-- asset type, rather than hard-coding generated account UUIDs.
do $$
declare
  r record;
  v_target text;
begin
  for r in
    select ca.company_id, ca.id, ca.data,
           upper(coalesce(nullif(btrim(ca.data->>'currency'),''),
                          nullif(btrim(ca.data->>'currencyCode'),''))) as currency,
           lower(regexp_replace(btrim(coalesce(ca.data->>'name','')), '\s+', ' ', 'g')) as normalized_name
      from public.erp_cash_accounts ca
     where not ca.is_deleted
       and lower(regexp_replace(btrim(coalesce(ca.data->>'name','')), '\s+', ' ', 'g'))
           in ('ebl usd','ebl iqd')
  loop
    select a.account_id
      into v_target
      from public.erp_accounts a
     where a.organization_id=r.company_id
       and a.is_active
       and lower(a.account_type)='asset'
       and upper(a.currency)=r.currency
       and lower(regexp_replace(btrim(a.name), '\s+', ' ', 'g'))=r.normalized_name
     order by a.code, a.account_id
     limit 1;

    if v_target is null then
      raise exception 'r42_ebl_ledger_not_found:%:%', r.id, r.currency using errcode='23503';
    end if;

    update public.erp_cash_accounts ca
       set data=ca.data || jsonb_build_object(
         'accountId',v_target,
         'account_id',v_target,
         'canonical',v_target,
         'ledgerAccountId',v_target,
         'schemaVersion',42,
         'schema_version',42
       ),
       updated_at=clock_timestamp()
     where ca.company_id=r.company_id and ca.id=r.id and not ca.is_deleted;
  end loop;
end $$;

-- Normalize every existing ledger alias before creating the uniqueness guard.
update public.erp_cash_accounts ca
   set data=ca.data || jsonb_build_object(
     'accountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
     'account_id',public.erp_r23_cashbox_ledger_account_id(ca.data),
     'canonical',public.erp_r23_cashbox_ledger_account_id(ca.data),
     'ledgerAccountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
     'schemaVersion',42,
     'schema_version',42
   ),
   updated_at=clock_timestamp()
 where not ca.is_deleted
   and public.erp_r23_cashbox_ledger_account_id(ca.data) is not null;

create or replace function public.erp_r42_cashbox_before_write_guard()
returns trigger
language plpgsql
set search_path=public
as $$
declare
  v_new_canonical text:=nullif(btrim(new.data->>'canonical'),'');
  v_new_snake text:=nullif(btrim(new.data->>'account_id'),'');
  v_new_camel text:=nullif(btrim(new.data->>'accountId'),'');
  v_new_ledger_alias text:=nullif(btrim(new.data->>'ledgerAccountId'),'');
  v_old_canonical text;
  v_old_snake text;
  v_old_camel text;
  v_old_ledger_alias text;
  v_ledger text;
  v_changed_values text[]:=array[]::text[];
  v_distinct_changed integer:=0;
  v_distinct_insert integer:=0;
  v_currency text;
  v_ledger_currency text;
  v_ledger_type text;
  v_active boolean;
begin
  if jsonb_typeof(new.data) is distinct from 'object' then
    new.data:='{}'::jsonb;
  end if;

  v_active:=public.erp_try_boolean(
    coalesce(new.data->>'is_active',new.data->>'isActive'),'true'
  );

  if tg_op='UPDATE' then
    v_old_canonical:=nullif(btrim(old.data->>'canonical'),'');
    v_old_snake:=nullif(btrim(old.data->>'account_id'),'');
    v_old_camel:=nullif(btrim(old.data->>'accountId'),'');
    v_old_ledger_alias:=nullif(btrim(old.data->>'ledgerAccountId'),'');

    if v_new_canonical is distinct from v_old_canonical and v_new_canonical is not null then
      v_changed_values:=array_append(v_changed_values,v_new_canonical);
    end if;
    if v_new_snake is distinct from v_old_snake and v_new_snake is not null then
      v_changed_values:=array_append(v_changed_values,v_new_snake);
    end if;
    if v_new_camel is distinct from v_old_camel and v_new_camel is not null then
      v_changed_values:=array_append(v_changed_values,v_new_camel);
    end if;
    if v_new_ledger_alias is distinct from v_old_ledger_alias and v_new_ledger_alias is not null then
      v_changed_values:=array_append(v_changed_values,v_new_ledger_alias);
    end if;

    select count(distinct x) into v_distinct_changed
      from unnest(v_changed_values) x;
    if v_distinct_changed>1 then
      raise exception 'cashbox_ledger_alias_conflict' using errcode='23514';
    end if;
    if v_distinct_changed=1 then
      select x into v_ledger from unnest(v_changed_values) x limit 1;
    else
      v_ledger:=coalesce(v_new_canonical,v_new_snake,v_new_camel,v_new_ledger_alias,
                         v_old_canonical,v_old_snake,v_old_camel,v_old_ledger_alias);
    end if;
  else
    select count(distinct x) into v_distinct_insert
      from unnest(array[v_new_canonical,v_new_snake,v_new_camel,v_new_ledger_alias]) x
     where x is not null;
    if v_distinct_insert>1 then
      raise exception 'cashbox_ledger_alias_conflict' using errcode='23514';
    end if;
    v_ledger:=coalesce(v_new_canonical,v_new_snake,v_new_camel,v_new_ledger_alias);
  end if;

  if new.is_deleted then
    return new;
  end if;

  if v_ledger is null then
    raise exception 'cashbox_ledger_account_required' using errcode='23502';
  end if;

  v_currency:=upper(coalesce(
    nullif(btrim(new.data->>'currency'),''),
    nullif(btrim(new.data->>'currencyCode'),'')
  ));
  if v_currency is null then
    raise exception 'cashbox_currency_required' using errcode='23502';
  end if;

  select upper(a.currency),lower(a.account_type)
    into v_ledger_currency,v_ledger_type
    from public.erp_accounts a
   where a.organization_id=new.company_id
     and a.account_id=v_ledger
     and a.is_active;

  if v_ledger_currency is null then
    raise exception 'cashbox_ledger_account_not_found:%',v_ledger using errcode='23503';
  end if;
  if v_ledger_type<>'asset' then
    raise exception 'cashbox_ledger_account_must_be_asset:%',v_ledger using errcode='23514';
  end if;
  if v_ledger_currency<>v_currency then
    raise exception 'cashbox_ledger_currency_mismatch:%:%',v_currency,v_ledger_currency using errcode='23514';
  end if;

  if v_active and exists(
    select 1
      from public.erp_cash_accounts x
     where x.company_id=new.company_id
       and x.id<>new.id
       and not x.is_deleted
       and public.erp_try_boolean(coalesce(x.data->>'is_active',x.data->>'isActive'),'true')
       and public.erp_r23_cashbox_ledger_account_id(x.data)=v_ledger
  ) then
    raise exception 'cashbox_ledger_account_already_bound:%',v_ledger using errcode='23505';
  end if;

  new.data:=new.data || jsonb_build_object(
    'accountId',v_ledger,
    'account_id',v_ledger,
    'canonical',v_ledger,
    'ledgerAccountId',v_ledger,
    'currency',v_currency,
    'schemaVersion',42,
    'schema_version',42
  );
  return new;
end $$;

drop trigger if exists trg_r42_cashbox_before_write_guard on public.erp_cash_accounts;
create trigger trg_r42_cashbox_before_write_guard
before insert or update on public.erp_cash_accounts
for each row execute function public.erp_r42_cashbox_before_write_guard();

-- The trigger gives readable validation errors for every write path; the
-- unique index is the final concurrency-safe guarantee against two concurrent
-- writers binding one ledger to two active cashboxes.
drop index if exists public.erp_cash_account_ledger_company_uq;
create unique index erp_cash_account_ledger_company_uq
  on public.erp_cash_accounts(
    company_id,
    (nullif(btrim(coalesce(data->>'canonical',data->>'account_id',data->>'accountId',data->>'ledgerAccountId','')),''))
  )
  where not is_deleted
    and lower(coalesce(data->>'is_active',data->>'isActive','true')) not in ('false','0','no','off')
    and nullif(btrim(coalesce(data->>'canonical',data->>'account_id',data->>'accountId',data->>'ledgerAccountId','')),'') is not null;

create or replace function public.erp_r42_list_cash_accounts(p_company_id uuid)
returns setof jsonb
language sql stable security definer set search_path=public
as $$
  select ca.data || jsonb_build_object(
      'id',ca.id,
      'accountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'account_id',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'canonical',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'ledgerAccountId',public.erp_r23_cashbox_ledger_account_id(ca.data),
      'createdAt',ca.created_at,'created_at',ca.created_at,
      'updatedAt',ca.updated_at,'updated_at',ca.updated_at,
      '_cloudCreatedAt',ca.created_at,'_cloudUpdatedAt',ca.updated_at,
      '_cloudVersion',ca.version,
      'ledgerAccountCode',a.code,'ledgerAccountName',a.name,
      'ledgerAccountCurrency',a.currency,'ledgerAccountType',a.account_type,
      'schemaVersion',42,'schema_version',42)
    from public.erp_cash_accounts ca
    left join public.erp_accounts a
      on a.organization_id=ca.company_id
     and a.account_id=public.erp_r23_cashbox_ledger_account_id(ca.data)
   where ca.company_id=p_company_id
     and not ca.is_deleted
     and public.erp_is_company_member(p_company_id)
   order by public.erp_try_boolean(coalesce(ca.data->>'isActive',ca.data->>'is_active'),'true') desc,
            lower(coalesce(ca.data->>'name','')),ca.id
$$;

create or replace function public.erp_r42_save_cash_account(p_company_id uuid,p_account jsonb)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_in jsonb:=coalesce(p_account,'{}'::jsonb);
  v_ledger text:=nullif(btrim(coalesce(
    v_in->>'canonical',v_in->>'account_id',v_in->>'accountId',v_in->>'ledgerAccountId',''
  )), '');
  v_result jsonb;
begin
  if v_ledger is null then raise exception 'cashbox_ledger_account_required'; end if;
  v_in:=v_in || jsonb_build_object(
    'accountId',v_ledger,'account_id',v_ledger,'canonical',v_ledger,'ledgerAccountId',v_ledger,
    'schemaVersion',42,'schema_version',42
  );
  v_result:=public.erp_r28_save_cash_account(p_company_id,v_in);
  return v_result || jsonb_build_object(
    'accountId',v_ledger,'account_id',v_ledger,'canonical',v_ledger,'ledgerAccountId',v_ledger,
    'schemaVersion',42,'schema_version',42
  );
end $$;

create or replace function public.erp_r42_cashbox_guard_health(p_company_id uuid)
returns jsonb
language sql stable security definer set search_path=public
as $$
with cash as (
  select ca.id,ca.data,public.erp_r23_cashbox_ledger_account_id(ca.data) ledger_id,
         upper(coalesce(ca.data->>'currency',ca.data->>'currencyCode','')) currency,
         public.erp_try_boolean(coalesce(ca.data->>'is_active',ca.data->>'isActive'),'true') active
    from public.erp_cash_accounts ca
   where ca.company_id=p_company_id and not ca.is_deleted
), problems as (
  select c.id,
    case
      when c.ledger_id is null then 'missing_ledger'
      when a.account_id is null then 'ledger_not_found'
      when lower(a.account_type)<>'asset' then 'ledger_not_asset'
      when upper(a.currency)<>c.currency then 'currency_mismatch'
      when coalesce(c.data->>'accountId','')<>c.ledger_id
        or coalesce(c.data->>'account_id','')<>c.ledger_id
        or coalesce(c.data->>'canonical','')<>c.ledger_id
        or coalesce(c.data->>'ledgerAccountId','')<>c.ledger_id then 'alias_drift'
      else null
    end issue
  from cash c
  left join public.erp_accounts a
    on a.organization_id=p_company_id and a.account_id=c.ledger_id and a.is_active
), dups as (
  select ledger_id,count(*) n
    from cash where active and ledger_id is not null
   group by ledger_id having count(*)>1
)
select jsonb_build_object(
  'healthy',not exists(select 1 from problems where issue is not null)
            and not exists(select 1 from dups),
  'problemCount',(select count(*) from problems where issue is not null),
  'duplicateActiveLedgerBindings',(select count(*) from dups),
  'problems',coalesce((select jsonb_agg(jsonb_build_object('cashAccountId',id,'issue',issue))
                        from problems where issue is not null),'[]'::jsonb),
  'duplicates',coalesce((select jsonb_agg(jsonb_build_object('ledgerAccountId',ledger_id,'count',n))
                          from dups),'[]'::jsonb)
)
$$;

revoke all on function public.erp_r42_list_cash_accounts(uuid) from public,anon;
revoke all on function public.erp_r42_save_cash_account(uuid,jsonb) from public,anon;
revoke all on function public.erp_r42_cashbox_guard_health(uuid) from public,anon;
grant execute on function public.erp_r42_list_cash_accounts(uuid) to authenticated,service_role;
grant execute on function public.erp_r42_save_cash_account(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r42_cashbox_guard_health(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
