from pathlib import Path

required = {
    'lib/design_system/kaj_phase4_components.dart': [
        'class KajPartnerHero',
        'class KajPartnerCardShell',
        'class KajPartnerMetric',
        'KajBrandMotif',
    ],
    'lib/features/business_partners/pages/business_partners_page.dart': [
        'KajPartnerHero',
        'CustomersPage()',
        'SuppliersPage()',
    ],
    'lib/features/business_partners/customers/widgets/customer_card.dart': [
        'KajPartnerCardShell',
    ],
    'lib/features/business_partners/suppliers/widgets/supplier_card.dart': [
        'KajPartnerCardShell',
    ],
    'pubspec.yaml': ['version: 19.4.0+194000'],
}

for file_name, needles in required.items():
    path = Path(file_name)
    if not path.exists():
        raise SystemExit(f'FAIL missing {file_name}')
    text = path.read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'FAIL {needle!r} missing from {file_name}')

print('PASS V19.4 Phase 4 business-partner luxury verification')
