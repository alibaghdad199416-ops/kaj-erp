from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
checks={}
m=read('supabase/migrations/20260826180000_stage3_maintenance_integrity_closure.sql')
executable='\n'.join(line for line in m.splitlines() if not line.strip().startswith('--'))
checks['forward-only stage3 migration']='begin;' in m and 'notify pgrst' in m and 'commit;' in m
checks['no executable quality-line dependency']='quality line' not in executable.lower() and 'qualityline.' not in executable.lower()
checks['single active maintenance invoice guard']='erp_r49_guard_single_active_maintenance_invoice' in m and 'pg_advisory_xact_lock' in m and 'active_maintenance_invoice_exists' in m
checks['paid invoice requires customer and currency']='paid_maintenance_customer_required' in m and 'maintenance_currency_invalid' in m
checks['invoice lifecycle is bounded']='maintenance_invoice_stage_invalid' in m and "'invoice_draft','invoice_approved','paid','completed'" in m
checks['maintenance approval is protected']="array['maintenance.approve']" in m
checks['stock issue accounting boundary']='maintenance_out' in m and 'erp_phase3_refresh_maintenance_products' in m and 'erp_phase3_post_maintenance_issue' in m
checks['invoice posting remains owned']='erp_v736_post_maintenance_invoice' in m and 'erp_v736_post_maintenance_invoice_pre_r49_identity' in m
checks['invoice number remains compact']='maintenance_invoice' in m and "'MINV'" in m
page=read('lib/features/maintenance/pages/maintenance_page.dart')
checks['maintenance UI gates CRUD actions']='maintenance.create' in page and 'maintenance.update' in page and 'maintenance.delete' in page and 'maintenance.cancel' in page and 'cashbox.receipt' in page
legacy=read('supabase/migrations/20260803220000_runtime_maintenance_delete_cashflow_partner_language_fix.sql')
checks['maintenance payment requires cash receipt permission']="array['cashbox.receipt']" in legacy
checks['maintenance cancellation requires cancel permission']="array['maintenance.cancel']" in legacy
checks['maintenance deletion requires delete permission']="array['maintenance.delete']" in legacy
for n,v in checks.items(): print(('PASS' if v else 'FAIL'),n)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 3 deep integrity closure — {len(checks)} gates')
