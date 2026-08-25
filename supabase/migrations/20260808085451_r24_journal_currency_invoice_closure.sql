-- R24 invoice posting closure: every single-currency journal line is written
-- with the journal currency before validation triggers run.
begin;

create or replace function public.erp_phase2_insert_journal_at(
  p_company_id uuid,
  p_reference_type text,
  p_reference_id text,
  p_number text,
  p_description text,
  p_currency text,
  p_lines jsonb,
  p_effective_at timestamptz
) returns text
language plpgsql security definer set search_path=public as $$
declare
  eid text:=gen_random_uuid()::text;
  l jsonb;
  td numeric;
  tc numeric;
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if v_currency not in ('USD','IQD') then raise exception 'journal_currency_invalid'; end if;
  perform public.erp_validate_operational_date(p_company_id,split_part(p_reference_type,'_',1),p_effective_at);
  select coalesce(sum(public.erp_try_numeric(value->>'debit',0)),0),
         coalesce(sum(public.erp_try_numeric(value->>'credit',0)),0)
    into td,tc from jsonb_array_elements(p_lines);
  if td<=0 or abs(td-tc)>0.01 then raise exception 'القيد غير متوازن'; end if;
  perform public.erp_phase2_void_reference_journals(p_company_id,p_reference_type,p_reference_id);
  insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by) values(
    p_company_id,eid,jsonb_build_object('id',eid,'entryNumber',p_number,'entryDate',p_effective_at,
      'effectiveAt',p_effective_at,'description',p_description,'currency',v_currency,
      'referenceType',p_reference_type,'referenceId',p_reference_id,'status','posted',
      'totalDebit',td,'totalCredit',tc,'createdAt',now()),auth.uid(),auth.uid());
  for l in select value from jsonb_array_elements(p_lines) loop
    if nullif(btrim(coalesce(l->>'currency','')),'') is not null
       and upper(btrim(l->>'currency'))<>v_currency then
      raise exception 'journal_line_currency_mismatch';
    end if;
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by)
    values(p_company_id,gen_random_uuid()::text,
      l||jsonb_build_object('entryId',eid,'currency',v_currency),auth.uid(),auth.uid());
  end loop;
  return eid;
end $$;

notify pgrst,'reload schema';
commit;
