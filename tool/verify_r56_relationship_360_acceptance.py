#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(__file__).resolve().parents[1]
migrations = sorted((root / 'supabase/migrations').glob('*.sql'))
migration = (root / 'supabase/migrations/20260811123333_r56_opportunity_maintenance_vehicle_partner_360.sql').read_text(encoding='utf-8')
r561_path = root / 'supabase/migrations/20260811133429_r56_1_business_acceptance_ci_correction.sql'
r561 = r561_path.read_text(encoding='utf-8')
repo = (root / 'lib/features/maintenance/data/maintenance_repository.dart').read_text(encoding='utf-8')
opportunity = (root / 'lib/features/customer_service/pages/add_opportunity_page.dart').read_text(encoding='utf-8')
pdf = (root / 'lib/core/printing/vehicle_service_card_pdf_service.dart').read_text(encoding='utf-8')
partner = (root / 'lib/features/business_partners/shared/data/business_partner_card_service.dart').read_text(encoding='utf-8')
partner_dialog = (root / 'lib/features/business_partners/shared/widgets/business_partner_profile_dialog.dart').read_text(encoding='utf-8')
partner_route = (root / 'lib/features/business_partners/shared/data/partner_record_route.dart').read_text(encoding='utf-8')
fresh = (root / 'tool/verify_fresh_database.ps1').read_text(encoding='utf-8')
failures = []

def need(label, condition):
    print(('PASS ' if condition else 'FAIL ') + label)
    if not condition: failures.append(label)

need('R56.1 remains immutable after R56', r561_path in migrations
     and migrations.index(r561_path) > 0
     and migrations[migrations.index(r561_path) - 1].name
         == '20260811123333_r56_opportunity_maintenance_vehicle_partner_360.sql')
need('Opportunity maintenance is canonical and idempotent', all(x in migration for x in (
    'uq_r56_maintenance_active_opportunity', 'maintenance_vehicle_immutable',
    'maintenance_opportunity_vehicle_mismatch', 'return v_existing')))
need('Browser action saves and opens linked maintenance', all(x in opportunity for x in (
    'Save & Create Maintenance Draft', 'findByOpportunity', 'initialCarId', 'opportunityId')))
need('Opportunity without car opens explicit vehicle selection',
     'Link the opportunity to a vehicle before creating a maintenance draft.' not in opportunity
     and all(value in (root / 'lib/features/maintenance/pages/add_maintenance_order_page.dart').read_text(encoding='utf-8')
             for value in ('resolveInitialMaintenanceVehicle', "opportunityId?.trim()", 'return null')))
need('R56.1 guard allows absent opportunity car but validates an existing car',
     'v_car_id is not null and v_car_id<>new.source_car_id' in r561
     and 'maintenance_vehicle_company_mismatch' in r561)
need('Repository uses authoritative maintenance RPCs', all(x in repo for x in (
    'erp_r56_find_maintenance_by_opportunity', 'erp_r56_create_cloud_maintenance_order'))
    and ('erp_r56_vehicle_service_card' in repo or 'erp_r90_vehicle_service_card' in repo))
for forbidden in ('purchasePrice', 'acquisitionCost', 'unitCost', 'profit', 'carCostAdded'):
    need(f'PDF excludes {forbidden}', forbidden not in pdf)
r90 = (root / 'supabase/migrations/20260820113000_r90_phase11_final_acceptance_closure.sql').read_text(encoding='utf-8')
r9 = (root / 'supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql').read_text(encoding='utf-8')
need('Vehicle PDF exposes maintenance cost columns only through permission-filtered card payload',
     all(value in pdf for value in ('laborCost','partsCost','totalCost'))
     and 'erp_r90_vehicle_service_card' in repo
     and 'erp_r9_filter_result_json' in (root / 'supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql').read_text(encoding='utf-8')
     and all(value in r9 for value in ("when 'laborCost' then 'laborCost'","when 'partsCost' then 'partsCost'","when 'totalCost' then 'totalCost'"))
     and 'v_can_history' in r90)
need('Partner cards use permission-aware 360 RPC', 'erp_r56_business_partner_360' in partner)
need('Canonical supplier child documents route through their purchase order',
     all(value in partner_route for value in ("type.startsWith('purchases_')", 'parentId',
                                               'PartnerRecordDestination.purchaseOrder')))
need('Partner accounting has dedicated complete presentations',
     all(value in partner_dialog for value in ('_PartnerAccountsSection', '_PartnerLedgerSection',
         "account['openingBalance']", "account['currentBalance']", "movement['documentReference']",
         "movement['currency']")))
ui_paths = (
    root / 'lib/features/business_partners/shared/widgets/business_partner_profile_dialog.dart',
    root / 'lib/features/business_partners/customers/pages/customers_page.dart',
    root / 'lib/features/business_partners/suppliers/pages/suppliers_page.dart',
    root / 'lib/features/inventory/cars/pages/vehicle_service_card_page.dart',
    root / 'lib/features/maintenance/pages/add_maintenance_order_page.dart',
    root / 'lib/features/customer_service/pages/add_opportunity_page.dart',
)
mojibake_markers = ('Ã˜', 'Ã™', 'Ãƒ', 'Ã‚', 'ï¿½', 'Ø', 'Ù')
need('R56/R56.1 UI contains no mojibake markers',
     all(marker not in path.read_text(encoding='utf-8')
         for path in ui_paths for marker in mojibake_markers))
need('Partner 360 uses field-filtered opportunity projection',
     "erp_r49_opportunity_command('list'" in r561 and 'jsonb_agg(r.payload' not in r561)
need('Vehicle profile and partner chains are actionable and complete',
     'Open Maintenance Order' in (root / 'lib/features/inventory/cars/pages/vehicle_service_card_page.dart').read_text(encoding='utf-8')
     and all(value in r561 for value in ("d.module||'_'||d.document_type",'erp_commercial_workflow_documents','accountsByCurrency','ledgerMovements')))
need('Fresh database executes R56 SQL proof', 'verify_r56_opportunity_maintenance_vehicle_partner_360.sql' in fresh)
need('R56 SQL functions use fixed search path', migration.count('set search_path=public') >= 5)
need('R56 browser functions deny anon/public', migration.count('from public,anon') >= 4)

if failures:
    print(f'R56 acceptance failed: {len(failures)} check(s)', file=sys.stderr)
    sys.exit(1)
print('R56 relationship and 360 acceptance PASS')
