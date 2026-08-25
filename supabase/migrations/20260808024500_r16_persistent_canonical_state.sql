begin;

-- R16: persistent canonical state.
--
-- R15 made the normalized PostgreSQL rows authoritative, but the visible
-- recycle-bin archive is intentionally removed by permanent purge.  A deleted
-- ID therefore still needed a durable, non-UI tombstone so an old browser or
-- sync snapshot could never recreate it after purge.  R16 separates that
-- canonical deletion registry from the recycle-bin UI and also makes cashbox
-- journal reconciliation identity-first: a journal line is never rewritten by
-- amount alone.

create table if not exists public.erp_canonical_deletion_tombstones(
  company_id uuid not null,
  source_table text not null,
  record_id text not null,
  deleted_at timestamptz not null default now(),
  deleted_by text,
  deletion_mode text not null default 'soft',
  source_archive_id uuid,
  purged_at timestamptz,
  restored_at timestamptz,
  restored_by text,
  last_event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  primary key(company_id,source_table,record_id)
);
create index if not exists erp_canonical_deletion_tombstones_active_idx
  on public.erp_canonical_deletion_tombstones(company_id,source_table,record_id)
  where restored_at is null;
alter table public.erp_canonical_deletion_tombstones enable row level security;
revoke all on public.erp_canonical_deletion_tombstones from public,anon,authenticated;

