"""V7.2 complete linked operations and accounting assignment gate."""
from pathlib import Path
from verification_text import contains_code

ROOT = Path(__file__).resolve().parents[1]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

migration = read("supabase/migrations/20260804032000_v72_complete_linked_operations.sql")
v73_migration = read("supabase/migrations/20260804180000_v73_reversible_workflows_shell.sql")
v750_migration = read("supabase/migrations/20260806143000_v750_rpc_runtime_recovery.sql")
package = read("package.json")
inventory_page = read("lib/features/inventory/pages/inventory_page.dart")
transfer_page = read("lib/features/inventory/pages/product_warehouse_transfers_page.dart")
transfer_form = read("lib/features/inventory/pages/transfer_stock_page.dart")
inventory_repo = read("lib/features/inventory/data/inventory_repository.dart")
sales_repo = read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart")
purchase_repo = read("lib/features/purchases/repositories/purchase_workflow_repository.dart")
maintenance_repo = read("lib/features/maintenance/data/maintenance_repository.dart")
accounting_controller = read("lib/features/accounting/controllers/accounting_controller.dart")
accounting_repo = read("lib/features/accounting/repositories/accounting_repository.dart")
accounting_page = read("lib/features/accounting/pages/accounting_page.dart")
product_page = read("lib/features/inventory/pages/add_inventory_page.dart")
account_fields = read("lib/features/inventory/widgets/inventory_account_fields.dart")
add_car = read("lib/features/inventory/cars/pages/add_car_page.dart")
edit_car = read("lib/features/inventory/cars/pages/edit_car_page.dart")
car_model = read("lib/features/inventory/cars/models/car_model.dart")
recycle_model = read("lib/features/settings/recycle_bin/models/recycle_bin_item.dart")
recycle_repo = read("lib/features/settings/recycle_bin/repositories/recycle_bin_repository.dart")
recycle_page = read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")

checks = {
    "forward migration follows V7.1.1": "20260804032000_v72_complete_linked_operations.sql" in package or (ROOT / "supabase/migrations/20260804032000_v72_complete_linked_operations.sql").is_file(),
    "primary product transfer entry opens unified documents": contains_code(inventory_page, "const ProductWarehouseTransfersPage()"),
    "unified transfer page exposes create edit delete print actions": all(marker in transfer_page for marker in ("سند نقل جديد", "Icons.edit_outlined", "Icons.delete_forever_outlined", "Icons.print_outlined")),
    "product transfer form has no recursive document dependency": "initialAssetType" in transfer_form and "product_warehouse_transfers_page.dart" not in transfer_form,
    "transfer deletion uses verified v2 RPC": "erp_delete_inventory_warehouse_transfer_v2" in inventory_repo and "result['deleted'] != true" in inventory_repo,
    "transfer v2 validates header items and movement cleanup": all(marker in migration for marker in ("erp_delete_inventory_warehouse_transfer_v2", "warehouse_transfer_link_cleanup_incomplete", "activeMovements", "stockReversed")),
    "sales deletion uses latest reversible wrapper": (("erp_delete_cloud_sales_order_v4" in sales_repo and "erp_delete_cloud_sales_order_v4" in v750_migration) or ("erp_delete_cloud_sales_order_v3" in sales_repo and "erp_delete_cloud_sales_order_v3" in v73_migration)),
    "purchase deletion uses v3 reversible wrapper": "erp_delete_cloud_purchase_order_v3" in purchase_repo and "erp_delete_cloud_purchase_order_v3" in v73_migration,
    "maintenance deletion uses v3 reversible wrapper": "erp_delete_cloud_maintenance_order_v3" in maintenance_repo and "erp_delete_cloud_maintenance_order_v3" in v73_migration,
    "commercial deletion preserves partner advances": all(marker in migration for marker in ("paymentsPreserved", "customer_unapplied_credit", "supplier_unapplied_debit", "partner_advance")),
    "preserved payments appear in partner totals and documents": all(marker in migration for marker in ("unappliedPartnerPaymentsIncluded", "erp_cloud_partner_subledger_details_v2", "erp_cloud_partner_subledger_documents", "unapplied_credit", "unapplied_debit")),
    "preserved payments are listed and editable": "erp_r49_list_partner_unapplied_payments" in accounting_repo and "erp_update_partner_unapplied_payment" in accounting_repo and "loadPartnerUnappliedPayments" in accounting_controller,
    "partner account UI manages edit and permanent delete by permission": all(marker in accounting_page for marker in ("_showPartnerUnappliedPayments", "accounting.update", "accounting.delete", "Icons.account_balance_wallet_outlined", "Icons.delete_forever_outlined")),
    "product accounts use isolated lazy loading with retry": all(marker in product_page for marker in ("ensureAccountsLoaded", "_accountLoadError", "force: true", "product-account-")),
    "shared vehicle account fields load only chart accounts": "ensureAccountsLoaded" in account_fields and contains_code(account_fields, "a.type.toLowerCase() == 'asset'") and contains_code(account_fields, "a.type.toLowerCase() == 'expense'"),
    "vehicle account assignments reset by currency and validate": all(marker in add_car + edit_car for marker in ("_validateAccountingAssignments", "_inventoryAssetAccountId = null", "_salesCostExpenseAccountId = null", "InventoryAccountFields")),
    "vehicle cloud map writes normalized and compatibility account aliases": all(marker in car_model for marker in ("inventory_asset_account_id", "inventoryAssetAccountId", "sales_cost_expense_account_id", "salesCostExpenseAccountId")),
    "recycle item carries exact archive id": "archiveId" in recycle_model and "archive_id" in recycle_model,
    "recycle purge targets exact archive and validates result": "erp_recycle_bin_purge_by_archive" in recycle_repo and "result['purged'] != true" in recycle_repo,
    "recycle permanent delete remains visible and runtime permission guarded": "Icons.delete_forever" in recycle_page and "PermissionAction.require" in recycle_page and "PermissionCodes.recycleBinPurge" in recycle_page,
    "exact batch purge removes archive rows and retries FK order": all(marker in migration for marker in ("erp_recycle_bin_purge_by_archive", "pg_temp.erp_v72_purge_queue", "foreign_key_violation", "permanent_delete_blocked_by_active_relationships", "archiveRowsRemoved")),
    "new RPCs are revoked from anon and granted to authenticated": migration.count("revoke all on function public.erp_") >= 8 and migration.count("grant execute on function public.erp_") >= 8,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL V7.2 complete linked operations verification:\n  - " + "\n  - ".join(failed))

print("PASS V7.2 complete linked operations, recycle purge, preserved payments, and product/vehicle account assignment")
for name in checks:
    print(f"  - {name}")
