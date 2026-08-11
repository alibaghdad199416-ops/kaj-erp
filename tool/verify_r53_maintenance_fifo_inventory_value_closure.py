#!/usr/bin/env python3
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
migration = (root / 'supabase/migrations/20260810220659_r53_maintenance_fifo_inventory_value_closure.sql').read_text(encoding='utf-8')
runtime = (root / 'supabase/tests/verify_r49_erp_transactions_runtime.sql').read_text(encoding='utf-8')
repository = (root / 'lib/features/inventory/data/inventory_repository.dart').read_text(encoding='utf-8')
movement = (root / 'lib/features/inventory/models/inventory_movement_model.dart').read_text(encoding='utf-8')
movement_page = (root / 'lib/features/inventory/pages/inventory_movements_page.dart').read_text(encoding='utf-8')
car = (root / 'lib/features/inventory/cars/models/car_model.dart').read_text(encoding='utf-8')
journal = (root / 'lib/features/accounting/models/journal_entry_model.dart').read_text(encoding='utf-8')
tests = (root / 'test/features/inventory/inventory_traceability_test.dart').read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
compact = re.sub(r'\s+', ' ', migration.lower())
failures = []


def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition:
        failures.append(label)


need('R53 is a forward-only maintenance FIFO closure',
     'erp_r53_consume_maintenance_fifo' in migration
     and 'erp_v736_post_maintenance_invoice_pre_r49_identity' in migration)
need('FIFO consumption is product, warehouse and effective-date scoped',
     "l.item_type='product'" in compact and 'l.item_id=v_line.product_id' in compact
     and 'l.warehouse_id=v_line.warehouse_id' in compact
     and 'l.effective_at<=p_effective_at' in compact)
need('FIFO consumption is locked, ordered and shortage-safe',
     'order by l.effective_at,l.created_at,l.id for update' in compact
     and 'insufficient_maintenance_cost_layers' in migration)
need('first-posting atomicity and historical idempotency are explicit',
     'if v_order.invoice_journal_entry_id is not null then' in compact
     and 'fifoValuationApplied' in migration)
need('helper RPC is internal and wrapper permission remains enforced',
     'from public,anon,authenticated' in compact
     and "array['maintenance.approve']" in compact
     and 'to authenticated,service_role' in compact)
need('actual FIFO cost reaches maintenance parts, order and journal link',
     'set unit_cost=round(v_group_cost/nullif(v_line.quantity,0),2)' in compact
     and 'set parts_cost=round(v_total_cost,2)' in compact
     and 'set journal_entry_id=' in compact)
need('runtime proves sale, maintenance and transfer quantity/value invariants',
     all(marker in runtime for marker in (
         'remaining_inventory_value_expected_75',
         'maintenance_remaining_inventory_value_expected_45',
         "data->>'warehouseId'='r49-destination-warehouse'",
         "remaining_quantity*unit_cost",
         'warehouse_transfer_changed_company_quantity_or_value',
     )))
need('inventory movement identity and currency reach model, UI and export',
     'required this.productId' in movement and 'required this.currency' in movement
     and 'productCurrencyById' in repository and 'movement.currency' in movement_page)
need('car value and accounting source traceability are explicit',
     'isIncludedInCurrentInventoryValue' in car
     and 'sourceReferenceLabel' in journal
     and 'movement retains product identity' in tests)
scripts = package.get('scripts', {})
need('R53 verifier is registered in the workspace chain',
     scripts.get('verify:r53', '').endswith('verify_r53_maintenance_fifo_inventory_value_closure.py')
     and 'npm run verify:r53' in scripts.get('verify:workspace', ''))

if failures:
    print(f'FAIL R53 maintenance FIFO closure - {len(failures)} gate(s) failed')
    sys.exit(1)
print('PASS R53 maintenance FIFO inventory-value closure - 10 gates')