create or replace function public.erp_r16_sync_tombstone(
  p_company_id uuid,p_source_table text,p_record_id text,
  p_deleted_at timestamptz,p_deleted_by text,p_deletion_mode text,
  p_source_archive_id uuid,p_purged_at timestamptz,
  p_restored_at timestamptz,p_restored_by text,p_metadata jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path=public as $$
begin
  if p_company_id is null or coalesce(btrim(p_source_table),'')='' or coalesce(btrim(p_record_id),'')='' then
    return;
  end if;
  insert into public.erp_canonical_deletion_tombstones(
    company_id,source_table,record_id,deleted_at,deleted_by,deletion_mode,
    source_archive_id,purged_at,restored_at,restored_by,last_event_at,metadata
  ) values(
    p_company_id,btrim(p_source_table),btrim(p_record_id),coalesce(p_deleted_at,now()),
    nullif(btrim(coalesce(p_deleted_by,'')),''),coalesce(nullif(btrim(p_deletion_mode),''),'soft'),
    p_source_archive_id,p_purged_at,p_restored_at,nullif(btrim(coalesce(p_restored_by,'')),''),
    now(),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict(company_id,source_table,record_id) do update set
    deleted_at=excluded.deleted_at,
    deleted_by=coalesce(excluded.deleted_by,erp_canonical_deletion_tombstones.deleted_by),
    deletion_mode=excluded.deletion_mode,
    source_archive_id=coalesce(excluded.source_archive_id,erp_canonical_deletion_tombstones.source_archive_id),
    purged_at=coalesce(excluded.purged_at,erp_canonical_deletion_tombstones.purged_at),
    restored_at=excluded.restored_at,
    restored_by=excluded.restored_by,
    last_event_at=now(),
    metadata=erp_canonical_deletion_tombstones.metadata||excluded.metadata;
end;
$$;

create or replace function public.erp_r16_recycle_tombstone_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_company uuid;
  v_source text;
  v_record text;
  v_deleted timestamptz;
  v_deleted_by text;
  v_mode text;
  v_archive uuid;
  v_purged timestamptz;
  v_restored timestamptz;
  v_restored_by text;
begin
  if tg_op='DELETE' then
    v_company:=old.company_id;
    v_source:=old.source_table;
    v_record:=old.record_id;
    v_deleted:=old.deleted_at;
    v_deleted_by:=old.deleted_by;
    v_mode:=old.deletion_mode;
    v_archive:=old.id;
    -- Deleting an unrestored archive is permanent purge.  Preserve that fact
    -- even though the recycle-bin row itself is intentionally removed.
    v_purged:=case when old.restored_at is null then coalesce(old.purged_at,now()) else old.purged_at end;
    v_restored:=old.restored_at;
    v_restored_by:=old.restored_by;
  else
    v_company:=new.company_id;
    v_source:=new.source_table;
    v_record:=new.record_id;
    v_deleted:=new.deleted_at;
    v_deleted_by:=new.deleted_by;
    v_mode:=new.deletion_mode;
    v_archive:=new.id;
    v_purged:=new.purged_at;
    v_restored:=new.restored_at;
    v_restored_by:=new.restored_by;
  end if;
  perform public.erp_r16_sync_tombstone(
    v_company,v_source,v_record,v_deleted,v_deleted_by,v_mode,v_archive,
    v_purged,v_restored,v_restored_by,
    jsonb_build_object('source','universal_recycle_bin','event',tg_op)
  );
  if tg_op='DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists erp_r16_recycle_tombstone_insert_update on public.erp_universal_recycle_bin;
create trigger erp_r16_recycle_tombstone_insert_update
after insert or update of restored_at,purged_at,deleted_at on public.erp_universal_recycle_bin
for each row execute function public.erp_r16_recycle_tombstone_trigger();
drop trigger if exists erp_r16_recycle_tombstone_delete on public.erp_universal_recycle_bin;
create trigger erp_r16_recycle_tombstone_delete
before delete on public.erp_universal_recycle_bin
for each row execute function public.erp_r16_recycle_tombstone_trigger();

-- Seed all currently visible recycle-bin deletions.
select public.erp_r16_sync_tombstone(
  u.company_id,u.source_table,u.record_id,u.deleted_at,u.deleted_by::text,u.deletion_mode,
  u.id,u.purged_at,u.restored_at,u.restored_by::text,
  jsonb_build_object('source','r16_seed_recycle_bin')
)
from public.erp_universal_recycle_bin u
where u.company_id is not null;

-- Recover already-purged master deletions when the immutable audit trail still
-- remembers them.  We only use the latest audited state for an ID, so a later
-- legitimate recreation/restore is never turned back into a tombstone.
do $$
declare r record;
begin
  if to_regclass('public.erp_audit_log') is not null then
    for r in
      with latest as (
        select distinct on (a.company_id,a.table_name,a.record_id)
          a.company_id,a.table_name,a.record_id,a.operation,a.occurred_at,a.actor_uid,
          a.old_data,a.new_data
        from public.erp_audit_log a
        where a.record_id is not null
          and a.table_name in (
            'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
            'erp_inventory','erp_inventory_groups','erp_product_images'
          )
        order by a.company_id,a.table_name,a.record_id,a.occurred_at desc,a.id desc
      )
      select * from latest
      where operation='DELETE'
         or (operation='UPDATE' and public.erp_try_boolean(new_data->>'is_deleted',false))
    loop
      perform public.erp_r16_sync_tombstone(
        r.company_id,r.table_name,r.record_id,r.occurred_at,r.actor_uid,
        case when r.operation='DELETE' then 'hard' else 'soft' end,
        null,case when r.operation='DELETE' then r.occurred_at else null end,
        null,null,jsonb_build_object('source','r16_seed_audit','operation',r.operation)
      );
    end loop;
  end if;
end $$;

-- R15/R14/R9 compatibility paths now consult the permanent canonical registry,
-- not the disposable recycle-bin row.
create or replace function public.erp_r15_pending_delete_exists(
  p_company_id uuid,p_table text,p_record_id text
) returns boolean
language sql stable security definer set search_path=public as $$
  select (auth.uid() is null or public.is_active_company_member(p_company_id)) and exists(
    select 1 from public.erp_canonical_deletion_tombstones t
    where t.company_id=p_company_id
      and t.source_table=p_table
      and t.record_id=p_record_id
      and t.restored_at is null
  )
$$;

-- Re-apply persistent tombstones to any master row already resurrected by a
-- stale client before R16 reached production.
do $$
declare v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'update public.%I r set is_deleted=true,deleted_at=coalesce(r.deleted_at,t.deleted_at),'
        ||'updated_at=now(),version=coalesce(r.version,0)+1 '
        ||'from public.erp_canonical_deletion_tombstones t '
        ||'where t.company_id=r.company_id and t.source_table=%L and t.record_id=r.id '
        ||'and t.restored_at is null and not coalesce(r.is_deleted,false)',v_table,v_table
      );
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Identity-first cashbox / General Ledger reconciliation.
-- ---------------------------------------------------------------------------
create table if not exists public.erp_canonical_reconciliation_issues(
  company_id uuid not null,
  issue_type text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'::jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  resolved_at timestamptz,
  primary key(company_id,issue_type,entity_type,entity_id)
);
create index if not exists erp_canonical_reconciliation_issues_open_idx
  on public.erp_canonical_reconciliation_issues(company_id,entity_type,entity_id)
  where resolved_at is null;
alter table public.erp_canonical_reconciliation_issues enable row level security;
revoke all on public.erp_canonical_reconciliation_issues from public,anon,authenticated;

create or replace function public.erp_r16_record_reconciliation_issue(
  p_company_id uuid,p_issue_type text,p_entity_type text,p_entity_id text,p_details jsonb
) returns void
language sql security definer set search_path=public as $$
  insert into public.erp_canonical_reconciliation_issues(
    company_id,issue_type,entity_type,entity_id,details,first_seen_at,last_seen_at,resolved_at
  ) values($1,$2,$3,$4,coalesce($5,'{}'::jsonb),now(),now(),null)
  on conflict(company_id,issue_type,entity_type,entity_id) do update set
    details=excluded.details,last_seen_at=now(),resolved_at=null
$$;

create or replace function public.erp_r16_resolve_reconciliation_issues(
  p_company_id uuid,p_entity_type text,p_entity_id text
) returns void
language sql security definer set search_path=public as $$
  update public.erp_canonical_reconciliation_issues
  set resolved_at=now(),last_seen_at=now()
  where company_id=$1 and entity_type=$2 and entity_id=$3 and resolved_at is null
$$;

create or replace function public.erp_r16_cash_line_matches(
  p_data jsonb,p_type text,p_amount numeric
) returns boolean
language sql immutable as $$
  select case
    when lower(coalesce($2,'')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in') then
      abs(public.erp_try_numeric($1->>'debit',0)-abs($3))<=0.01
      and abs(public.erp_try_numeric($1->>'credit',0))<=0.01
    when lower(coalesce($2,'')) in ('payment','expense','out','cash_out','supplier_payment','transfer_out') then
      abs(public.erp_try_numeric($1->>'credit',0)-abs($3))<=0.01
      and abs(public.erp_try_numeric($1->>'debit',0))<=0.01
    else false
  end
$$;

create or replace function public.erp_r15_rebind_cashbox_journals_internal(
  p_company_id uuid,p_cash_account_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_cash public.erp_cash_accounts%rowtype;
  v_ledger record;
  v_tx record;
  v_entry public.erp_journal_entries%rowtype;
  v_line_id text;
  v_amount numeric;
  v_type text;
  v_changed integer:=0;
  v_missing integer:=0;
  v_ambiguous integer:=0;
  v_opening numeric;
  v_count integer;
  v_explicit_total integer;
  v_tx_ref_id text;
  v_tx_ref_type text;
  v_entry_ref_id text;
  v_entry_ref_type text;
  v_reference_match boolean;
  v_match_method text;
begin
  select * into v_cash from public.erp_cash_accounts
  where company_id=p_company_id and id=p_cash_account_id and not is_deleted;
  if not found then return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','missing'); end if;
  select account_id,code,name,currency into v_ledger
  from public.erp_accounts
  where organization_id=p_company_id
    and account_id=coalesce(v_cash.data->>'accountId',v_cash.data->>'account_id')
    and is_active;
  if v_ledger.account_id is null then
    return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','ledger_missing');
  end if;
  if upper(coalesce(v_ledger.currency,''))<>upper(coalesce(v_cash.data->>'currency','')) then
    return jsonb_build_object('cashAccountId',p_cash_account_id,'skipped','ledger_currency_mismatch');
  end if;

  v_opening:=public.erp_try_numeric(coalesce(v_cash.data->>'openingBalance',v_cash.data->>'opening_balance'),0);
  update public.erp_accounts set opening_balance=v_opening,source_updated_at=now(),synced_at=now()
  where organization_id=p_company_id and account_id=v_ledger.account_id
    and opening_balance is distinct from v_opening;

  for v_tx in
    select id,data from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'cashAccountId',data->>'cash_account_id')=p_cash_account_id
      and nullif(coalesce(data->>'journalEntryId',data->>'journal_entry_id'),'') is not null
    order by created_at,id
  loop
    v_amount:=abs(public.erp_try_numeric(v_tx.data->>'amount',0));
    v_type:=lower(coalesce(v_tx.data->>'type',''));
    v_line_id:=null;
    v_match_method:=null;
    v_tx_ref_id:=nullif(coalesce(v_tx.data->>'referenceId',v_tx.data->>'reference_id'),'');
    v_tx_ref_type:=lower(coalesce(v_tx.data->>'referenceType',v_tx.data->>'reference_type',''));

    select * into v_entry from public.erp_journal_entries
    where company_id=p_company_id
      and id=coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id')
      and not is_deleted;
    if not found then
      v_missing:=v_missing+1;
      perform public.erp_r16_record_reconciliation_issue(
        p_company_id,'cash_journal_missing','cash_transaction',v_tx.id,
        jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',coalesce(v_tx.data->>'journalEntryId',v_tx.data->>'journal_entry_id'))
      );
      continue;
    end if;
    v_entry_ref_id:=nullif(coalesce(v_entry.data->>'referenceId',v_entry.data->>'reference_id'),'');
    v_entry_ref_type:=lower(coalesce(v_entry.data->>'referenceType',v_entry.data->>'reference_type',''));
    v_reference_match:=
      (v_tx_ref_id is not null and v_entry_ref_id=v_tx_ref_id
        and (v_tx_ref_type='' or v_entry_ref_type='' or v_entry_ref_type=v_tx_ref_type))
      or (v_entry_ref_id=v_tx.id and v_entry_ref_type in ('cash_transaction','manual_cash_transaction'));

    -- 1) Strongest identity: a journal line already carries this transaction ID.
    select count(*)::integer,min(jl.id),
           count(*) filter(where jl.data->>'cashTransactionId'=v_tx.id)::integer
      into v_count,v_line_id,v_explicit_total
    from public.erp_journal_lines jl
    where jl.company_id=p_company_id and not jl.is_deleted
      and jl.data->>'entryId'=v_entry.id
      and jl.data->>'cashTransactionId'=v_tx.id
      and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=
          upper(coalesce(v_tx.data->>'currency',''))
      and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
    if v_count=1 then
      v_match_method:='line_cash_transaction_id';
    elsif v_count>1 then
      v_ambiguous:=v_ambiguous+1;
      perform public.erp_r16_record_reconciliation_issue(
        p_company_id,'cash_line_identity_ambiguous','cash_transaction',v_tx.id,
        jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'candidateCount',v_count,'method','line_cash_transaction_id')
      );
      continue;
    else
      select count(*)::integer into v_explicit_total
      from public.erp_journal_lines jl
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=v_entry.id and jl.data->>'cashTransactionId'=v_tx.id;
      if v_explicit_total>0 then
        v_missing:=v_missing+1;
        perform public.erp_r16_record_reconciliation_issue(
          p_company_id,'cash_line_identity_amount_mismatch','cash_transaction',v_tx.id,
          jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'explicitLineCount',v_explicit_total)
        );
        continue;
      end if;
    end if;

    -- 2) Journal header explicitly identifies the cash transaction.
    if v_line_id is null and v_entry.data->>'cashTransactionId'=v_tx.id then
      select count(*)::integer,min(jl.id) into v_count,v_line_id
      from public.erp_journal_lines jl
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=v_entry.id
        and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=
            upper(coalesce(v_tx.data->>'currency',''))
        and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
      if v_count=1 then v_match_method:='journal_cash_transaction_id';
      elsif v_count>1 then
        v_ambiguous:=v_ambiguous+1; v_line_id:=null;
        perform public.erp_r16_record_reconciliation_issue(
          p_company_id,'cash_header_identity_ambiguous','cash_transaction',v_tx.id,
          jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'candidateCount',v_count)
        );
        continue;
      end if;
    end if;

    -- 3) Source reference + debit/credit direction.  This safely handles old
    -- cash transfers where two transactions share one reference but have
    -- opposite directions.
    if v_line_id is null and v_reference_match then
      select count(*)::integer,min(jl.id) into v_count,v_line_id
      from public.erp_journal_lines jl
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=v_entry.id
        and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=
            upper(coalesce(v_tx.data->>'currency',''))
        and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
      if v_count=1 then v_match_method:='source_reference';
      elsif v_count>1 then
        v_ambiguous:=v_ambiguous+1; v_line_id:=null;
        perform public.erp_r16_record_reconciliation_issue(
          p_company_id,'cash_reference_identity_ambiguous','cash_transaction',v_tx.id,
          jsonb_build_object('cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,'candidateCount',v_count,'referenceId',v_entry_ref_id)
        );
        continue;
      end if;
    end if;

    -- 4) Last automatic fallback: the current canonical cash ledger account is
    -- already on exactly one amount/direction-compatible line.  There is no
    -- amount-only fallback; otherwise R16 records an issue and changes nothing.
    if v_line_id is null then
      select count(*)::integer,min(jl.id) into v_count,v_line_id
      from public.erp_journal_lines jl
      where jl.company_id=p_company_id and not jl.is_deleted
        and jl.data->>'entryId'=v_entry.id
        and jl.data->>'accountId'=v_ledger.account_id
        and upper(coalesce(nullif(jl.data->>'currency',''),v_entry.data->>'currency',''))=
            upper(coalesce(v_tx.data->>'currency',''))
        and public.erp_r16_cash_line_matches(jl.data,v_type,v_amount);
      if v_count=1 then v_match_method:='canonical_ledger_account';
      elsif v_count>1 then
        v_ambiguous:=v_ambiguous+1; v_line_id:=null;
      end if;
    end if;

    if v_line_id is null then
      v_missing:=v_missing+1;
      perform public.erp_r16_record_reconciliation_issue(
        p_company_id,'cash_identity_unresolved','cash_transaction',v_tx.id,
        jsonb_build_object(
          'cashAccountId',p_cash_account_id,'journalEntryId',v_entry.id,
          'amount',v_amount,'type',v_type,'transactionReferenceId',v_tx_ref_id,
          'journalReferenceId',v_entry_ref_id,'referenceMatched',v_reference_match
        )
      );
      continue;
    end if;

    update public.erp_journal_lines
    set data=data||jsonb_build_object(
          'accountId',v_ledger.account_id,'accountCode',v_ledger.code,
          'accountName',v_ledger.name,'currency',upper(v_ledger.currency),
          'cashTransactionId',v_tx.id,'cashAccountId',p_cash_account_id,
          'r16CanonicalCashBinding',true,'r16CashMatchMethod',v_match_method),
        updated_at=now()
    where company_id=p_company_id and id=v_line_id
      and (data->>'accountId' is distinct from v_ledger.account_id
           or data->>'cashTransactionId' is distinct from v_tx.id
           or data->>'cashAccountId' is distinct from p_cash_account_id
           or not public.erp_try_boolean(data->>'r16CanonicalCashBinding',false));
    if found then v_changed:=v_changed+1; end if;

    update public.erp_cash_transactions
    set data=data||jsonb_build_object(
          'cashLedgerAccountId',v_ledger.account_id,'r16CanonicalCashBinding',true,
          'r16CashMatchMethod',v_match_method),updated_at=now()
    where company_id=p_company_id and id=v_tx.id
      and (data->>'cashLedgerAccountId' is distinct from v_ledger.account_id
           or not public.erp_try_boolean(data->>'r16CanonicalCashBinding',false));
    perform public.erp_r16_resolve_reconciliation_issues(p_company_id,'cash_transaction',v_tx.id);
  end loop;

  return jsonb_build_object(
    'cashAccountId',p_cash_account_id,'ledgerAccountId',v_ledger.account_id,
    'updatedJournalLines',v_changed,'unmatchedTransactions',v_missing,
    'ambiguousTransactions',v_ambiguous,'openingBalance',v_opening
  );
