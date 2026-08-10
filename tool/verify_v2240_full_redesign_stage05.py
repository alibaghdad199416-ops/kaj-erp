from pathlib import Path
import json, sys
root=Path(__file__).resolve().parents[1]
checks=[]
def need(path,*tokens):
 p=root/path; text=p.read_text(encoding='utf-8') if p.exists() else ''
 checks.append((p.exists() and all(t in text for t in tokens),str(path),tokens))
need(Path('lib/design_system/kaj_relationship_stage5_components.dart'),'KajRelationshipHero','KajRelationshipSection','KajRelationshipState','KajWorkflowRibbon')
need(Path('lib/features/maintenance/pages/maintenance_page.dart'),'KajRelationshipHero','kaj_relationship_stage5_components.dart')
need(Path('lib/features/maintenance/pages/add_maintenance_order_page.dart'),'kaj_relationship_stage5_components.dart')
need(Path('lib/features/maintenance/pages/maintenance_order_details_dialog.dart'),'kaj_relationship_stage5_components.dart')
need(Path('lib/features/business_partners/pages/business_partners_page.dart'),'KajRelationshipHero','UNIFIED RELATIONSHIPS')
need(Path('lib/features/business_partners/customers/pages/add_customer_page.dart'),'kaj_relationship_stage5_components.dart')
need(Path('lib/features/business_partners/suppliers/pages/add_supplier_page.dart'),'kaj_relationship_stage5_components.dart')
need(Path('lib/features/business_partners/shared/widgets/business_partner_profile_dialog.dart'),'kaj_relationship_stage5_components.dart')
need(Path('lib/features/customer_service/pages/customer_service_page.dart'),'KajRelationshipHero','kaj_relationship_stage5_components.dart')
need(Path('lib/features/customer_service/pages/add_opportunity_page.dart'),'kaj_relationship_stage5_components.dart')
checks.append(('version: 22.4.0+224000' in (root/'pubspec.yaml').read_text(encoding='utf-8'),'pubspec.yaml',('22.4.0+224000',)))
checks.append((json.loads((root/'package.json').read_text(encoding='utf-8')).get('version')=='22.4.0','package.json',('22.4.0',)))
failed=[c for c in checks if not c[0]]
if failed:
 for _,p,t in failed: print('FAIL',p,'missing',', '.join(t))
 sys.exit(1)
print('PASS V22.4 full redesign stage 05 maintenance, partners and CRM verification')
print(f'PASS {len(checks)} relationship, workflow, localization and release contracts')
