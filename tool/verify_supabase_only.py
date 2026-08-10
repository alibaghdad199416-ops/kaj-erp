#!/usr/bin/env python3
from __future__ import annotations
import json, re, sys
from pathlib import Path
from verification_text import contains_code

ROOT = Path(__file__).resolve().parents[1]
ALLOWED_BUSINESS_FEATURES = {
    'accounting', 'business_partners', 'customer_service', 'dashboard',
    'global_search', 'inventory', 'maintenance', 'notifications',
    'purchases', 'sales', 'settings',
}
INFRASTRUCTURE_FEATURES = {'auth', 'splash'}
errors: list[str] = []
notes: list[str] = []

def fail(message: str) -> None: errors.append(message)
def read(path: Path) -> str: return path.read_text(encoding='utf-8-sig', errors='replace')

# Web-only layout.
for name in ('android','ios','linux','macos','windows'):
    if (ROOT/name).exists(): fail(f'unused native platform remains: {name}')
for name in ('web/sqflite_sw.js','web/sqlite3.wasm'):
    if (ROOT/name).exists(): fail(f'local database artifact remains: {name}')

# Accepted feature boundary. Products are implemented as an Inventory subsection
# with their own canonical route, while authentication and splash are infrastructure.
feature_dirs = {p.name for p in (ROOT/'lib/features').iterdir() if p.is_dir()}
unexpected_features = feature_dirs - ALLOWED_BUSINESS_FEATURES - INFRASTRUCTURE_FEATURES
if unexpected_features:
    fail(f'unexpected top-level feature modules: {sorted(unexpected_features)}')
missing_features = ALLOWED_BUSINESS_FEATURES - feature_dirs
if missing_features:
    fail(f'accepted feature modules missing: {sorted(missing_features)}')

routes_text = read(ROOT/'lib/app/routes.dart') + '\n' + read(ROOT/'lib/app/route_names.dart')
for route in (
    '/governance', '/documents', '/business-intelligence', '/ai',
    '/predictions', '/hr', '/assets', '/projects', '/mobile',
    '/platform-builder', '/security', '/cloud-platform',
    '/production-hardening', '/integration', '/reservations',
):
    if route in routes_text:
        fail(f'removed route remains in routes.dart: {route}')
for route in (
    '/dashboard', '/global-search', '/notifications', '/products',
    '/inventory', '/maintenance', '/business-partners',
    '/customer-service', '/sales', '/purchases', '/accounting', '/settings',
):
    if route not in routes_text:
        fail(f'accepted route missing from routes.dart: {route}')

# Runtime boundary.
scan_files = [ROOT/'pubspec.yaml', ROOT/'pubspec.lock']
scan_files += list((ROOT/'lib').rglob('*.dart')) + list((ROOT/'web').rglob('*'))
scan_files += list((ROOT/'supabase/functions').rglob('*.ts')) + [ROOT/'package.json']
for p in scan_files:
    if not p.is_file(): continue
    text = read(p).lower()
    for token in (
        'sqflite','sqlite3.wasm','sqflite_sw.js',
        'package:firebase_core','package:firebase_auth','cloud_firestore',
        'firebase/database','firebase/firestore','firebase/auth','firebase-admin',
        "from('cloud_profiles')", ".eq('user_uid'", 'target_user_uid'
    ):
        if token in text: fail(f'forbidden runtime token {token!r} in {p.relative_to(ROOT)}')

# Browser config must contain public Supabase values only. Use the checked-in
# example during source-package/CI verification; local secrets stay untracked.
defines_path = ROOT/'dart_defines.json'
if not defines_path.is_file():
    defines_path = ROOT/'dart_defines.example.json'
defines = json.loads(read(defines_path))
allowed = {'SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_PUBLISHABLE_KEY'}
extra = set(defines)-allowed
if extra: fail(f'unexpected browser configuration keys: {sorted(extra)}')
key = str(defines.get('SUPABASE_PUBLISHABLE_KEY') or defines.get('SUPABASE_ANON_KEY') or '')
if not key: fail('Supabase publishable/anon key is missing')
if key.startswith('sb_secret_') or key.startswith('service_role'): fail('secret Supabase key found in browser config')

