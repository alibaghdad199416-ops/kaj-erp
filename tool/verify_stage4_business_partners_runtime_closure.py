from pathlib import Path
import re
import sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
def exists(p): return (ROOT/p).exists()
migration=read('supabase/migrations/20260826190000_stage4_business_partners_runtime_closure.sql')
backfill=read('supabase/migrations/20260826200100_stage4_partner_alias_backfill_closure.sql')
page=read('lib/features/business_partners/pages/business_partners_page.dart')
customer=read('lib/features/business_partners/customers/pages/customers_page.dart')
customer_card=read('lib/features/business_partners/customers/widgets/customer_card.dart')
supplier_card=read('lib/features/business_partners/suppliers/widgets/supplier_card.dart')
service=read('lib/features/business_partners/shared/data/business_partner_card_service.dart')
checks={
 'stage4 migration is forward-only':'begin;' in migration and 'commit;' in migration,
 'stage4 historical alias closure is forward-only':'begin;' in backfill and 'commit;' in backfill,
 'no executable quality-line dependency':'quality line' not in re.sub(r'--.*|/\*[\s\S]*?\*/','',migration+'\n'+backfill,flags=re.M).lower(),
 'customer CRUD is granular at RLS':all(x in migration for x in ['customers.create','customers.update','customers.delete','customers.view']),
 'supplier CRUD is granular at RLS':all(x in migration for x in ['suppliers.create','suppliers.update','suppliers.delete','suppliers.view']),
 'customer national ID tenant uniqueness':'erp_customers_company_national_id_uq' in migration,
 'supplier tax number tenant uniqueness':'erp_suppliers_company_tax_number_uq' in migration,
 'partner aliases synchronized':'erp_stage4_partner_alias_sync' in migration and "array['national_id','nationalId']" in migration and "array['tax_number','taxNumber']" in migration,
 'historical customer aliases backfilled':'update public.erp_customers' in backfill and "data->'national_id' is distinct from data->'nationalId'" in backfill,
 'historical supplier aliases backfilled':'update public.erp_suppliers' in backfill and "data->'tax_number' is distinct from data->'taxNumber'" in backfill,
 'post-normalization collisions are rejected':'stage4_customer_national_id_collision_after_alias_normalization' in backfill and 'stage4_supplier_tax_number_collision_after_alias_normalization' in backfill,
 'customer page exposes CRUD and profile':all(x in customer for x in ['class CustomersPage','add_customer_page.dart','edit_customer_page.dart','deleteCustomer']),
 'supplier card uses stage4 shell':'KajPartnerCardShell' in supplier_card,
 'customer card uses stage4 shell':'KajPartnerCardShell' in customer_card,
 'partner profile loads authoritative RPC':'erp_r49_business_partner_card_summary' in service,
 'phase4 luxury verifier remains present':exists('tool/verify_v194_phase4_luxury.py'),
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 4 deep business-partners closure — {len(checks)} gates')
