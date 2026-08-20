from pathlib import Path

from verification_text import contains_code

ROOT = Path(__file__).resolve().parents[1]
add = (ROOT / 'lib/features/maintenance/pages/add_maintenance_order_page.dart').read_text(encoding='utf-8')
details = (ROOT / 'lib/features/maintenance/pages/maintenance_order_details_dialog.dart').read_text(encoding='utf-8')

checks = [
    ('Maintenance invoice price validates thousands-aware values', 'final number = ThousandsInputFormatter.parse(value);' in add),
    ('Maintenance draft save parses formatted labor amount', 'laborCost: ThousandsInputFormatter.parse(_labor.text) ?? 0' in add),
    ('Maintenance draft save parses formatted invoice price', 'salePrice: ThousandsInputFormatter.parse(_price.text) ?? 0' in add),
    ('Maintenance line price parses formatted IQD amounts', 'unitPrice: ThousandsInputFormatter.parse(line.unitPrice.text) ?? 0' in add),
    ('Maintenance quantity parses grouping separators safely', 'ThousandsInputFormatter.parse(line.quantity.text)?.toInt() ?? 0' in add),
    ('Maintenance quantity validator remains integer-only', 'number != number.truncateToDouble()' in add),
    (
        'Draft detail identifies both historical and canonical draft stages',
        contains_code(
            details,
            """
            const <String>{
              'draft',
              'order_draft',
            }
            """,
        ),
    ),
    (
        'Persisted draft renders immediately before optional backend enrichment',
        contains_code(
            details,
            """
            if (_isOrderDraft) {
              _loading = false;
              unawaited(_loadDraftCoreLines());
            """,
        ),
    ),
    ('Persisted draft loads core lines without reconciliation dependency', 'final lines = await _repository.getOrderLines(_order.id);' in details),
    ('Draft line-load failure stays visible instead of blanking workspace', '_loadWarning = userFacingError(' in details and 'The maintenance draft was opened' in details),
    ('Post-draft workflow still uses authoritative snapshot', 'unawaited(_loadDetails());' in details and 'final snapshot = await _repository.getOrderSnapshot(_order.id);' in details),
    ('Reload routes drafts to core-line path', '_isOrderDraft ? _loadDraftCoreLines() : _loadDetails()' in details),
]

failed = False
for label, ok in checks:
    if ok:
        print(f'PASS: {label}')
    else:
        failed = True
        print(f'FAIL: {label}')

if failed:
    raise SystemExit(1)
print('R87.3 maintenance draft/IQD regression guard PASS')