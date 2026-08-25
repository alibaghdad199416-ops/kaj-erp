from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks={
 'version': ('pubspec.yaml','version: 19.5.0+195000'),
 'phase5 components': ('lib/design_system/kaj_phase5_components.dart','class KajCommercialHero'),
 'sales hero': ('lib/features/sales/pages/sales_page.dart','title: AppTranslation.translate(\'مركز المبيعات\')'),
 'purchase hero': ('lib/features/purchases/pages/purchases_page.dart','title: AppTranslation.translate(\'مركز المشتريات\')'),
}
failed=[]
for name,(file,marker) in checks.items():
    text=(root/file).read_text(encoding='utf-8')
    if marker not in text: failed.append(name)
if failed:
    print('FAIL V19.5:', ', '.join(failed)); sys.exit(1)
print('PASS V19.5 Phase 5 sales and purchasing luxury verification')
