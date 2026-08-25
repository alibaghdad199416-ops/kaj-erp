begin;

create or replace function public.erp_cloud_model_report(
  p_company_id uuid,
  p_module text,
  p_start_date date default null,
  p_end_date date default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  m text := lower(btrim(coalesce(p_module, '')));
  d1 date := coalesce(p_start_date, date '1900-01-01');
  d2 date := coalesce(p_end_date, date '2999-12-31');
  result jsonb := '[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  if m = 'products' then
    result := jsonb_build_array(jsonb_build_object(
      'key','products','title','Products / المنتجات',
      'columns',jsonb_build_array(
        'id','code','name','serialNumber','category','groupId','unit',
        'quantity','expectedIncoming','expectedOutgoing','expectedQuantity',
        'minQuantity','purchasePrice','landedCost','unitCost','salePrice',
        'expectedGrossProfitPerUnit','isActive','notes','createdAt','updatedAt',
        'createdBy','updatedBy','rawData'
      ),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(
        i.id,i.data->>'code',i.data->>'name',i.data->>'serialNumber',
        i.data->>'category',i.data->>'groupId',i.data->>'unit',
        i.data->>'quantity',i.data->>'expectedIncoming',i.data->>'expectedOutgoing',
        i.data->>'expectedQuantity',i.data->>'minQuantity',i.data->>'purchasePrice',
        i.data->>'landedCost',i.data->>'unitCost',i.data->>'salePrice',
        i.data->>'expectedGrossProfitPerUnit',i.data->>'isActive',i.data->>'notes',
        i.created_at,i.updated_at,coalesce(cu.email,'system'),
        coalesce(uu.email,cu.email,'system'),i.data::text
      ) order by i.data->>'name'),'[]'::jsonb)
      from public.erp_inventory i
      left join auth.users cu on cu.id=i.created_by
      left join auth.users uu on uu.id=i.updated_by
      where i.company_id=p_company_id and not i.is_deleted
        and i.created_at::date between d1 and d2)
    ));
  elsif m = 'warehouses' then
    result := jsonb_build_array(jsonb_build_object(
      'key','warehouses','title','Warehouses / المخازن',
      'columns',jsonb_build_array(
        'id','code','name','branchId','address','isActive','notes',
        'createdAt','updatedAt','createdBy','updatedBy','rawData'
      ),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(
        w.id,w.data->>'code',w.data->>'name',w.data->>'branchId',
        w.data->>'address',w.data->>'isActive',w.data->>'notes',
        w.created_at,w.updated_at,coalesce(cu.email,'system'),
        coalesce(uu.email,cu.email,'system'),w.data::text
      ) order by w.data->>'name'),'[]'::jsonb)
      from public.erp_warehouses w
      left join auth.users cu on cu.id=w.created_by
      left join auth.users uu on uu.id=w.updated_by
      where w.company_id=p_company_id and not w.is_deleted
        and w.created_at::date between d1 and d2)
    ));
  elsif m in ('customers','suppliers') then
    if m='customers' then
      result := jsonb_build_array(jsonb_build_object(
        'key','customers','title','Customers / العملاء',
        'columns',jsonb_build_array(
          'id','name','phone','email','address','identityNumber','taxNumber',
          'isActive','notes','createdAt','updatedAt','createdBy','updatedBy','rawData'
        ),
        'rows',(select coalesce(jsonb_agg(jsonb_build_array(
          x.id,x.data->>'name',x.data->>'phone',x.data->>'email',x.data->>'address',
          x.data->>'identityNumber',x.data->>'taxNumber',x.data->>'isActive',
          x.data->>'notes',x.created_at,x.updated_at,coalesce(cu.email,'system'),
          coalesce(uu.email,cu.email,'system'),x.data::text
        ) order by x.data->>'name'),'[]'::jsonb)
        from public.erp_customers x
        left join auth.users cu on cu.id=x.created_by
        left join auth.users uu on uu.id=x.updated_by
        where x.company_id=p_company_id and not x.is_deleted
          and x.created_at::date between d1 and d2)
      ));
    else
      result := jsonb_build_array(jsonb_build_object(
        'key','suppliers','title','Suppliers / المجهزون',
        'columns',jsonb_build_array(
          'id','name','phone','email','address','identityNumber','taxNumber',
          'isActive','notes','createdAt','updatedAt','createdBy','updatedBy','rawData'
        ),
        'rows',(select coalesce(jsonb_agg(jsonb_build_array(
          x.id,x.data->>'name',x.data->>'phone',x.data->>'email',x.data->>'address',
          x.data->>'identityNumber',x.data->>'taxNumber',x.data->>'isActive',
          x.data->>'notes',x.created_at,x.updated_at,coalesce(cu.email,'system'),
          coalesce(uu.email,cu.email,'system'),x.data::text
        ) order by x.data->>'name'),'[]'::jsonb)
        from public.erp_suppliers x
        left join auth.users cu on cu.id=x.created_by
        left join auth.users uu on uu.id=x.updated_by
        where x.company_id=p_company_id and not x.is_deleted
          and x.created_at::date between d1 and d2)
      ));
    end if;
  elsif m = 'payments' then
    result := jsonb_build_array(jsonb_build_object(
      'key','payments','title','Invoice payments / دفعات الفواتير',
      'columns',jsonb_build_array(
        'module','invoiceNumber','invoiceId','paymentId','paymentType',
        'cashAccountId','paymentCurrency','cashAmount','invoiceCurrency',
        'invoiceAmount','exchangeRate','exchangeDifference','settlementAccountId',
        'settlementMode','paymentDate','notes','createdBy','updatedBy','rawData'
      ),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(
        d.module,d.document_number,d.id,p.value->>'paymentId',p.value->>'paymentType',
        p.value->>'cashAccountId',p.value->>'paymentCurrency',p.value->>'cashAmount',
        p.value->>'invoiceCurrency',coalesce(p.value->>'invoiceAmount',p.value->>'amount'),
        p.value->>'exchangeRate',p.value->>'exchangeDifference',
        p.value->>'settlementAccountId',p.value->>'settlementMode',
        p.value->>'paymentDate',p.value->>'notes',
        coalesce(p.value->>'createdByUserName',cu.email,'system'),
        coalesce(p.value->>'updatedByUserName',uu.email,cu.email,'system'),p.value::text
      ) order by public.erp_try_timestamptz(p.value->>'paymentDate',d.created_at) desc),'[]'::jsonb)
      from public.erp_commercial_workflow_documents d
      cross join lateral jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p(value)
      left join auth.users cu on cu.id=d.created_by
      left join auth.users uu on uu.id=d.updated_by
      where d.company_id=p_company_id and not d.is_deleted and d.document_type='invoice'
        and coalesce(public.erp_try_timestamptz(p.value->>'paymentDate',d.created_at),d.created_at)::date between d1 and d2)
    ));
  elsif m = 'accounting' then
    result := jsonb_build_array(
      jsonb_build_object(
        'key','journal_entries','title','Journal entries / القيود المحاسبية',
        'columns',jsonb_build_array(
          'id','entryNumber','entryDate','description','currency','exchangeRate',
          'totalDebit','totalCredit','status','referenceType','referenceId',
          'orderId','createdAt','updatedAt','createdBy','updatedBy','rawData'
        ),
        'rows',(select coalesce(jsonb_agg(jsonb_build_array(
          j.id,j.data->>'entryNumber',j.data->>'entryDate',j.data->>'description',
          j.data->>'currency',j.data->>'exchangeRate',j.data->>'totalDebit',
          j.data->>'totalCredit',j.data->>'status',j.data->>'referenceType',
          j.data->>'referenceId',j.data->>'orderId',j.created_at,j.updated_at,
          coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),j.data::text
        ) order by public.erp_try_timestamptz(j.data->>'entryDate',j.created_at) desc),'[]'::jsonb)
        from public.erp_journal_entries j
        left join auth.users cu on cu.id=j.created_by
        left join auth.users uu on uu.id=j.updated_by
        where j.company_id=p_company_id and not j.is_deleted
          and coalesce(public.erp_try_timestamptz(j.data->>'entryDate',j.created_at),j.created_at)::date between d1 and d2)
      ),
      jsonb_build_object(
        'key','journal_lines','title','Journal lines / تفاصيل القيود',
        'columns',jsonb_build_array(
          'id','entryId','accountId','accountCode','accountName','debit','credit',
          'currency','exchangeRate','costCenterId','description','createdAt',
          'updatedAt','createdBy','updatedBy','rawData'
        ),
        'rows',(select coalesce(jsonb_agg(jsonb_build_array(
          l.id,l.data->>'entryId',l.data->>'accountId',a.code,a.name,
          l.data->>'debit',l.data->>'credit',l.data->>'currency',l.data->>'exchangeRate',
          l.data->>'costCenterId',l.data->>'description',l.created_at,l.updated_at,
          coalesce(cu.email,'system'),coalesce(uu.email,cu.email,'system'),l.data::text
        ) order by l.created_at desc),'[]'::jsonb)
        from public.erp_journal_lines l
        left join public.erp_accounts a on a.organization_id=l.company_id and a.account_id=l.data->>'accountId'
        left join auth.users cu on cu.id=l.created_by
        left join auth.users uu on uu.id=l.updated_by
        where l.company_id=p_company_id and not l.is_deleted
          and l.created_at::date between d1 and d2)
      )
    );
  else
    return public.erp_cloud_contextual_report(p_company_id,m,p_start_date,p_end_date);
  end if;

  return result;
end;
$$;

grant execute on function public.erp_cloud_model_report(uuid,text,date,date) to authenticated;

commit;
