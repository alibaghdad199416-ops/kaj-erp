#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(__file__).resolve().parents[1]
migrations = sorted((root / 'supabase/migrations').glob('*.sql'))
migration = (root / 'supabase/migrations/20260811123333_r56_opportunity_maintenance_vehicle_partner_360.sql').read_text(encoding='utf-8')
repo = (root / 'lib/features/maintenance/data/maintenance_repository.dart').read_text(encoding='utf-8')
opportunity = (root / 'lib/features/customer_service/pages/add_opportunity_page.dart').read_text(encoding='utf-8')
pdf = (root / 'lib/core/printing/vehicle_service_card_pdf_service.dart').read_text(encoding='utf-8')
partner = (root / 'lib/features/business_partners/shared/data/business_partner_card_service.dart').read_text(encoding='utf-8')
fresh = (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8')
failures = []

def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition: failures.append(label)

need('R56 is forward-only migration 260', len(migrations) == 260 and migrations[-1].name.startswith('20260811123333_r56_'))
need('Opportunity maintenance is canonical and idempotent', all(x in migration for x in (
    'uq_r56_maintenance_active_opportunity', 'maintenance_vehicle_immutable',
    'maintenance_opportunity_vehicle_mismatch', 'return v_existing')))
need('Browser action saves and opens linked maintenance', all(x in opportunity for x in (
    'Save & Create Maintenance Draft', 'findByOpportunity', 'initialCarId', 'opportunityId')))
need('Repository uses R56 authoritative RPCs', all(x in repo for x in (
    'erp_r56_find_maintenance_by_opportunity', 'erp_r56_create_cloud_maintenance_order',
    'erp_r56_vehicle_service_card')))
for forbidden in ('purchasePrice', 'acquisitionCost', 'unitCost', 'partsCost', 'laborCost', 'totalCost', 'profit', 'carCostAdded'):
    need(f'PDF excludes {forbidden}', forbidden not in pdf)
need('Partner cards use permission-aware 360 RPC', 'erp_r56_business_partner_360' in partner)
need('Fresh database executes R56 SQL proof', 'verify_r56_opportunity_maintenance_vehicle_partner_360.sql' in fresh)
need('R56 SQL functions use fixed search path', migration.count('set search_path=public') >= 5)
need('R56 browser functions deny anon/public', migration.count('from public,anon') >= 4)

if failures:
    print(f'R56 acceptance failed: {len(failures)} check(s)', file=sys.stderr)
    sys.exit(1)
print('R56 relationship and 360 acceptance PASS')
