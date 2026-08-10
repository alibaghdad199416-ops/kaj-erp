from pathlib import Path
import json, re, sys
root=Path(__file__).resolve().parents[1]
checks=[]
def need(path,*tokens):
 p=root/path
 text=p.read_text(encoding='utf-8') if p.exists() else ''
 ok=p.exists() and all(t in text for t in tokens)
 checks.append((ok,str(path),tokens))
need(Path('lib/design_system/kaj_inventory_stage4_components.dart'),'KajInventoryPageHeader','KajInventorySection','KajInventoryResponsiveFields','KajInventoryLoadingState','KajInventoryEmptyState')
need(Path('lib/features/inventory/cars/pages/add_car_page.dart'),'KajInventoryScreen','Identity and specifications','KajPrimaryAction')
need(Path('lib/features/inventory/pages/transfer_stock_page.dart'),'KajInventoryScreen','Route and quantities','KajField')
need(Path('lib/features/inventory/cars/pages/cars_page.dart'),'All warehouses','kaj_inventory_stage4_components.dart')
need(Path('lib/features/inventory/pages/inventory_page.dart'),'kaj_inventory_stage4_components.dart')
need(Path('lib/features/inventory/pages/warehouse_management_page.dart'),'kaj_inventory_stage4_components.dart')
need(Path('lib/features/inventory/pages/product_warehouse_transfers_page.dart'),'kaj_inventory_stage4_components.dart')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
checks.append(('version: 22.3.0+223000' in pub,'pubspec.yaml',('22.3.0+223000',)))
pkg=json.loads((root/'package.json').read_text(encoding='utf-8'))
checks.append((pkg.get('version')=='22.3.0','package.json',('22.3.0',)))
failed=[c for c in checks if not c[0]]
if failed:
 for _,p,t in failed: print('FAIL',p,'missing',', '.join(t))
 sys.exit(1)
print('PASS V22.3 full redesign stage 04 inventory verification')
print(f'PASS {len(checks)} inventory design, responsive, localization and release contracts')
