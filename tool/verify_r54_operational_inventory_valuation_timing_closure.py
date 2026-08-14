#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration = (root / 'supabase/migrations/20260810224144_r54_operational_inventory_valuation_timing_closure.sql').read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r49_erp_transactions_runtime.sql').read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
compact = re.sub(r'\s+', ' ', migration.lower())
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


need('R54 is forward-only and leaves R53 historical',
     'pre_r54_valuation' in migration and 'erp_r53_consume_maintenance_fifo' in migration)
need('purchase receipt registers and refreshes operational valuation',
     'erp_fifo_register_purchase_receipt' in migration
     and 'erp_r54_refresh_receipt_valuation' in migration
     and 'valuationReceiptId' in migration)
need('purchase invoice preserves receipt-owned layer state',
     'erp_r54_preserve_receipt_layer_valuation' in migration
     and 'purchase_invoice_operational_valuation_mismatch' in migration
     and 'operationalValuationPreserved' in migration)
need('sales delivery consumes FIFO without creating a journal',
     'erp_r54_consume_sales_delivery_fifo' in migration
     and 'operationalFifoAppliedAt' in migration
     and 'erp_phase2_insert_journal_at' not in migration)
need('sales invoice remains able to attach its later journal',
     "set journal_entry_id=v_entry->>'journalEntryId'" in compact
     or 'erp_v736_post_sales_invoice_costs' not in migration)
need('maintenance issue owns FIFO before invoice',
     "v_before='stock_issue_draft' and v_after='stock_issue_approved'" in compact
     and 'erp_r54_allocate_maintenance_line_costs' in migration)
need('maintenance line rounding assigns exact final remainder',
     'v_group_cost-v_assigned' in migration
     and 'maintenance_fifo_line_allocation_mismatch' in migration)
need('new helpers are internal and browser wrappers retain permissions',
     compact.count('from public,anon,authenticated') >= 8
     and "array['maintenance.approve']" in compact
     and "array['sales.approve','sales.update','sales.create']" in compact)
need('runtime captures all three pre-invoice valuation boundaries',
     all(marker in runtime for marker in (
         'purchase_receipt_operational_valuation_expected_qty_10_value_100_layers_2_no_gl',
         'sales_delivery_operational_valuation_expected_qty_15_cost_175_value_75_no_gl',
         'maintenance_issue_operational_valuation_expected_qty_2_cost_30_value_45_no_gl',
     )))
need('runtime proves invoice non-mutation and operational retry safety',
     all(marker in runtime for marker in (
         'purchase_invoice_mutated_operational_valuation',
         'sales_delivery_retry_not_idempotent',
         'maintenance_issue_retry_boundary_not_idempotent',
         'maintenance_invoice_mutated_operational_valuation',
     )))
scripts = package.get('scripts', {})
need('R54 verifier is registered in workspace verification',
     scripts.get('verify:r54', '').endswith('verify_r54_operational_inventory_valuation_timing_closure.py')
     and 'npm run verify:r54' in scripts.get('verify:workspace', ''))

if failures:
    print(f'FAIL R54 operational valuation timing closure - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R54 operational inventory valuation timing closure - 11 gates')
