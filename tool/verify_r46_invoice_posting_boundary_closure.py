from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]

def text(p): return (root/p).read_text(encoding='utf-8')
def need(label, ok):
    print(('PASS ' if ok else 'FAIL ')+label)
    if not ok: failures.append(label)
failures=[]
r46=text('supabase/migrations/20260809234500_r46_account_binding_alias_canonical_closure.sql')
r736=text('supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql')
r22=text('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql')
r2301=text('supabase/migrations/20260807190000_v2301_acceptance_closure.sql')
r44=text('tool/verify_r44_thumbnail_performance_closure.py')
r46_compact=' '.join(r46.split())
need('order guard is currency-only', 'erp_v764_definition_currency' in r46 and 'erp_phase2_item_accounts( new.company_id' not in r46_compact and 'erp_v764_definition_accounts( new.company_id' not in r46_compact)
need('purchase receipt is quantity-only', "'quantity-only; valuation owned by invoice'" in r736 and 'create or replace function public.erp_phase2_post_purchase_receipt' in r736 and 'select null::text' in r736)
need('sales delivery is quantity-only', "'quantity-only; valuation owned by invoice'" in r736 and 'create or replace function public.erp_phase2_post_sales_delivery' in r736)
need('maintenance issue accounting disabled', 'create or replace function public.erp_phase3_post_maintenance_issue' in r736 and 'select null::text' in r736)
need('sales invoice owns posting', "perform public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales')" in r22)
need('purchase invoice owns posting', 'erp_r22_post_purchase_invoice_direct(p_company_id,p_invoice_id)' in r22)
need('maintenance invoice owns posting', 'create or replace function public.erp_v736_post_maintenance_invoice' in r2301 and "'maintenance_invoice_revenue'" in r2301 and "'maintenance_invoice_cost_'" in r2301)
need('canonical cost aliases prefer explicit binding', "v_data->>'salesCostExpenseAccountId'" in r46 and "v_data->>'costOfSalesAccountId'" in r46)
need('MULTI fallback is not written into strict master bindings', 'if v_asset_exact and v_expense_exact then' in r46)
need('R44 verifier retained', 'R44 thumbnail performance closure' in r44)
if failures:
    sys.exit(1)
print('PASS R46 invoice posting boundary/account alias closure — 10 gates')