# Firebase is hosting only.
fb = json.loads(read(ROOT/'firebase.json'))
if set(fb) != {'hosting'}: fail(f'firebase.json must contain hosting only, found {sorted(fb)}')
if fb.get('hosting',{}).get('public') != 'build/web': fail('Firebase Hosting public directory must be build/web')
config = read(ROOT/'supabase/config.toml')
if not re.search(r'\[auth\.third_party\.firebase\]\s*\nenabled\s*=\s*false', config):
    fail('Supabase Firebase third-party auth must remain disabled')

# Resolve all local Dart imports and prove every lib file is reachable from main.
lib = ROOT/'lib'; dart_files = {p.resolve() for p in lib.rglob('*.dart')}
directive_re = re.compile(r"^\s*(?:import|export|part)\b[^;]+;", re.M)
uri_re = re.compile(r"['\"]([^'\"]+)['\"]")
def resolve(src: Path, uri: str):
    if uri.startswith('dart:'): return None
    if uri.startswith('package:') and not uri.startswith('package:quality_line_erp/'): return None
    target = lib/uri[len('package:quality_line_erp/'):] if uri.startswith('package:quality_line_erp/') else src.parent/uri
    return target.resolve()
edges: dict[Path,list[Path]] = {}
for src in dart_files:
    deps=[]
    source_text = read(src)
    uris = [
        uri
        for directive in directive_re.findall(source_text)
        for uri in uri_re.findall(directive)
    ]
    for uri in uris:
        target=resolve(src,uri)
        if target is None: continue
        if not target.exists(): fail(f'missing Dart import {uri} from {src.relative_to(ROOT)}')
        elif target in dart_files: deps.append(target)
    edges[src]=deps

# Keep the application import graph acyclic. Large route/page cycles made small
# UI changes invalidate dozens of modules and were a major source of fragile
# refactors. Kahn's algorithm reports any future cycle as a quality-gate error.
indegree = {path: 0 for path in dart_files}
for dependencies in edges.values():
    for dependency in dependencies:
        indegree[dependency] += 1
queue = [path for path, degree in indegree.items() if degree == 0]
visited_count = 0
while queue:
    current = queue.pop()
    visited_count += 1
    for dependency in edges[current]:
        indegree[dependency] -= 1
        if indegree[dependency] == 0:
            queue.append(dependency)
if visited_count != len(dart_files):
    cyclic = sorted(
        str(path.relative_to(ROOT))
        for path, degree in indegree.items()
        if degree > 0
    )
    fail('circular Dart import graph: ' + ', '.join(cyclic[:25]))

start=(lib/'main.dart').resolve(); seen=set(); stack=[start]
while stack:
    current=stack.pop()
    if current in seen: continue
    seen.add(current); stack.extend(edges.get(current,()))
unreachable=dart_files-seen
# A small, explicit set of unit-test support types is intentionally kept outside
# the production import graph. Every entry must be imported by a real Flutter test
# and is not shipped into the compiled web runtime.
allowed_non_runtime = {
    ROOT / line.strip()
    for line in read(ROOT/'tool/non_runtime_dart_allowlist.txt').splitlines()
    if line.strip() and not line.lstrip().startswith('#')
}
allowed_non_runtime = {p.resolve() for p in allowed_non_runtime}
unknown_unreachable = unreachable - allowed_non_runtime
stale_allowlist = allowed_non_runtime - unreachable
if unknown_unreachable:
    fail('unreachable Dart files not declared in allowlist: '+', '.join(
        str(p.relative_to(ROOT)) for p in sorted(unknown_unreachable)
    ))
if stale_allowlist:
    fail('stale non-runtime Dart allowlist entries: '+', '.join(
        str(p.relative_to(ROOT)) for p in sorted(stale_allowlist)
    ))

