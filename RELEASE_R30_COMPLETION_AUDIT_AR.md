# Quality Line ERP — R30 Completion Audit

R30 is the final hardening pass over R28/R29 acceptance work.

## Additional closures
- Removed Unix-epoch (1970) fallback from accounting statement rows.
- Removed Unix-epoch fallback from the common report export date formatter; invalid/missing dates render blank instead of a false historical date.
- Added an R30 installed-workspace validation script that runs format, the full R8→R30 workspace gates, Flutter analyzer, Flutter tests, and a fresh web build.
- Changed the default `deploy:production` command from the obsolete R24 deployment script to the R30 deployment script.
- The R30 production deploy verifies the authoritative Supabase migration history already applied to `fjiaxdorunedmltgqtty` and deliberately does not replay R23–R28 accounting migrations whose cloud migration timestamps differ from the original local filenames.
- Firebase Hosting remains the only Firebase responsibility and deploys to `kaj-erp` only after the complete validation/build succeeds.
- Advanced the web release/cache token to `r30-completion-audit-20260809`.

## Acceptance areas retained
- EBL USD / EBL IQD canonical ledger persistence and same-currency asset validation.
- Duplicate active cashbox ledger binding prevention.
- Commercial receipt/delivery/invoice/payment/movement drill-down.
- Product Edit / Details / History / Movement Log.
- Product Movement Log server RPC with Supplier→Warehouse, Warehouse→Warehouse, and Warehouse→Customer semantics, including user/reference/date/quantity.
- Product movement/history PDF + Excel export.
- Browser-safe PDF pipeline for purchase/sales, cash voucher, maintenance, warehouse transfer, accounting reports, and report customization paths.
- Recycle Bin Excel export.
- Accounting report filters for currency/date/branch/cost center.
- Text semantics for account codes (no accidental decimal-number formatting).
- English/Arabic localization gates and requested English terminology coverage.
- Responsive car/product action layout and overflow headroom.

## Environment limitation
This execution environment does not contain Flutter/Dart. `flutter analyze`, `flutter test`, and the final `flutter build web` must therefore run on the workstation. The R30 deployment script enforces those steps before Firebase deployment.
