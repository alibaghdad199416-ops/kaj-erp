from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    'version': ('pubspec.yaml', 'version: 21.2.0+212000'),
    'release token': ('lib/core/release/app_release_info.dart', 'v2120-phase03-inventory-luxury-localization-20260807'),
    'inventory design system': ('lib/design_system/kaj_inventory_components.dart', 'class KajInventoryActionBar'),
    'inventory metric': ('lib/design_system/kaj_inventory_components.dart', 'class KajInventoryMetricPill'),
    'vehicle premium card': ('lib/features/inventory/cars/widgets/car_card.dart', 'KajDesignTokens.softShadow'),
    'product premium card': ('lib/features/inventory/widgets/inventory_card.dart', 'KajDesignTokens.softShadow'),
    'vehicle english localization': ('lib/features/inventory/cars/pages/cars_page.dart', "'Vehicle management'"),
    'product english localization': ('lib/features/inventory/pages/inventory_page.dart', "'Product management'"),
    'warehouse premium shell': ('lib/features/inventory/pages/warehouse_management_page.dart', 'KajInventoryActionBar('),
    'transfer premium shell': ('lib/features/inventory/pages/product_warehouse_transfers_page.dart', 'KajInventoryActionBar('),
}
missing=[]
for name,(rel,needle) in checks.items():
    text=(ROOT/rel).read_text(encoding='utf-8')
    if needle not in text:
        missing.append(f'{name}: {rel} missing {needle!r}')
if missing:
    print('FAIL V21.2 Phase 3 inventory luxury verification')
    for item in missing: print(' -', item)
    raise SystemExit(1)
print('PASS V21.2 Phase 3 inventory luxury verification')
print(f'- {len(checks)} inventory design, localization and release contracts checked')
