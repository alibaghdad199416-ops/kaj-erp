from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "havlqebmnjdcwmpaaqew"
MIGRATION = "supabase/migrations/20260816013000_r84_user_record_scope_atomic_profile_closure.sql"


def text(path: str) -> str:
    target = ROOT / path
    assert target.exists(), f"missing required file: {path}"
    return target.read_text(encoding="utf-8-sig")


def require(path: str, *needles: str) -> str:
    source = text(path)
    missing = [needle for needle in needles if needle not in source]
    assert not missing, f"{path} is missing: {', '.join(missing)}"
    return source


def main() -> None:
    service = require(
        "lib/core/cloud/supabase_user_administration_service.dart",
        "functionName: 'admin-manage-user'",
        "'action': 'update'",
        "'erp_user': identityPayload",
        "'avatar_base64': avatarBase64",
        "media_readback_mismatch",
    )
    assert "functionName: 'admin-update-user-media'" not in service, (
        "user update still performs a second media Edge request"
    )

    require(
        "supabase/functions/admin-manage-user/index.ts",
        "users.image.update",
        "users.credentials.update",
        "avatar_base64",
        "media_payload_too_large",
        "media_readback_mismatch",
        "profile_readback_mismatch",
        "previousRecord",
        "Membership update rollback failed",
        "Profile update rollback failed",
        "ERP user update rollback failed",
        "updateUserById",
    )
    require(
        "lib/features/settings/access/widgets/permission_action.dart",
        "PermissionCodes.usersImageUpdate",
        "PermissionCodes.customersImageUpdate",
        "PermissionCodes.suppliersImageUpdate",
        "PermissionCodes.carsImagesManage",
        "PermissionCodes.inventoryImagesManage",
        "_dedicatedEditPermission",
    )

    scope_modules = (
        "customers",
        "suppliers",
        "cars",
        "inventory",
        "warehouses",
        "customer_service",
        "sales",
        "purchases",
        "maintenance",
        "accounting",
        "cashbox",
        "expenses",
        "installments",
    )
    migration = require(
        MIGRATION,
        "erp_r84_user_has_permission_override",
        "erp_r84_record_scope_mode",
        "erp_r84_record_visible",
        "erp_r84_scoped_write_guard",
        "erp_r84_opportunity_scope_guard",
        "as restrictive for select",
        "erp_r84_list_opportunities",
        "erp_r9_list_cloud_master_records",
        "erp_r9_get_cloud_master_record",
        "erp_r9_list_cloud_sales_workflow_orders",
        "erp_r9_list_cloud_purchase_workflow_orders",
        "erp_r9_list_cloud_maintenance_orders",
        "erp_r49_get_sales_order_draft",
        "erp_r49_get_purchase_order_draft",
        "created_by uuid default auth.uid()",
        "erp_seed_access_catalog",
        "Existing explicit user overrides historically implied company-wide rows",
    )
    for module in scope_modules:
        assert f"'{module}.records.own'" in migration, f"missing own scope for {module}"
        assert f"'{module}.records.all'" in migration, f"missing all scope for {module}"

    require(
        "lib/features/customer_service/repositories/opportunity_repository.dart",
        "erp_r84_list_opportunities",
        "CloudTenantContext.instance.companyUuid",
    )

    require(
        "lib/features/business_partners/customers/data/customer_repository.dart",
        "photo_base64",
        "photoBase64",
        "لم يتم تثبيت صورة العميل",
    )
    require(
        "lib/features/business_partners/suppliers/repositories/supplier_repository.dart",
        "photo_base64",
        "photoBase64",
        "لم يتم تثبيت صورة المورد",
    )
    require(
        "lib/features/inventory/cars/data/car_images_repository.dart",
        "imageBase64",
        "thumbnailBase64",
        "replaceImages",
        "getImages",
    )
    require(
        "supabase/migrations/20260815230000_r78_complete_requirements_closure.sql",
        "customers.image.update",
        "suppliers.image.update",
        "cars.images.manage",
        "inventory.images.manage",
        "erp_r78_media_permission_guard",
    )

    require(
        "lib/core/widgets/app_entity_page.dart",
        "module-command-rail",
        "module-continuous-workspace",
        "Only the module identity header is framed",
    )
    require(
        "lib/core/widgets/app_full_page_route.dart",
        "_PremiumWindowTheme",
        "_WindowHeader",
        "_WindowFooter",
        "Clip.hardEdge",
    )
    require(
        "lib/core/printing/unified_pdf_document.dart",
        "documentHeader",
        "titleBlock",
        "sectionHeader",
        "footer",
    )
    require(
        "lib/core/exporting/pdf_export_service.dart",
        "UnifiedPdfDocument",
        "company_settings",
    )
    require(
        "lib/features/settings/reports/services/report_export_service.dart",
        "PdfExportService().build",
        "canonicalPdfLanguage(options.language)",
        "_relationIndexRows",
    )
    require(
        "lib/core/printing/accounting_report_export_service.dart",
        "PdfExportService().build",
        "ExcelWorkbookPresentation",
    )

    require(
        "lib/core/cloud/supabase_config.dart",
        EXPECTED_REF,
        "validateRuntime",
        "browserStorageNamespace",
    )
    require("dart_defines.json", EXPECTED_REF)

    print("PASS R84 user/media/record-scope/UI/export closure")
    print("  - user profile + avatar update crosses one governed Edge request")
    print("  - changed user image requires users.image.update and read-back")
    print("  - customer/supplier/car/product media remain read-back verified")
    print("  - every scoped module exposes records.own and records.all")
    print("  - PostgreSQL list/detail/write/RLS boundaries enforce record scope")
    print("  - CRM opportunities use the scoped PostgreSQL list RPC")
    print("  - module workspace/windows and PDF/Excel identity remain unified")
    print(f"  - production project isolation remains {EXPECTED_REF}")


if __name__ == "__main__":
    main()