end;
$$;

-- Future cash postings reconcile after the whole posting transaction has built
-- its journal lines.  The deferred trigger removes timing races between cash
-- transaction insertion and journal-line insertion.
create or replace function public.erp_r16_deferred_cash_reconcile()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_cash_id text;
begin
  if new.is_deleted then return new; end if;
  v_cash_id:=coalesce(new.data->>'cashAccountId',new.data->>'cash_account_id');
  if nullif(v_cash_id,'') is not null then
    perform public.erp_r15_rebind_cashbox_journals_internal(new.company_id,v_cash_id);
  end if;
  return new;
end;
$$;
drop trigger if exists erp_r16_deferred_cash_reconcile on public.erp_cash_transactions;
create constraint trigger erp_r16_deferred_cash_reconcile
after insert or update on public.erp_cash_transactions
deferrable initially deferred
for each row execute function public.erp_r16_deferred_cash_reconcile();

-- Re-run the now identity-safe reconciliation once for existing production data.
do $$
declare r record;
begin
  for r in select company_id,id from public.erp_cash_accounts where not is_deleted loop
    perform public.erp_r15_rebind_cashbox_journals_internal(r.company_id,r.id);
  end loop;
end $$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare
  v_base jsonb;
  v_open_issues bigint:=0;
  v_tombstone_conflicts bigint:=0;
  v_tombstones bigint:=0;
  v_issue_details jsonb:='[]'::jsonb;
  v_table text;
  v_count bigint;
