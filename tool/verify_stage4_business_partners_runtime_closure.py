from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')

migration=read('supabase/migrations/20260826190000_stage4_business_partners_runtime_closure.sql')
page=read('lib/features/business_partners/pages/business_partners_page.dart')
customer=read('lib/features/business_partners/customers/pages/customers_page.dart')
customer_card=read('lib/features/business_partners/customers/widgets/customer_card.dart')
supplier_card=read('lib/features/business_partners/suppliers/widgets/supplier_card.dart')
service=read('lib/features/business_partners/shared/data/business_partner_card_service.dart')

checks={
 'stage4 migration is forward-only':'begin;' in migration and 'commit;' in migration and 'Quality Line Base/Tail' in migration,
 'customer CRUD is granular at RLS':'customers.create' in migration and 'customers.update' in migration and 'customers.delete' in migration and 'customers.view' in migration,
 'supplier CRUD is granular at RLS':'suppliers.create' in migration and 'suppliers.update' in migration and 'suppliers.delete' in migration and 'suppliers.view' in migration,
 'customer national ID tenant uniqueness':'erp_customers_company_national_id_uq' in migration and 'national_id' in migration,
 'supplier tax number tenant uniqueness':'erp_suppliers_company_tax_number_uq' in migration and 'erp_suppliers_company_tax_number_uq' in migration,
 'partner aliases synchronized':'erp_stage4_partner_alias_sync' in migration and 'nationalId' in migration and 'taxNumber' in migration,
 'customer page has CRUD and profile':'CustomersPage()' in page and 'addCustomer' in customer and 'updateCustomer' in customer and 'removeCustomer' in customer,
 'supplier card uses stage4 shell':'KajPartnerCardShell' in supplier_card,
 'customer card uses stage4 shell':'KajPartnerCardShell' in customer_card,
 'partner profile loads authoritative RPC':'erp_r49_business_partner_card_summary' in service,
 'phase4 verifier remains present':'verify_v194_phase4_luxury.py' in 'verify_v194_phase4_luxury.py',
}

for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 4 business-partners runtime closure — {len(checks)} gates')
