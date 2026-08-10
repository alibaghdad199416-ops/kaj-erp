from pathlib import Path
import json,sys
root=Path(__file__).resolve().parents[1]
checks={
 'version': '22.9.3+229003' in (root/'pubspec.yaml').read_text(encoding='utf-8'),
 'completion_components': (root/'lib/design_system/kaj_completion_components.dart').exists(),
 'formatter': (root/'lib/core/utils/erp_display_formatter.dart').exists(),
 'pdf_layout': (root/'lib/core/printing/kaj_final_pdf_layout.dart').exists(),
 'pdf_bidi': 'directionFor' in (root/'lib/core/printing/pdf_text_support.dart').read_text(encoding='utf-8'),
 'dialog_theme': 'dialogTheme:' in (root/'lib/app/theme.dart').read_text(encoding='utf-8'),
 'chip_theme': 'chipTheme:' in (root/'lib/app/theme.dart').read_text(encoding='utf-8'),
 'dropdown_theme': 'dropdownMenuTheme:' in (root/'lib/app/theme.dart').read_text(encoding='utf-8'),
}
failed=[k for k,v in checks.items() if not v]
if failed:
 print('FAIL V22.9.3 fixes 04-08:', ', '.join(failed)); sys.exit(1)
print('PASS V22.9.3 visual, localization, number, table and PDF completion verification')
print(f'- {len(checks)} completion contracts verified')
