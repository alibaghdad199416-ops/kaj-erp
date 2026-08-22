param([switch]$Reset)
$ErrorActionPreference = "Stop"
$ApiUrl = "http://127.0.0.1:54321"
$DbConnection = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"

function Invoke-SupabaseQuery {
    param(
        [Parameter(Mandatory=$true)][string]$Sql
    )
    $env:PGPASSWORD = "postgres"
    $result = & psql -h 127.0.0.1 -p 54322 -U postgres -d postgres -c $Sql
    return $result
}

if ($Reset) {
    Write-Host "Resetting local database..."
    & supabase db reset --local
} else {
    Write-Host "Applying migration function..."
    $Sql = @"
CREATE OR REPLACE FUNCTION public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
RETURNS setof jsonb
LANGUAGE SQL SECURITY DEFINER SET search_path=public AS
$$
SELECT jsonb_build_object(
  'id', o.id::text,
  'orderNumber', o.order_number,
  'customerId', o.customer_id,
  'customerName', coalesce(c.data->>'name', ''),
  'status', o.status,
  'currency', o.currency,
  'exchangeRate', o.exchange_rate,
  'subtotal', o.subtotal,
  'discount', o.discount,
  'total', o.total,
  'notes', o.notes,
  'createdAt', o.created_at::text,
  'updatedAt', o.updated_at::text,
  'deliveryId', d.id::text,
  'deliveryStatus', d.status,
  'invoiceId', i.id::text,
  'invoiceStatus', i.status,
  'invoiceRemaining', coalesce(nullif(i.payload->>'remainingAmount','')::numeric, 0),
  'createdBy', o.created_by::text,
  'createdByName', coalesce(nullif(btrim(p.full_name), ''), o.created_by::text, ''),
  'carId', (SELECT payload->>'carId' FROM public.erp_records WHERE company_id = o.company_id AND entity_type = 'opportunities' AND record_id = o.opportunity_id),
  'carName', concat_ws(' ', car.data->>'brand', car.data->>'model', car.data->>'year')
)
FROM erp_sales_orders_cloud o
LEFT JOIN erp_customers c ON c.id = o.customer_id AND c.company_id = o.company_id AND NOT c.is_deleted
LEFT JOIN lateral (
  SELECT x.*
  FROM erp_commercial_workflow_documents x
  WHERE x.company_id = o.company_id AND x.module = 'sales'
    AND x.document_type = 'delivery' AND x.parent_id = o.id AND NOT x.is_deleted
  ORDER BY x.created_at DESC LIMIT 1
) d ON TRUE
LEFT JOIN lateral (
  SELECT x.*
  FROM erp_commercial_workflow_documents x
  WHERE x.company_id = o.company_id AND x.module = 'sales'
    AND x.document_type = 'invoice' AND x.parent_id = o.id AND NOT x.is_deleted
  ORDER BY x.created_at DESC LIMIT 1
) i ON TRUE
LEFT JOIN public.profiles p ON p.id = o.created_by
LEFT JOIN erp_cars car ON car.company_id = o.company_id AND car.id = (SELECT payload->>'carId' FROM public.erp_records WHERE company_id = o.company_id AND entity_type = 'opportunities' AND record_id = o.opportunity_id)
WHERE o.company_id = p_company_id AND NOT o.is_deleted
  AND public.erp_is_company_member(p_company_id)
ORDER BY o.created_at DESC;
$$
;

REVOKE ALL ON FUNCTION public.erp_list_cloud_sales_workflow_orders(uuid) FROM PUBLIC, ANON;
GRANT EXECUTE ON FUNCTION public.erp_list_cloud_sales_workflow_orders(uuid) TO authenticated;
"@
    $result = Invoke-SupabaseQuery -Sql $Sql
    Write-Host "Function applied successfully"
    Write-Host "Result: $result"
}