test_sources = '\n'.join(read(path) for path in (ROOT/'test').rglob('*.dart'))
for path in sorted(allowed_non_runtime):
    relative = path.relative_to(lib).as_posix()
    package_import = f'package:quality_line_erp/{relative}'
    if package_import not in test_sources:
        fail(
            'non-runtime allowlist entry is not imported by Flutter tests: '
            + str(path.relative_to(ROOT))
        )
notes.append(
    f'Dart graph: {len(seen)} reachable source files; '
    f'{len(unreachable)} explicitly test-only support files; no import cycles'
)

# All literal RPC calls must be defined by migrations.
rpcs=set(); funcs=set()
for p in lib.rglob('*.dart'):
    rpcs.update(re.findall(r"\.rpc\(\s*['\"]([A-Za-z0-9_]+)['\"]", read(p)))
for p in (ROOT/'supabase/migrations').glob('*.sql'):
    funcs.update(re.findall(r"create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?([A-Za-z0-9_]+)\s*\(", read(p), re.I))
missing=sorted(rpcs-funcs)
if missing: fail('RPC functions missing from migrations: '+', '.join(missing))
notes.append(f'RPC contract: {len(rpcs)} literal calls, all defined')

# A function may exist in an older migration but be removed by CASCADE when a
# retired table is dropped. Check the final function bodies used by Flutter and
# ensure none still depends on a table retired by the cleanup migration.
cleanup_path=ROOT/'supabase/migrations/20260728001200_accepted_module_cleanup.sql'
if cleanup_path.exists():
    cleanup_text=read(cleanup_path)
    drop_section=cleanup_text.split(
        '-- Drop dedicated retired tables only after their archive copies exist.',1
    )[-1].split('-- Replace the historical multi-module command router',1)[0]
    retired_tables=set(re.findall(r"'([a-z0-9_]+)'", drop_section, re.I))
    # A later accepted-module migration may intentionally re-create a previously
    # retired table under a new supported contract. Do not classify that table
    # as retired after its canonical re-introduction.
    migrations = sorted((ROOT/'supabase/migrations').glob('*.sql'))
    cleanup_index = migrations.index(cleanup_path)
    recreated_tables=set()
    for migration in migrations[cleanup_index + 1:]:
        recreated_tables.update(re.findall(
            r'create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-z0-9_]+)',
            read(migration), re.I,
        ))
    retired_tables -= recreated_tables
    final_function_bodies: dict[str,tuple[Path,str]]={}
    function_body_re=re.compile(
        r'create\s+(?:or\s+replace\s+)?function\s+(?:public\.)?'
        r'([a-zA-Z0-9_]+)\s*\([^;]*?\)\s*returns\b.*?\bas\s+\$\$(.*?)\$\$\s*;',
        re.I|re.S,
    )
    for migration in sorted((ROOT/'supabase/migrations').glob('*.sql')):
        for match in function_body_re.finditer(read(migration)):
            final_function_bodies[match.group(1)]=(migration,match.group(2).lower())
    for rpc in sorted(rpcs):
        definition=final_function_bodies.get(rpc)
        if definition is None: continue
        dependencies=[
            table for table in retired_tables
            if re.search(r'\b'+re.escape(table)+r'\b', definition[1])
        ]
        if dependencies:
            fail(
                f'active RPC {rpc} still depends on retired table(s) '
                f'{sorted(dependencies)} in {definition[0].name}'
            )

# Basic SQL delimiter sanity outside comments, strings, and function bodies.
# Dart syntax is validated by flutter analyze; interpolated strings make raw
# delimiter counting unreliable.
def structural_sql(path: Path) -> str:
    text=read(path)
    text=re.sub(r'--.*?$', '', text, flags=re.M)
    text=re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text=re.sub(r'\$\$.*?\$\$', '', text, flags=re.S)
    text=re.sub(r"'(?:''|[^'])*'", '', text)
    return text
