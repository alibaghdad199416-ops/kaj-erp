-- R68: governed bulk inbox/recycle operations and canonical financial-family
-- deletion. All destructive entry points remain company- and permission-bound.
begin;

create or replace function public.erp_r68_empty_recycle_bin(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_archive record;
  v_result jsonb;
  v_batches integer:=0;
  v_archive_rows integer:=0;
  v_source_rows integer:=0;
  v_tombstones integer:=0;
  v_skipped jsonb:='[]'::jsonb;
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied' using errcode='42501';
  end if;
  if not public.erp_cloud_user_has_permission(
    p_company_id,'settings.recycle_bin.purge'
  ) then
    raise exception 'permanent_delete_permission_required' using errcode='42501';
  end if;

  -- One representative per company-owned deletion batch. Each subtransaction
  -- rolls back independently, so a protected batch cannot corrupt the rest.
  for v_archive in
    select distinct on (coalesce(u.deletion_batch_id,u.id))
      u.id,u.deletion_batch_id,u.source_table,u.record_id
    from public.erp_universal_recycle_bin u
    where u.company_id=p_company_id
      and u.restored_at is null and u.purged_at is null
    order by coalesce(u.deletion_batch_id,u.id),u.deleted_at,u.id
  loop
    begin
      v_result:=public.erp_recycle_bin_purge_by_archive(
        p_company_id,v_archive.id
      );
      v_batches:=v_batches+1;
      v_archive_rows:=v_archive_rows+coalesce(
        (v_result->>'archiveRowsRemoved')::integer,0
      );
      v_source_rows:=v_source_rows+coalesce(
        (v_result->>'sourceRowsDeleted')::integer,0
      );
      v_tombstones:=v_tombstones+coalesce(
        (v_result->>'integrityTombstonesRetained')::integer,0
      );
    exception when others then
      v_skipped:=v_skipped||jsonb_build_array(jsonb_build_object(
        'archiveId',v_archive.id,'deletionBatchId',v_archive.deletion_batch_id,
        'sourceTable',v_archive.source_table,'recordId',v_archive.record_id,
        'sqlstate',sqlstate,'reason',sqlerrm
      ));
    end;
  end loop;

  perform public.erp_record_audit_event(
    p_company_id,'EMPTY_RECYCLE_BIN','erp_universal_recycle_bin',null,
    jsonb_build_object(
      'processedBatches',v_batches,'archiveRowsRemoved',v_archive_rows,
      'sourceRowsDeleted',v_source_rows,
      'integrityTombstonesRetained',v_tombstones,
      'skippedCount',jsonb_array_length(v_skipped)
    ),'application'
  );
  return jsonb_build_object(
    'ok',true,'processedBatches',v_batches,
    'archiveRowsRemoved',v_archive_rows,'sourceRowsDeleted',v_source_rows,
    'integrityTombstonesRetained',v_tombstones,
    'skippedCount',jsonb_array_length(v_skipped),'skipped',v_skipped
  );
end;
$$;

create or replace function public.erp_r68_clear_cloud_notifications(
  p_company_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_key text:=public.erp_r49_notification_user_key();
  v_cleared integer:=0;
  v_unread integer:=0;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then
    raise exception 'notification_user_identity_required' using errcode='42501';
  end if;

  with visible as (
    select n.id,not coalesce(s.is_read,false) as was_unread
    from public.erp_enterprise_notifications n
    left join public.erp_notification_user_states s
      on s.company_id=n.company_id and s.notification_id=n.id
     and s.user_key=v_key
    where n.company_id=p_company_id and not n.is_deleted
      and public.erp_r49_notification_visible(p_company_id,n.data)
      and not coalesce(s.deleted,false)
  ), upserted as (
    insert into public.erp_notification_user_states(
      company_id,notification_id,user_key,is_read,deleted,deleted_at,updated_at
    )
    select p_company_id,v.id,v_key,not v.was_unread,true,now(),now()
    from visible v
    on conflict(company_id,notification_id,user_key) do update
      set deleted=true,
          deleted_at=coalesce(erp_notification_user_states.deleted_at,excluded.deleted_at),
          updated_at=now()
    returning notification_id
  )
  select count(*)::integer,
         coalesce((select count(*)::integer from visible where was_unread),0)
    into v_cleared,v_unread
  from upserted;

  perform public.erp_record_audit_event(
    p_company_id,'CLEAR_NOTIFICATIONS','erp_notification_user_states',v_key,
    jsonb_build_object('clearedCount',v_cleared,'unreadCleared',v_unread),
    'application'
  );
  return jsonb_build_object(
    'ok',true,'clearedCount',v_cleared,'unreadCleared',v_unread,
    'remainingUnread',0
  );
end;
$$;

-- Stamp the durable family identity from the authoritative payment envelope
-- onto every cash, transfer and journal artifact. This closes the historical
-- gap where transferId existed only inside invoice JSON.
create or replace function public.erp_r68_stamp_payment_envelope(
  p_company_id uuid,p_payment jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cash text:=nullif(coalesce(
    p_payment->>'cashTransactionId',p_payment->>'cash_transaction_id'
  ),'');
  v_journal text:=nullif(coalesce(
    p_payment->>'journalEntryId',p_payment->>'journal_entry_id'
  ),'');
  v_payment text:=nullif(coalesce(
    p_payment->>'paymentId',p_payment->>'payment_id'
  ),'');
  v_key text:=nullif(coalesce(
    p_payment->>'paymentKey',p_payment->>'payment_key'
  ),'');
  v_transfer text:=nullif(coalesce(
    p_payment->>'transferId',p_payment->>'transfer_id'
  ),'');
  v_family text;
begin
  v_family:=coalesce(v_key,v_payment,v_cash);
  if v_family is null then return; end if;

  update public.erp_cash_transactions ct
  set data=ct.data||jsonb_build_object(
        'transactionFamilyId',v_family,'paymentKey',coalesce(v_key,v_family),
        'paymentId',v_payment,'paymentTransferId',v_transfer
      ),updated_at=now()
  where ct.company_id=p_company_id and not ct.is_deleted
    and (ct.id=v_cash or (v_transfer is not null and
      coalesce(ct.data->>'referenceId',ct.data->>'reference_id')=v_transfer));

  update public.erp_cash_transfers t
  set data=t.data||jsonb_build_object(
        'transactionFamilyId',v_family,'paymentKey',coalesce(v_key,v_family),
        'paymentId',v_payment
      ),updated_at=now()
  where t.company_id=p_company_id and not t.is_deleted and t.id=v_transfer;

  update public.erp_journal_entries je
  set data=je.data||jsonb_build_object(
        'transactionFamilyId',v_family,'paymentKey',coalesce(v_key,v_family),
        'paymentId',v_payment,'paymentTransferId',v_transfer
      ),updated_at=now()
  where je.company_id=p_company_id and not je.is_deleted
    and (je.id=v_journal or (v_transfer is not null and
      coalesce(je.data->>'referenceId',je.data->>'reference_id')=v_transfer));

  update public.erp_journal_lines jl
  set data=jl.data||jsonb_build_object(
        'transactionFamilyId',v_family,'paymentKey',coalesce(v_key,v_family),
        'paymentId',v_payment,'paymentTransferId',v_transfer
      ),updated_at=now()
  where jl.company_id=p_company_id and not jl.is_deleted
    and (
      coalesce(jl.data->>'entryId',jl.data->>'entry_id')=v_journal
      or (v_transfer is not null and
          coalesce(jl.data->>'referenceId',jl.data->>'reference_id')=v_transfer)
    );
end;
$$;

create or replace function public.erp_r68_stamp_document_payment_families()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_payment jsonb;
begin
  if new.document_type='invoice' then
    for v_payment in
      select value from jsonb_array_elements(
        coalesce(new.payload->'payments','[]'::jsonb)
        ||coalesce(new.payload->'detachedPayments','[]'::jsonb)
      )
    loop
      perform public.erp_r68_stamp_payment_envelope(new.company_id,v_payment);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists erp_r68_stamp_document_payment_families
  on public.erp_commercial_workflow_documents;
create trigger erp_r68_stamp_document_payment_families
after insert or update of payload on public.erp_commercial_workflow_documents
for each row execute function public.erp_r68_stamp_document_payment_families();

-- Backfill every retained active or detached payment envelope without changing
-- its business document.
do $$
declare v_doc record; v_payment jsonb;
begin
  for v_doc in
    select company_id,payload from public.erp_commercial_workflow_documents
    where document_type='invoice'
  loop
    for v_payment in
      select value from jsonb_array_elements(
        coalesce(v_doc.payload->'payments','[]'::jsonb)
        ||coalesce(v_doc.payload->'detachedPayments','[]'::jsonb)
      )
    loop
      perform public.erp_r68_stamp_payment_envelope(v_doc.company_id,v_payment);
    end loop;
  end loop;
end;
$$;

create or replace function public.erp_r68_delete_financial_transaction_family(
  p_company_id uuid,p_transaction_id text default null,
  p_entry_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_seed public.erp_cash_transactions%rowtype;
  v_family text;
  v_payment text;
  v_key text;
  v_transfer text;
  v_journals text[]:='{}'::text[];
  v_cash_count integer:=0;
  v_transfer_count integer:=0;
  v_journal_count integer:=0;
  v_line_count integer:=0;
  v_maintenance_count integer:=0;
  v_allocation_count integer:=0;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  if coalesce(nullif(btrim(p_transaction_id),''),nullif(btrim(p_entry_id),'')) is null then
    raise exception 'financial_transaction_identity_required' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_company_id::text||':financial-family:'||
    coalesce(p_transaction_id,p_entry_id),0
  ));

  if p_transaction_id is not null then
    select * into v_seed from public.erp_cash_transactions
    where company_id=p_company_id and id=p_transaction_id for update;
  else
    select * into v_seed from public.erp_cash_transactions
    where company_id=p_company_id
      and coalesce(data->>'journalEntryId',data->>'journal_entry_id',
                   data->>'entryId',data->>'entry_id')=p_entry_id
    order by is_deleted,created_at limit 1 for update;
  end if;
  if not found then
    return jsonb_build_object('ok',true,'alreadyDeleted',true,
      'transactionId',p_transaction_id,'entryId',p_entry_id);
  end if;
  if v_seed.is_deleted then
    return jsonb_build_object('ok',true,'alreadyDeleted',true,
      'transactionId',v_seed.id);
  end if;
  if lower(coalesce(v_seed.data->>'referenceType',''))='cash_transfer' then
    raise exception 'cash_transfer_requires_transfer_delete' using errcode='P0001';
  end if;

  v_family:=nullif(coalesce(
    v_seed.data->>'transactionFamilyId',v_seed.data->>'transaction_family_id',
    v_seed.data->>'paymentKey',v_seed.data->>'payment_key'
  ),'');
  v_payment:=nullif(coalesce(
    v_seed.data->>'paymentId',
    case when lower(coalesce(v_seed.data->>'referenceType',''))<>'partner_advance'
      then v_seed.data->>'referenceId' end
  ),'');
  v_key:=nullif(coalesce(v_seed.data->>'paymentKey',v_family),'');
  v_transfer:=nullif(v_seed.data->>'paymentTransferId','');

  -- Legacy V7.5.7 rows can recover their canonical IDs from the retained
  -- payment/detachedPayment envelope.
  select coalesce(v_family,p.value->>'paymentKey',p.value->>'paymentId',v_seed.id),
         coalesce(v_payment,p.value->>'paymentId'),
         coalesce(v_key,p.value->>'paymentKey'),
         coalesce(v_transfer,p.value->>'transferId')
    into v_family,v_payment,v_key,v_transfer
  from public.erp_commercial_workflow_documents d
  cross join lateral jsonb_array_elements(
    coalesce(d.payload->'payments','[]'::jsonb)
    ||coalesce(d.payload->'detachedPayments','[]'::jsonb)
  ) p(value)
  where d.company_id=p_company_id and (
    p.value->>'cashTransactionId'=v_seed.id
    or coalesce(p.value->>'journalEntryId','')=coalesce(
      v_seed.data->>'journalEntryId',v_seed.data->>'journal_entry_id','')
    or (v_key is not null and p.value->>'paymentKey'=v_key)
  ) limit 1;
  v_family:=coalesce(v_family,v_key,v_payment,v_seed.id);

  -- Active commercial invoice ownership is authoritative and cannot be
  -- detached as a side effect of a Finance delete.
  if exists(
    select 1 from public.erp_commercial_workflow_documents d
    cross join lateral jsonb_array_elements(
      coalesce(d.payload->'payments','[]'::jsonb)
    ) p(value)
    where d.company_id=p_company_id and not d.is_deleted
      and d.document_type='invoice' and lower(coalesce(d.status,''))<>'cancelled'
      and (
        p.value->>'cashTransactionId'=v_seed.id
        or (v_key is not null and p.value->>'paymentKey'=v_key)
        or (v_payment is not null and p.value->>'paymentId'=v_payment)
        or coalesce(p.value->>'journalEntryId','')=coalesce(
          v_seed.data->>'journalEntryId',v_seed.data->>'journal_entry_id','')
      )
  ) then
    raise exception 'payment_linked_to_active_invoice'
      using errcode='P0001',detail='family='||v_family;
  end if;

  if exists(
    select 1 from public.erp_partner_advance_allocations a
    where a.company_id=p_company_id and not a.is_deleted and (
      a.cash_transaction_id=v_seed.id
      or exists(select 1 from public.erp_cash_transactions c
        where c.company_id=p_company_id and c.id=a.cash_transaction_id
          and not c.is_deleted
          and coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
    )
  ) then
    raise exception 'payment_has_active_allocations'
      using errcode='P0001',detail='family='||v_family;
  end if;

  if exists(
    select 1 from public.erp_maintenance_payments mp
    join public.erp_maintenance_orders mo
      on mo.company_id=mp.company_id and mo.id=mp.maintenance_order_id
    where mp.company_id=p_company_id and not mp.is_deleted
      and not coalesce(mp.is_unapplied,false)
      and not mo.is_deleted
      and lower(coalesce(mo.workflow_stage,'')) not in ('cancelled','order_cancelled')
      and (mp.cash_transaction_id=v_seed.id
        or mp.source_cash_transaction_id=v_seed.id
        or (v_key is not null and mp.payment_key=v_key))
  ) then
    raise exception 'payment_linked_to_active_maintenance_invoice'
      using errcode='P0001',detail='family='||v_family;
  end if;

  select coalesce(array_agg(distinct x),array[]::text[]) into v_journals
  from (
    select coalesce(c.data->>'journalEntryId',c.data->>'journal_entry_id') x
    from public.erp_cash_transactions c
    where c.company_id=p_company_id and not c.is_deleted and (
      c.id=v_seed.id
      or coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family
      or (v_transfer is not null and
          coalesce(c.data->>'referenceId',c.data->>'reference_id')=v_transfer)
    )
    union
    select je.id from public.erp_journal_entries je
    where je.company_id=p_company_id and not je.is_deleted and (
      coalesce(je.data->>'transactionFamilyId',je.data->>'paymentKey')=v_family
      or (v_transfer is not null and
          coalesce(je.data->>'referenceId',je.data->>'reference_id')=v_transfer)
    )
  ) q where x is not null;

  update public.erp_partner_advance_allocations a
  set is_deleted=true,deleted_at=v_now,deleted_by=auth.uid(),
      deletion_reason='Financial transaction family deleted'
  where a.company_id=p_company_id and not a.is_deleted
    and a.cash_transaction_id in (
      select c.id from public.erp_cash_transactions c
      where c.company_id=p_company_id and (
        c.id=v_seed.id or
        coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family)
    );
  get diagnostics v_allocation_count=row_count;

  update public.erp_maintenance_payments mp
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
  where mp.company_id=p_company_id and not mp.is_deleted and (
    mp.cash_transaction_id=v_seed.id or mp.source_cash_transaction_id=v_seed.id
    or (v_key is not null and mp.payment_key=v_key)
    or mp.journal_entry_id=any(v_journals)
  );
  get diagnostics v_maintenance_count=row_count;

  update public.erp_journal_lines jl
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=jl.data||jsonb_build_object(
        'deleteReason','Financial transaction family deleted',
        'transactionFamilyId',v_family,'deletedAt',v_now
      )
  where jl.company_id=p_company_id and not jl.is_deleted
    and coalesce(jl.data->>'entryId',jl.data->>'entry_id')=any(v_journals);
  get diagnostics v_line_count=row_count;

  update public.erp_journal_entries je
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=je.data||jsonb_build_object(
        'deleteReason','Financial transaction family deleted',
        'transactionFamilyId',v_family,'deletedAt',v_now
      )
  where je.company_id=p_company_id and not je.is_deleted
    and je.id=any(v_journals);
  get diagnostics v_journal_count=row_count;

  update public.erp_cash_transactions c
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=c.data||jsonb_build_object(
        'deleteReason','Financial transaction family deleted',
        'transactionFamilyId',v_family,'deletedAt',v_now
      )
  where c.company_id=p_company_id and not c.is_deleted and (
    c.id=v_seed.id
    or coalesce(c.data->>'transactionFamilyId',c.data->>'paymentKey')=v_family
    or (v_transfer is not null and
        coalesce(c.data->>'referenceId',c.data->>'reference_id')=v_transfer)
  );
  get diagnostics v_cash_count=row_count;

  update public.erp_cash_transfers t
  set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
      data=t.data||jsonb_build_object(
        'deleteReason','Financial transaction family deleted',
        'transactionFamilyId',v_family,'deletedAt',v_now
      )
  where t.company_id=p_company_id and not t.is_deleted and (
    coalesce(t.data->>'transactionFamilyId',t.data->>'paymentKey')=v_family
    or (v_transfer is not null and t.id=v_transfer)
  );
  get diagnostics v_transfer_count=row_count;

  perform public.erp_record_audit_event(
    p_company_id,'DELETE_FINANCIAL_TRANSACTION_FAMILY',
    'erp_cash_transactions',v_seed.id,jsonb_build_object(
      'transactionFamilyId',v_family,'paymentId',v_payment,
      'paymentKey',v_key,'transferId',v_transfer,
      'cashRowsDeleted',v_cash_count,'transferRowsDeleted',v_transfer_count,
      'journalEntriesDeleted',v_journal_count,'journalLinesDeleted',v_line_count,
      'maintenancePaymentsDeleted',v_maintenance_count,
      'allocationsDeleted',v_allocation_count
    ),'application'
  );
  return jsonb_build_object(
    'ok',true,'alreadyDeleted',false,'transactionFamilyId',v_family,
    'paymentId',v_payment,'paymentKey',v_key,'transferId',v_transfer,
    'cashRowsDeleted',v_cash_count,'transferRowsDeleted',v_transfer_count,
    'journalEntriesDeleted',v_journal_count,'journalLinesDeleted',v_line_count,
    'maintenancePaymentsDeleted',v_maintenance_count,
    'allocationsDeleted',v_allocation_count
  );
end;
$$;

-- Existing Cashbox and Journal callers converge here. Direct transfers retain
-- their established transfer-family deletion semantics.
create or replace function public.erp_delete_cloud_cash_transaction(
  p_company_id uuid,p_transaction_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare v_type text; v_reference text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );
  select lower(coalesce(data->>'referenceType',data->>'reference_type','')),
         coalesce(data->>'referenceId',data->>'reference_id')
    into v_type,v_reference
  from public.erp_cash_transactions
  where company_id=p_company_id and id=p_transaction_id and not is_deleted;
  if not found then return; end if;
  if v_type='cash_transfer' and v_reference is not null then
    perform public.erp_delete_cloud_cash_transfer(p_company_id,v_reference);
    return;
  end if;
  perform public.erp_r68_delete_financial_transaction_family(
    p_company_id,p_transaction_id,null
  );
end;
$$;

revoke all on function public.erp_r68_empty_recycle_bin(uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r68_clear_cloud_notifications(uuid)
  from public,anon,authenticated;
revoke all on function public.erp_r68_stamp_payment_envelope(uuid,jsonb)
  from public,anon,authenticated;
revoke all on function public.erp_r68_delete_financial_transaction_family(uuid,text,text)
  from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from public,anon,authenticated;
grant execute on function public.erp_r68_empty_recycle_bin(uuid)
  to authenticated,service_role;
grant execute on function public.erp_r68_clear_cloud_notifications(uuid)
  to authenticated,service_role;
grant execute on function public.erp_r68_stamp_payment_envelope(uuid,jsonb)
  to service_role;
grant execute on function public.erp_r68_delete_financial_transaction_family(uuid,text,text)
  to authenticated,service_role;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
