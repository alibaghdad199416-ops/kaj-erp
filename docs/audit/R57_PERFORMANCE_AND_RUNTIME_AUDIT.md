# R57 Performance and Runtime Audit

Baseline: `5f478d1c4257f763a19a34d8a32e4c5e5ad8a827`

## Query and refresh boundaries

- Accounting header totals are returned by one tenant-scoped RPC. Cash is
  aggregated by currency from active cash accounts and every posted cash-in,
  cash-out, payment, receipt, expense, and transfer direction.
- Commercial quantity reconciliation is returned by one bounded aggregate RPC
  per opened order. It does not issue per-line or per-warehouse requests.
- Accounting header invalidation is coalesced while a request is active and is
  driven by `AppDataChangeBus` events from accounting, cashbox, expenses,
  purchases, and sales.
- Settings sections are lazy-created on first selection and cached thereafter;
  inactive sections no longer initiate their controllers or initial requests.

## UI density and rendering

- Duplicate root hero surfaces were removed from Settings, Users, Accounting,
  and Recycle Bin. Existing canonical page toolbars remain the single root
  presentation surface.
- Quantity reconciliation uses compact rows and status chips inside existing
  order and maintenance details rather than another page hero.
- R44 thumbnail behavior and image loading code were not changed.

## Runtime evidence

- Focused account-identifier and export tests: PASS.
- Flutter analyzer with fatal infos/warnings: PASS.
- R57 source/contract verifier: PASS.
- Fresh database replay: BLOCKED before database startup because Docker Desktop
  was not running (`dockerDesktopLinuxEngine` pipe unavailable). No linked or
  remote database command was used.
- Hosted authenticated browser and browser console: EXTERNAL/UNVERIFIED in this
  local run; no Production mutation was attempted.

## Authenticated request graph and budgets

The duplicate-request trace identified four ownership boundaries. Preference
setters owned persistence but did not remember the last successful remote
snapshot. `CarsController` converted every concurrent caller into a second
query. Master-data repositories shared a singleton transport but not an active
request. Local mutation events also returned to the cars and maintenance
controllers after those controllers had already reconciled their mutations.

After closure, the request graph and budgets are:

- `UI event -> AppPreferencesController -> local store -> preferences upsert`:
  zero remote writes for an equal snapshot and exactly one serialized write for
  each distinct snapshot. The snapshot key is user-scoped, so an account switch
  cannot reuse another user's suppression state.
- `CarsPage/controller callers -> CarsController -> cars RPC`: one RPC for
  concurrent ordinary loads; zero additional RPCs for a page reopen inside the
  20-second freshness window; and at most one follow-up when a forced refresh
  arrives during the active request.
- `Inventory/lookup repositories -> CloudMasterDataService -> master-list RPC`:
  one RPC per company/table while that request is active. Results are not kept
  in a new global stale cache; later independent reads remain authoritative.
- `maintenance callers -> MaintenanceController -> orders RPC`: one active RPC
  plus at most one forced follow-up. A controller-owned local mutation event is
  not fetched twice, while `cloud-realtime` and cross-module events still force
  a fresh reconciliation.

Realtime freshness remains event-driven. Local event suppression is limited to
operations that the same controller has already reloaded; external realtime
events are not classified as local echoes. No migration or production
configuration was added for this performance closure, and the migration count
remains 263.