begin
  if auth.uid() is not null and not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_base:=public.erp_r15_current_state_health(p_company_id);
  select count(*) into v_open_issues
  from public.erp_canonical_reconciliation_issues
  where company_id=p_company_id and resolved_at is null;
  select count(*) into v_tombstones
  from public.erp_canonical_deletion_tombstones
  where company_id=p_company_id and restored_at is null;
  select coalesce(jsonb_agg(jsonb_build_object(
      'issueType',q.issue_type,'entityType',q.entity_type,'entityId',q.entity_id,
      'details',q.details,'firstSeenAt',q.first_seen_at,'lastSeenAt',q.last_seen_at
    ) order by q.last_seen_at desc),'[]'::jsonb) into v_issue_details
  from (
    select issue_type,entity_type,entity_id,details,first_seen_at,last_seen_at
    from public.erp_canonical_reconciliation_issues
    where company_id=p_company_id and resolved_at is null
    order by last_seen_at desc limit 25
  ) q;
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones t '
        ||'on t.company_id=r.company_id and t.source_table=%L and t.record_id=r.id '
        ||'where r.company_id=$1 and t.restored_at is null and not coalesce(r.is_deleted,false)',
        v_table,v_table
      ) into v_count using p_company_id;
      v_tombstone_conflicts:=v_tombstone_conflicts+coalesce(v_count,0);
    end if;
  end loop;
  return v_base||jsonb_build_object(
    'ok',coalesce((v_base->>'ok')::boolean,false) and v_open_issues=0 and v_tombstone_conflicts=0,
    'persistentDeletionConflictCount',v_tombstone_conflicts,
    'permanentDeletionTombstoneCount',v_tombstones,
    'unresolvedCanonicalReconciliationIssueCount',v_open_issues,
    'openCanonicalIssues',v_issue_details,
    'canonicalStateVersion',16,
    'checkedAt',timezone('utc',now())
  );