for p in (ROOT/'supabase/migrations').glob('*.sql'):
    text=structural_sql(p)
    for a,b in [('(',')'),('[',']'),('{','}')]:
        if text.count(a) != text.count(b):
            fail(f'unbalanced {a}{b} count in {p.relative_to(ROOT)}')

# Ensure the final cloud-only repair is present.
latest=ROOT/'supabase/migrations/20260728000600_supabase_native_identity_and_car_reuse.sql'
if not latest.exists(): fail('final Supabase-native identity migration is missing')
else:
    latest_sql = read(latest).lower()
    for required in (
        'where not is_deleted',
        'p_user_id uuid',
        'drop table if exists public.cloud_profiles',
        'supabase_user_id_required',
    ):
        if required not in latest_sql:
            fail(f'final Supabase migration is missing contract: {required}')

# Accepted-module cleanup must preserve the Notification Center data store,
# retire removed routes, and provide a user-visible archive operation.
cleanup=ROOT/'supabase/migrations/20260728001200_accepted_module_cleanup.sql'
if not cleanup.exists(): fail('accepted-module cleanup migration is missing')
else:
    cleanup_sql=read(cleanup).lower()
    pre_router=cleanup_sql.split('-- replace the historical multi-module command router',1)[0]
    if "'erp_enterprise_notifications'" in pre_router:
        fail('accepted-module cleanup must not archive/drop the active notification store')
    for required in (
        'create schema if not exists qualityline_retired',
        'erp_archive_cloud_notification',
        'erp_cloud_global_search',
        "'/business-partners'",
        "'/customer-service'",
        "'/accounting'",
    ):
        if required not in cleanup_sql:
            fail(f'accepted-module cleanup is missing contract: {required}')

notification_page=read(ROOT/'lib/features/notifications/pages/notification_center_page.dart')
notification_repo=read(ROOT/'lib/features/notifications/repositories/notification_center_repository.dart')
for required in ('loadPersistentNotifications','markAllAsRead','archiveNotification'):
    if required not in notification_page + notification_repo:
        fail(f'Notification Center is missing persistent operation: {required}')

search_page=read(ROOT/'lib/features/global_search/pages/global_search_page.dart')
for required in ('_HighlightedText','result.title','result.subtitle'):
    if required not in search_page:
        fail(f'Global Search is missing match-highlighting contract: {required}')

# Focused contracts for the final commercial/UI repairs.
multi=ROOT/'supabase/migrations/20260728000700_multi_warehouse_commercial_documents.sql'
if not multi.exists(): fail('multi-warehouse commercial migration is missing')
else:
    multi_sql=read(multi).lower()
    for required in (
        'erp_create_cloud_sales_delivery_multi',
        'erp_create_cloud_purchase_receipt_multi',
        'erp_validate_commercial_warehouse_allocations',
        "'allocations'",
    ):
        if required not in multi_sql:
            fail(f'multi-warehouse migration is missing contract: {required}')

catalog=ROOT/'supabase/migrations/20260728000800_sales_catalog_stock_repair.sql'
if not catalog.exists(): fail('sales catalog/legacy stock repair migration is missing')
else:
    catalog_sql=read(catalog).lower()
    for required in (
        'repairedfromproductmaster',
        'reservedquantity',
        'warehousebalances',
        'erp_cloud_sales_order_catalog',
        'erp_approve_cloud_sales_order',
    ):
        if required not in catalog_sql:
            fail(f'sales catalog repair migration is missing contract: {required}')

product_update=ROOT/'supabase/migrations/20260728000900_product_update_relationships.sql'
if not product_update.exists(): fail('linked product update migration is missing')
else:
    product_update_sql=read(product_update).lower()
    for required in (
        'minimumquantity',
        'erp_sales_order_items_cloud',
        'erp_purchase_order_items_cloud',
        "o.status='draft'",
        'erp_inventory_refresh_product',
    ):
        if required not in product_update_sql:
            fail(f'linked product update migration is missing contract: {required}')

