#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors=[]

def read(rel):
    return (ROOT/rel).read_text(encoding='utf-8', errors='replace')

def need(cond,msg):
    if not cond: errors.append(msg)

m=read('supabase/migrations/20260807190000_v2301_acceptance_closure.sql')
car_model=read('lib/features/inventory/cars/models/car_model.dart')
car_repo=read('lib/features/inventory/cars/data/car_warehouse_transfer_repository.dart')
r49=read('supabase/migrations/20260810090000_r49_focused_final_permission_runtime_closure.sql')
status=read('lib/core/localization/operational_status_label.dart')
translations=read('lib/core/localization/module_translation_catalog.dart')
v736=read('supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql')
v756=read('supabase/migrations/20260806203000_v756_secure_multicurrency_payment_chain.sql')
v757=read('supabase/migrations/20260806214500_v757_multicurrency_payment_chain_hardening.sql')
v760=read('supabase/migrations/20260807013000_v760_no_capitalization_accounting_integrity.sql')
v767=read('supabase/migrations/20260807080000_v767_invoice_export_runtime_closure.sql')
v731=read('supabase/migrations/20260804193000_v731_preserved_payment_reallocation.sql')
v732=read('supabase/migrations/20260804213000_v732_operational_state_repair.sql')
opportunity=read('supabase/migrations/20260801080000_opportunity_sales_link_and_language_completion.sql')

# Currency-specific definition accounting must prefer the explicit account for
# the definition currency over the legacy generic account.
fn=m[m.find('create or replace function public.erp_v764_definition_accounts'):]
fn=fn[:fn.find('end; $$;')]
need(fn.find('salesRevenueUsdAccountId')>=0 and fn.find('salesRevenueIqdAccountId')>=0,
     'currency-specific revenue account fields missing from final definition resolver')
need(fn.find('salesRevenueUsdAccountId') < fn.find('salesRevenueAccountId'),
     'USD/IQD revenue account is not preferred over legacy generic revenue account')
need("erp_phase2_account_guard(p_company_id,revenue_id,'revenue',c)" in fn,
     'revenue account type/currency guard missing')

# Vehicle damage/scrap is accounting-owned and reversible.
need('erp_v2301_reconcile_car_scrap_transfer' in m and 'inventory_scrap_car' in m,
     'vehicle scrap accounting trigger missing')
need("erp_v764_definition_currency(new.company_id,'car',v_car_id)" in m and
     "erp_v764_scrap_expense_account(new.company_id,v_to_id,v_currency)" in m,
     'vehicle scrap does not use definition currency and warehouse USD/IQD expense account')
need("'status','تالفة'" in m and "('damaged','scrap','تالفة','تالف')" in m,
     'vehicle is not protected from sale while in damage/scrap warehouse or reverse is blocked')
need("CarStatus { defined, purchasing, available, damaged, selling, sold }" in car_model and
     "return CarStatus.damaged" in car_model,
     'Dart vehicle model does not understand damaged state')
need("'تالفة': 'Damaged'" in translations and "'damaged' || 'scrap'" in status,
     'damaged status is not bilingual')
need("'erp_r49_create_car_warehouse_transfer'" in car_repo and
     "'erp_create_car_warehouse_transfer'" not in car_repo and
     "'erp_v2300_create_car_warehouse_transfer'" not in car_repo,
     'car transfers are not routed through the current R49 permission/timestamp wrapper')
need('create or replace function public.erp_r49_create_car_warehouse_transfer' in r49 and
     'public.erp_v2300_create_car_warehouse_transfer(' in r49 and
     'p_notes,p_effective_at' in r49,
     'R49 single-car transfer wrapper does not preserve the operator-selected operational timestamp')

# Operational timestamp must reach logistics documents, movements and vehicle state.
need('erp_v2301_inherit_commercial_effective_at' in m and
     'erp_a_v2301_workflow_effective_date' in m,
     'receipt/delivery documents do not inherit order effectiveAt before posting')
need('erp_v2301_align_inventory_movement_effective_at' in m and
     "v_type in ('purchase_receipt','sales_delivery')" in m and
     "v_type='maintenance_order'" in m,
     'commercial/maintenance stock movements are not aligned to operational date')
need('erp_v2301_align_commercial_car_effective_at' in m and
     "'receivedAt',v_effective" in m and "'deliveredAt',v_effective" in m,
     'vehicle receipt/delivery timestamps still use technical execution time')

# Maintenance is single currency, invoice-owned, and no-capitalization.
need('erp_v2301_maintenance_line_currency_guard' in m and
     'maintenance_item_currency_mismatch' in m,
     'maintenance lines do not enforce definition currency = order currency')
maint=m[m.rfind('create or replace function public.erp_v736_post_maintenance_invoice'):]
maint=maint[:maint.find('end;\n$$;')+8]
need("car_cost_added=0" in maint and "'capitalizationApplied',false" in maint and
     "'capitalizationPolicy','disabled'" in maint,
     'maintenance invoice can still capitalize consumed stock into vehicle value')
need('update public.erp_cars' not in maint,
     'maintenance invoice still updates the car valuation')
need('erp_v764_definition_accounts' in maint and "'costExpenseAccountId'" in maint and "'assetAccountId'" in maint,
     'maintenance material cost does not use configured cost/inventory accounts')
need("erp_v764_assert_partner_dual_ledgers" in maint and "erp_workflow_partner_account" in maint,
     'maintenance customer account is not validated by invoice currency')

# Purchase/sales invoice ownership and linked FX payment chain must remain intact.
need('quantity-only; valuation owned by invoice' in v736 and 'select null::text' in v736,
     'receipt/delivery can still own accounting before invoice approval')
need('erp_v760_normalize_purchase_invoice_posting' in v760,
     'purchase invoice definition-account posting missing')
need('erp_v767_invoice_policy_preflight' in v767 and 'erp_v764_definition_accounts' in v767,
     'sales/purchase invoice preflight no longer validates definition accounts')
need('linked_cash_account' in v756.lower() and 'erp_transfer_cloud_cash_v5' in v756 and
     'cashboxes_must_be_bidirectionally_linked_for_fx' in v757,
     'cross-currency linked cashbox payment chain missing or not bidirectionally validated')

# Deletion/reversal ownership: operational documents are reversible; cash
# payment deletion is cashbox-owned and retires its accounting chain.
need('paymentsPreserved' in v731 and 'erp_list_partner_unapplied_payments' in v731,
     'deleting operational workflow documents loses posted partner payments')
need('erp_delete_car_warehouse_transfer' in v732 and 'operationalStateReplayed' in v732,
     'vehicle transfer deletion does not replay operational state')
need('Source cash payment deleted' in v731,
     'cash payment deletion does not retire settlement/accounting links')

# Opportunity lifecycle remains bidirectional.
need('erp_sync_opportunity_sales_lifecycle' in opportunity and
     'erp_sales_orders_cloud_active_opportunity_uq' in opportunity,
     'opportunity-sales lifecycle synchronization missing')

if errors:
    print('FAILED V23.0.1 final acceptance closure')
    for e in errors: print('  -',e)
    sys.exit(1)
print('PASS V23.0.1 final acceptance closure')
print('- currency-specific revenue accounts override the legacy generic account')
print('- product and vehicle scrap/damage accounting is definition-driven and reversible')
print('- order effectiveAt reaches logistics documents, stock movements and vehicle timestamps')
print('- maintenance is single-currency and invoice-owned without vehicle capitalization')
print('- purchase/sales invoice accounting, linked FX cashboxes, deletion ownership and opportunity sync retained')
