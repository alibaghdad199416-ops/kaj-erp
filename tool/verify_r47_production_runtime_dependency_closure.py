from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]

def text(p): return (root/p).read_text(encoding='utf-8')
def need(label, ok):
    print(('PASS ' if ok else 'FAIL ')+label)
    if not ok: failures.append(label)
failures=[]
r47=text('supabase/migrations/20260810001000_r47_production_runtime_dependency_closure.sql')
r46=text('supabase/migrations/20260809234500_r46_account_binding_alias_canonical_closure.sql')
r46_compact=' '.join(r46.split())
need('deterministic UUID helper restored', 'create or replace function public.erp_deterministic_uuid' in r47 and 'md5(p_seed)' in r47)
need('legacy cash transfer routes to R22', 'perform public.erp_r22_transfer_cloud_cash' in r47 and 'erp_ensure_workflow_fx_accounts' not in r47)
need('purchase invoice JSON object count fixed', 'if jsonb_object_length(v_by_currency)' not in r47 and 'jsonb_object_keys(v_by_currency)' in r47)
need('maintenance reversal alias shadow fixed', 'v_now timestamptz:=now(); c record' not in r47 and 'from public.erp_inventory_fifo_consumptions c' in r47)
need('R46 order guard remains currency only', 'erp_v764_definition_currency' in r46 and 'erp_phase2_item_accounts( new.company_id' not in r46_compact)
need('R46 invoice boundary retained', 'Accounting validation/posting belongs to invoice approval' in r46)
if failures:
    sys.exit(1)
print('PASS R47 production runtime dependency closure — 6 gates')