sales_repo=read(ROOT/'lib/features/sales/workflow/repositories/sales_workflow_repository.dart')
purchase_repo=read(ROOT/'lib/features/purchases/repositories/purchase_workflow_repository.dart')
for name,text in (('sales',sales_repo),('purchase',purchase_repo)):
    if not contains_code(text, "if (editing) 'p_order_id': orderId"):
        fail(f'{name} catalog must send p_order_id only in edit mode')

allocation_widget=ROOT/'lib/core/widgets/warehouse_allocation_dialog.dart'
if not allocation_widget.exists(): fail('warehouse allocation UI is missing')
else:
    allocation_text=read(allocation_widget)
    for required in ('warehouseBalances','اعتماد التوزيع','suggestedWarehouseId'):
        if required not in allocation_text:
            fail(f'warehouse allocation UI is missing contract: {required}')

car_card=read(ROOT/'lib/features/inventory/cars/widgets/car_card.dart')
for required in ('KajDesignTokens.softShadow','_ActionButton','Icons.delete_outline','car.chassis','costCurrency','saleCurrency'):
    if required not in car_card:
        fail(f'car card is missing required compact visual/detail contract: {required}')
for forbidden in ('car.vehicleType','car.carNumber','car.supplierName','car.warehouseId','imagePath','car.plateNumber'):
    if forbidden in car_card:
        fail(f'car card exposes removed field: {forbidden}')
product_card=read(ROOT/'lib/features/inventory/widgets/inventory_card.dart')
for required in ('KajDesignTokens.softShadow','_ActionButton','Icons.delete_outline','onEdit','Color(0xFF16A36A)'):
    if required not in product_card:
        fail(f'product card is missing required compact visual/edit contract: {required}')
for forbidden in ('item.sku','item.barcode','item.nameEn','item.taxRate'):
    if forbidden in product_card:
        fail(f'product card exposes removed field: {forbidden}')

pdf_service=read(ROOT/'lib/core/printing/enterprise_document_pdf_service.dart')
report_pdf=read(ROOT/'lib/features/settings/reports/services/report_export_service.dart')
pdf_support=read(ROOT/'lib/core/printing/pdf_text_support.dart')
commercial_safe = (
    'PdfTextSupport.canonicalPdfLanguage(language)' in pdf_service
    and "kIsWeb ? 'en'" in pdf_support
    and 'rethrow;' in pdf_support
)
report_safe = (
    "String get _exportLanguage => 'en'" in report_pdf
    or 'تم إيقاف التصدير لمنع ظهور رموز بدل الأحرف العربية' in report_pdf
)
if not commercial_safe:
    fail('commercial PDF must use browser-safe English or stop before corrupted Arabic output')
if not report_safe:
    fail('report PDF must use canonical English or stop before corrupted Arabic output')

# Ensure no embedded privileged credential literal exists.
secret_re=re.compile(r'(sb_secret_[A-Za-z0-9._-]{12,}|service_role_[A-Za-z0-9._-]{12,}|postgres(?:ql)?://[^\s:]+:[^\s@]+@)',re.I)
for p in ROOT.rglob('*'):
    if not p.is_file() or any(part in {'.git','build','.dart_tool','node_modules'} for part in p.parts): continue
    if p.suffix.lower() in {'.png','.jpg','.jpeg','.ico','.zip','.wasm'}: continue
    if secret_re.search(read(p)): fail(f'possible privileged credential literal in {p.relative_to(ROOT)}')

if errors:
    print('FAILED Supabase-only verification')
    for item in errors: print(f'  - {item}')
    sys.exit(1)
print('PASS Supabase-only structural verification')
for item in notes: print(f'  - {item}')
print(f'  - Executable tests: {len(list((ROOT/"test").rglob("*_test.dart")))}; support files: {len(list((ROOT/"test/support").rglob("*.dart")))}')
print(f'  - Migrations: {len(list((ROOT/"supabase/migrations").glob("*.sql")))}')