end;
$$;

create or replace function public.erp_r16_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if not public.is_company_admin(p_company_id) then
    raise exception 'company_admin_required' using errcode='42501';
  end if;
  v_result:=public.erp_r15_reconcile_company_state(p_company_id);
  return v_result||jsonb_build_object('canonicalStateVersion',16,'health',public.erp_r16_current_state_health(p_company_id));
end;
$$;

create or replace function public.erp_r16_runtime_contract_probe(p_company_id uuid)
returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'ok',auth.uid() is not null and public.is_active_company_member(p_company_id),
    'r15MasterList',to_regprocedure('public.erp_r15_list_cloud_master_records(uuid,text)') is not null,
    'r15MasterGet',to_regprocedure('public.erp_r15_get_cloud_master_record(uuid,text,text)') is not null,
    'r15MasterUpsert',to_regprocedure('public.erp_r15_upsert_cloud_master_record(uuid,text,text,jsonb,bigint)') is not null,
    'r15MasterDelete',to_regprocedure('public.erp_r15_soft_delete_cloud_master_record(uuid,text,text,bigint)') is not null,
    'r14Phase26',to_regprocedure('public.erp_r14_phase26_cloud_command(text,text,jsonb)') is not null,
    'r14SalesApprove',to_regprocedure('public.erp_r14_approve_sales_invoice(uuid,uuid)') is not null,
    'r14PurchaseApprove',to_regprocedure('public.erp_r14_approve_purchase_invoice(uuid,uuid)') is not null,
    'persistentDeletionRegistry',to_regclass('public.erp_canonical_deletion_tombstones') is not null,
    'identitySafeCashReconciliation',to_regprocedure('public.erp_r16_cash_line_matches(jsonb,text,numeric)') is not null,
    'masterContractsOk',jsonb_array_length(public.erp_r14_master_contract_issues())=0,
    'masterContractIssues',public.erp_r14_master_contract_issues(),
    'currentStateHealth',public.erp_r16_current_state_health(p_company_id),
    'canonicalStateVersion',16,
    'checkedAt',timezone('utc',now())
  )
$$;

revoke all on function public.erp_r16_sync_tombstone(uuid,text,text,timestamptz,text,text,uuid,timestamptz,timestamptz,text,jsonb) from public,anon,authenticated;
revoke all on function public.erp_r16_record_reconciliation_issue(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.erp_r16_resolve_reconciliation_issues(uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_r16_deferred_cash_reconcile() from public,anon,authenticated;
revoke all on function public.erp_r16_current_state_health(uuid) from public,anon;
revoke all on function public.erp_r16_reconcile_company_state(uuid) from public,anon;
revoke all on function public.erp_r16_runtime_contract_probe(uuid) from public,anon;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_runtime_contract_probe(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_sync_tombstone(uuid,text,text,timestamptz,text,text,uuid,timestamptz,timestamptz,text,jsonb) to service_role;
grant execute on function public.erp_r16_record_reconciliation_issue(uuid,text,text,text,jsonb) to service_role;
grant execute on function public.erp_r16_resolve_reconciliation_issues(uuid,text,text) to service_role;

notify pgrst,'reload schema';
commit;
