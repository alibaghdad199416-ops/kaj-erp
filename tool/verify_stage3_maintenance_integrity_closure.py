from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
checks={}
m=read('supabase/migrations/20260826180000_stage3_maintenance_integrity_closure.sql')
checks['forward-only stage3 migration']='begin;' in m and 'notify pgrst' in m and 'commit;' in m
checks['independent of quality line base tail']='Quality Line Base/Tail' not in m
checks['single active maintenance invoice guard']='erp_r49_guard_single_active_maintenance_invoice' in m and 'pg_advisory_xact_lock' in m and 'active_maintenance_invoice_exists' in m
checks['paid invoice requires customer and currency']='paid_maintenance_customer_required' in m and 'maintenance_currency_invalid' in m
checks['invoice lifecycle is bounded']='maintenance_invoice_stage_invalid' in m and "'invoice_draft','invoice_approved','paid','completed'" in m
checks['maintenance approval is protected']="array['maintenance.approve']" in m
checks['stock issue is quantity-only']='maintenance_out' in m and 'erp_phase3_refresh_maintenance_products' in m and 'erp_v736_post_maintenance_invoice' in m
checks['no legacy maintenance posting helper']='erp_phase3_post_maintenance_issue' not in m
checks['invoice number remains compact']='maintenance_invoice' in m and "'MINV'" in m
for n,v in checks.items(): print(('PASS' if v else 'FAIL'),n)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 3 maintenance integrity closure — {len(checks)} gates')
