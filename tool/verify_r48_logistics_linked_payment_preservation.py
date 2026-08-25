from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
failures = []

def text(path):
    return (root / path).read_text(encoding='utf-8')

def need(label, ok):
    print(('PASS ' if ok else 'FAIL ') + label)
    if not ok:
        failures.append(label)

v736 = text('supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql')
v740 = text('supabase/migrations/20260806040000_v740_definition_accounting_fx_payments_compact_numbers.sql')
v756 = text('supabase/migrations/20260806203000_v756_secure_multicurrency_payment_chain.sql')
v757 = text('supabase/migrations/20260806214500_v757_multicurrency_payment_chain_hardening.sql')
r22 = text('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql')
r37 = text('supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql')
r46 = text('supabase/migrations/20260809234500_r46_account_binding_alias_canonical_closure.sql')
r46_compact = ' '.join(r46.split())
r47 = text('supabase/migrations/20260810001000_r47_production_runtime_dependency_closure.sql')
dialog = text('lib/core/finance/invoice_payment_batch_dialog.dart')
maint_repo = text('lib/features/maintenance/data/maintenance_repository.dart')
package = text('package.json')

# Purchase receipt approval owns physical receipt quantities, not accounting.
need('purchase receipt approval increases warehouse quantity',
     "create or replace function public.erp_approve_cloud_purchase_receipt" in v736
     and "'quantity',v_qty+a.quantity" in v736
     and "'purchase_in',a.quantity" in v736
     and "'accountingOwner','invoice'" in v736)

# Sales delivery approval owns physical delivery quantities, not accounting.
need('sales delivery approval decreases warehouse quantity',
     "create or replace function public.erp_approve_cloud_sales_delivery" in v736
     and "'quantity',public.erp_try_numeric(data->>'quantity',0)-a.quantity" in v736
     and "'sale_out',-a.quantity" in v736
     and "'accountingOwner','invoice'" in v736)

# Maintenance stock issue approval owns parts quantity deduction.
need('maintenance stock issue approval decreases warehouse quantity',
     "elsif o.workflow_stage='stock_issue_draft' then" in v740
     and "'quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity" in v740
     and "'maintenance_out',-p.quantity" in v740
     and "workflow_stage='stock_issue_approved'" in v740)

# Maintenance accounting remains invoice-owned after logistics issue.
need('maintenance logistics remains non-accounting until invoice',
     "create or replace function public.erp_phase3_post_maintenance_issue" in v736
     and "select null::text" in v736
     and "perform public.erp_v736_post_maintenance_invoice(p_company_id,o.id);" in v740)

# Runtime maintenance UI/repository still traverses the canonical workflow wrapper.
need('maintenance runtime still uses canonical advance wrapper',
     "erp_r37_advance_maintenance_workflow" in maint_repo
     and "perform public.erp_advance_cloud_maintenance_workflow" in r37)

# UI requires configured linked invoice-currency cashbox for cross-currency payments.
need('cross-currency payment UI requires linked invoice-currency cashbox',
     "row.paymentCurrency != widget.invoiceCurrency" in dialog
     and "اختر الصندوق المرتبط بعملة الفاتورة" in dialog
     and "linkedCashAccountId" in dialog
     and "_configuredLinkedCashboxFor" in dialog)

# Backend validates source currency, linked target currency, and bidirectional link.
need('secure payment backend enforces linked cashboxes',
     "payment_cashbox_currency_mismatch" in v757
     and "linked_cashbox_must_use_invoice_currency" in v757
     and "cashboxes_must_be_bidirectionally_linked_for_fx" in v757
     and "erp_resolve_linked_cash_account" in v757)

# Sales/purchase payment batch is invoice-owned and uses secure linked-payment engine.
need('sales and purchase payments use secure linked payment chain',
     "create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch" in v757
     and "r:=public.erp_execute_secure_linked_payment_v1" in v757
     and "status='approved'" in v757)

# Maintenance payments share the same secure linked-payment chain.
need('maintenance payments use secure linked payment chain',
     "create or replace function public.erp_v737_record_maintenance_payment" in v756
     and "r:=public.erp_execute_secure_linked_payment_v1" in v756
     and "maintenance_approved_invoice_required" in v756)

# Direct FX cash transfers continue to require configured linking; R47 preserves this by routing legacy calls to R22.
need('cashbox FX transfer link guard preserved through R47',
     "perform public.erp_r22_transfer_cloud_cash" in r47
     and "linked:=public.erp_resolve_linked_cash_account" in r22
     and "cashboxes_not_linked_for_fx" in r22)

# R46 must not move accounting validation back into order-line approval.
need('R46 invoice accounting boundary still preserved',
     "Accounting validation/posting belongs to invoice approval" in r46
     and "erp_v764_definition_currency" in r46
     and "erp_phase2_item_accounts( new.company_id" not in r46_compact)

need('R48 verifier registered', 'verify:r48' in package)

if failures:
    sys.exit(1)
print('PASS R48 logistics/linked-payment preservation — 12 gates')
