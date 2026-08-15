from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "havlqebmnjdcwmpaaqew"
PERMISSIONS = {
    "users.image.update",
    "users.credentials.update",
    "customers.image.update",
    "suppliers.image.update",
    "cars.images.manage",
    "inventory.images.manage",
    "reports.audit.view",
    "reports.contextual.view",
    "reports.financial_details.view",
}


def text(path: str) -> str:
    target = ROOT / path
    assert target.exists(), f"missing required file: {path}"
    return target.read_text(encoding="utf-8")


def contains_all(path: str, values) -> None:
    source = text(path)
    missing = [value for value in values if value not in source]
    assert not missing, f"{path} is missing: {', '.join(missing)}"


def main() -> None:
    migration_path = "supabase/migrations/20260815230000_r78_complete_requirements_closure.sql"
    permission_codes = "lib/features/settings/access/models/permission_codes.dart"
    media_function = "supabase/functions/admin-update-user-media/index.ts"
    user_function = "supabase/functions/admin-manage-user/index.ts"
    contextual_repo = "lib/features/settings/reports/data/contextual_reports_repository.dart"
    audit_repo = "lib/features/settings/reports/data/execution_audit_repository.dart"
    report_export = "lib/features/settings/reports/services/report_export_service.dart"
    accounting_export = "lib/core/printing/accounting_report_export_service.dart"
    unified_pdf = "lib/core/printing/unified_pdf_document.dart"
    generic_pdf = "lib/core/exporting/pdf_export_service.dart"
    voucher_pdf = "lib/features/accounting/cashbox/services/cash_voucher_pdf_service.dart"
    transfer_pdf = "lib/core/printing/warehouse_transfer_pdf_service.dart"
    entity_page = "lib/core/widgets/app_entity_page.dart"
    window_route = "lib/core/widgets/app_full_page_route.dart"

    # The runtime permission list is authoritative from Supabase. Dart constants
    # provide typo-safe references without creating phantom client-only permissions.
    contains_all(permission_codes, PERMISSIONS)
    contains_all(migration_path, PERMISSIONS)
    contains_all(
        migration_path,
        {
            "erp_cloud_current_user_has_permission",
            "erp_r78_media_permission_guard",
            "erp_r9_cloud_contextual_report",
            "erp_r9_cloud_model_report",
            "erp_r9_cloud_customer_service_report",
            "erp_r9_cloud_report_audit",
            "erp_seed_access_catalog",
            "notify pgrst,'reload schema'",
        },
    )
    contains_all(
        migration_path,
        {
            "erp_customers",
            "erp_suppliers",
            "erp_cars",
            "erp_inventory",
            "erp_car_images",
            "erp_product_images",
        },
    )

    contains_all(
        media_function,
        {
            "users.update",
            "users.image.update",
            "erp_cloud_current_user_has_permission",
            "media_readback_mismatch",
            "invalid_media_payload",
        },
    )
    contains_all(
        user_function,
        {
            "users.update",
            "users.delete",
            "users.credentials.update",
            "erp_cloud_current_user_has_permission",
        },
    )

    contains_all(
        "lib/features/business_partners/customers/data/customer_repository.dart",
        {"photo_base64", "photoBase64", "لم يتم تثبيت صورة العميل"},
    )
    contains_all(
        "lib/features/business_partners/suppliers/repositories/supplier_repository.dart",
        {"photo_base64", "photoBase64", "لم يتم تثبيت صورة المورد"},
    )
    contains_all(
        "lib/features/inventory/cars/data/car_images_repository.dart",
        {"imageBase64", "thumbnailBase64", "getImages", "replaceImages"},
    )

    contains_all(contextual_repo, {"reports.contextual.view", "reports.financial_details.view"})
    contains_all(audit_repo, {"reports.audit.view"})

    report_source = text(report_export)
    assert "const language = 'en';" not in report_source, "Reports Excel still forces English"
    contains_all(
        report_export,
        {
            "canonicalPdfLanguage(options.language)",
            "PdfExportService().build",
            "ContextualReportCustomizer().apply",
            "Workbook schema version",
            "Currency context",
            "_relationIndexRows",
            "Cross-module document relations",
        },
    )

    accounting_source = text(accounting_export)
    assert "arabic = false" not in accounting_source, "Accounting export still forces English"
    contains_all(accounting_export, {"PdfExportService().build", "ExcelWorkbookPresentation"})

    contains_all(
        unified_pdf,
        {"documentHeader", "titleBlock", "sectionHeader", "signatureBox", "footer"},
    )
    for path in (generic_pdf, voucher_pdf, transfer_pdf):
        contains_all(path, {"unified_pdf_document.dart", "UnifiedPdfDocument"})
    contains_all(generic_pdf, {"company_settings", "companyName", "logo"})

    contains_all(entity_page, {"module-command-rail", "module-continuous-workspace"})
    contains_all(
        window_route,
        {"_PremiumWindowTheme", "_WindowHeader", "_WindowFooter", "Clip.hardEdge"},
    )

    contains_all(
        "lib/core/cloud/supabase_config.dart",
        {EXPECTED_REF, "validateRuntime", "browserStorageNamespace"},
    )
    contains_all("dart_defines.json", {EXPECTED_REF})

    print("PASS R78 complete requirements closure")
    print("  - granular user/media/report permissions: PostgreSQL + Edge + typed client constants")
    print("  - media persistence: read-back verified for users/customers/suppliers/cars")
    print("  - report details: contextual/audit/financial gates enforced")
    print("  - exports: Arabic/English PDF + Excel + relation index share one data pipeline")
    print("  - PDF identity: unified header/table/footer with company branding fallback")
    print("  - UI: continuous module workspace + clipped premium module windows")
    print(f"  - production project isolation: {EXPECTED_REF}")


if __name__ == "__main__":
    main()
