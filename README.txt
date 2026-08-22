KAJ ERP R87.3 — Maintenance Draft + IQD Price regression hotfix

Fixes:
1) Reopening order_draft no longer depends on downstream snapshot/reconciliation; the persisted order renders immediately and core lines load independently.
2) Maintenance labor/invoice/line prices and quantities use ThousandsInputFormatter.parse, so IQD-sized values with grouping separators validate and persist correctly.

No database migration is included.
No Production/Hosted Supabase operation is included.

After merge run:
  python -B tool/verify_r87_3_maintenance_draft_iqd_regression.py
  npm run analyze
  flutter test test/features/maintenance/r87_3_maintenance_draft_iqd_regression_test.dart --dart-define-from-file=dart_defines.json

Then runtime-check both entry paths:
- Maintenance module -> create IQD draft -> save -> reopen.
- Opportunity -> linked Maintenance draft -> IQD price -> save -> reopen from Maintenance.
