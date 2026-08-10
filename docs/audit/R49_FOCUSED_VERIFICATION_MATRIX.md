# R49 Focused Final Verification Matrix

Status vocabulary:
- **VERIFIED**: an executable local gate/test was run on the final code state.
- **STATICALLY VERIFIED**: source/SQL/contracts were inspected and verified, but Flutter/browser/live integration is unavailable here.
- **EXTERNAL**: requires Flutter/browser or the linked live services in the user's environment.

| Module | Requirement / risk | Canonical path | Verification | Result | External? |
|---|---|---|---|---|---|
| CRM / Opportunities | Lifecycle, Expected Value, currency, read-back | Opportunity model/controller/repository + R49 lifecycle SQL | R49 gates + source/database verification | VERIFIED / STATIC runtime | Browser E2E |
| CRM ↔ Sales | One linked active order, reverse projection | Sales workflow repository + opportunity reconciliation | R49 gates | VERIFIED / STATIC runtime | Live E2E |
| Sales | Approval ≠ delivery ≠ invoice ≠ payment | R46/R48/R49 workflow contracts | R46 10/10, R48 12/12, R49 | VERIFIED | Live posting |
| Purchases | Approval ≠ receipt ≠ invoice ≠ payment | Purchase workflow repository + invoice SQL | R46/R48/R49 | VERIFIED | Live posting |
| Maintenance | Issue/consumption ≠ invoice; customer ledger required | Maintenance repository + R49 integrity SQL | R48/R49 | VERIFIED | Live posting |
| Accounting | Master-data accounts, text account codes, active/currency guards | Accounting repositories + invoice/account guard SQL | R22/R46/R49 + DB contracts | VERIFIED / STATIC runtime | Live GL sampling |
| Net Profit | Revenue − Expense from posted GL, not purchases-as-expense | R49 accounting profit wrappers | R49 gates | VERIFIED / STATIC runtime | Live KPI reconciliation |
| Inventory | Receipt/delivery/issue quantity boundaries | R46/R48 | R46/R48 | VERIFIED | Live movement sampling |
| Inventory Value | Product + car FIFO layers, per currency | R49 financial summary/report SQL | R49 gates + DB verification | VERIFIED / STATIC runtime | Live valuation reconciliation |
| Cars | Separate identity/reference, FIFO car valuation, thumbnails | car repositories + R44 + R49 | R44 9/9 + R49 | VERIFIED | Visual/browser |
| Products / spare parts | Warehouse/account/cost traceability | inventory repositories + R49 | R49 + structure | VERIFIED / STATIC runtime | Live E2E |
| Cashboxes / FX | Explicit currency, active state, linked-route guards | R42/R48/R49 cashbox/payment chain | R42/R48/R49 | VERIFIED | Live FX/payment |
| Receivables / Payables | No missing-currency → USD fallback | R49 financial subledger integrity SQL | R49 + DB verification | VERIFIED | Live legacy-data probe |
| Installments | Sale currency inherited; workflow-owned schedule | installment repo/controller + R49 SQL | R49 | VERIFIED | Live sale/payment |
| Users / Permissions | Granular scopes, tenant-bound scope management | permission catalog + R49 permission SQL | R9/R49 + DB verification | VERIFIED | Multi-user live test |
| Notifications | Per-user read/archive identity | notification repository + R49 SQL | R49 | VERIFIED | Multi-user live test |
| Warehouses | Active/tenant checks and protected inventory actions | inventory repository + R49 permission wrappers | R49 | VERIFIED | Live CRUD |
| Global Search | CRM included, server-side filters, currency-aware values | global search repo + R49 search SQL | R9/R49 | VERIFIED | Live result sampling |
| Reports | Period-aware, per-currency, GL profit, car+product valuation | reports repository + R49 SQL | R49 + DB verification | VERIFIED | Live report reconciliation |
| Dashboard | Per-currency KPIs, GL profit, car+product valuation | dashboard repository + R49 wrappers | R49 | VERIFIED | Live KPI reconciliation |
| Printing / Export | No fabricated journal/payment rows; bilingual paths | legacy PDF/report export services | R36-R41 + R49 | VERIFIED / STATIC runtime | Browser/PDF visual |
| Localization | Arabic/English catalog coverage | AppText/catalog/localization verifier | verify:localization + audit:final | VERIFIED static | RTL/LTR visual |
| Responsive UI | No known direct >=500px modal dimensions; reflow shell | AppResponsive/App full page route | R24/R49 + UI audit | VERIFIED static | Zoom 100% visual |
| Performance | R44 bulk thumbnails, no per-card image RPC; reduced duplicate loads | R44 + controllers/repositories | R43/R44/R49 | VERIFIED static | Network profile |
| Multi-user concurrency | stale-version rejection + backend idempotency | R49 permission/runtime SQL + invoice guard | R49 | VERIFIED static | Concurrent live users |
| Database reproducibility | Forward-only migrations, signatures/type boundaries | 249 migrations + deploy allowlist | verify:database/structure | VERIFIED | Fresh linked project push |
| Deployment | Correct Supabase/Firebase targets; no production push here | R49 deploy orchestrator | verify:delivery | VERIFIED config | Actual production deployment |
| Flutter compile/test/build | Analyzer/tests/web release | validate_r49_workspace.ps1 | CLI unavailable in this environment | EXTERNAL | Yes |
