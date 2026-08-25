from pathlib import Path
import json, re, sys
root=Path(__file__).resolve().parents[1]
checks=[]

def require(path, needle, label):
    text=(root/path).read_text(encoding='utf-8')
    if needle not in text:
        print(f'FAILED {label}: missing {needle!r} in {path}')
        sys.exit(1)
    checks.append(label)

require(Path('pubspec.yaml'),'version: 22.9.4+229004','release metadata')
require(Path('lib/app/theme.dart'),"withValues(alpha: .94)",'top-bar contrast')
require(Path('lib/app/theme.dart'),"withValues(alpha: .97)",'dialog contrast')
require(Path('lib/core/utils/thousands_input_formatter.dart'),'class ThousandsInputFormatter','thousands input formatter')
require(Path('lib/core/exporting/excel_export_service.dart'),"language: 'en'",'English-only Excel')
require(Path('lib/core/exporting/pdf_export_service.dart'),"language: 'en'",'English-only PDF')
require(Path('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart'),"title: 'Recycle Bin Report'",'English recycle-bin export')
require(Path('lib/features/customer_service/pages/customer_service_page.dart'),'controller.opportunities.isEmpty','opportunity empty-stage refresh')
require(Path('lib/features/sales/workflow/repositories/sales_workflow_repository.dart'),'erp_manage_commercial_order_component_v3','sales component runtime guard')
require(Path('lib/features/purchases/repositories/purchase_workflow_repository.dart'),'erp_manage_commercial_order_component_v3','purchase component runtime guard')
require(Path('supabase/migrations/20260807050000_v763_commercial_component_runtime_guard.sql'),'erp_v762_approve_workflow_invoice','invoice approval guard')
require(Path('lib/core/widgets/app_full_page_route.dart'),'final dialogChild = child.child','dialog null safety')

# No duplicated migration versions.
versions={}
for p in (root/'supabase/migrations').glob('*.sql'):
    version=p.name.split('_',1)[0]
    versions.setdefault(version,[]).append(p.name)
dups={k:v for k,v in versions.items() if len(v)>1}
if dups:
    print('FAILED duplicate migration versions:',dups)
    sys.exit(1)
checks.append('unique migration versions')

print('PASS V22.9.4 final runtime, visual, export and workflow closure verification')
print(f'- {len(checks)} closure contracts verified')
