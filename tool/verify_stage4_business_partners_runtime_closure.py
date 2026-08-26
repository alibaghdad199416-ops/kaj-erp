from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
def exists(p): return (ROOT/p).exists()

migration=read('supabase/migrations/20260826190000_stage4_business_partners_runtime_closure.sql')
backfill=read('supabase/migrations/20260826200000_stage4_partner_alias_backfill_closure.sql')
page=read('lib/features/business_partners/pages/business_partners_page.dart')
customer=read('lib/features/business_partners/customers/pages/customers_page.dart')
customer_card=read('lib/features/business_partners/customers/widgets/customer_card.dart')
supplier_card=read('lib/features/business_partners/suppliers/widgets/supplier_card.dart')
service=read('lib/features/business_partners/shared/data/business_partner_card_service.dart')
executable='\n'.join(line for line in (migration+'\n'+backfill).splitlines() if not line.strip().startswith('--'))
checks={
 'stage4 migration is forward-only':'begin;' in migration and 'commit;' in migration,
 'stage4 historical alias closure is forward-only':'begin;' in backfill and 'commit;' in backfill,
 'no executable quality-line dependency':'quality line' not in executable.lower() and 'qualityline.' not in executable.lower(),
 'customer CRUD is granular at RLS':'customers.create' in migration and 'customers.update' in migration and 'customers.delete' in migration and 'customers.view' in migration,
 'supplier CRUD is granular at RLS':'suppliers.create' in migration and 'suppliers.update' in migration and 'suppliers.delete' in migration and 'suppliers.view' in migration,
 'customer national ID tenant uniqueness':'erp_customers_company_national_id_uq' in migration,
 'supplier tax number tenant uniqueness':'erp_suppliers_company_tax_number_uq' in migration,
 'partner aliases synchronized':'erp_stage4_partner_alias_sync' in migration and "array['national_id','nationalId']" in migration and "array['tax_number','taxNumber']" in migration,
 'historical customer aliases backfilled':'update public.erp_customers' in backfill and "data->'national_id' is distinct from data->'nationalId'" in backfill,
 'historical supplier aliases backfilled':'update public.erp_suppliers' in backfill and "data->'tax_number' is distinct from data->'taxNumber'" in backfill,
 'post-normalization collisions are rejected':'stage4_customer_national_id_collision_after_alias_normalization' in backfill and 'stage4_supplier_tax_number_collision_after_alias_normalization' in backfill,
 'customer page exposes CRUD and profile':'CustomersPage()' in page and 'add_customer_page.dart' in customer and 'edit_customer_page.dart' in customer and 'removeCustomer' in customer,
 'supplier card uses stage4 shell':'KajPartnerCardShell' in supplier_card,
 'customer card uses stage4 shell':'KajPartnerCardShell' in customer_card,
 'partner profile loads authoritative RPC':'erp_r49_business_partner_card_summary' in service,
 'phase4 luxury verifier remains present':exists('tool/verify_v194_phase4_luxury.py'),
}
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 4 deep business-partners closure — {len(checks)} gates')
