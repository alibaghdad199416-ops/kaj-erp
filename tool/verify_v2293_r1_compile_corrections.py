from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
checks = {
    'single dialogTheme': (root/'lib/app/theme.dart').read_text(encoding='utf-8').count('dialogTheme:') == 1,
    'single snackBarTheme': (root/'lib/app/theme.dart').read_text(encoding='utf-8').count('snackBarTheme:') == 1,
    'single chipTheme': (root/'lib/app/theme.dart').read_text(encoding='utf-8').count('chipTheme:') == 1,
    'maintenance diagnostics signature': re.search(r"WorkflowOperationException\.fromPostgrest\(\s*'maintenance_payment'", (root/'lib/features/maintenance/data/maintenance_repository.dart').read_text(encoding='utf-8')) is not None,
    'maintenance label fallback list': "const <String>['مسودة الأمر', 'Order draft']" in (root/'lib/features/maintenance/models/maintenance_order_model.dart').read_text(encoding='utf-8'),
    'nullable resale callback guarded': 'onPressed: () => onResell?.call(),' in (root/'lib/features/sales/widgets/sale_card.dart').read_text(encoding='utf-8'),
    'final pdf layout connected': 'final primary = _finalLayoutInk;' in (root/'lib/core/printing/enterprise_document_pdf_service.dart').read_text(encoding='utf-8'),
}
failed=[name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL V22.9.3 R1 compile corrections: ' + ', '.join(failed))
print('PASS V22.9.3 R1 compile corrections')
print(f'- {len(checks)} compile contracts verified')
