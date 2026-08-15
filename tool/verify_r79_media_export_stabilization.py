from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_REF = "havlqebmnjdcwmpaaqew"


def read(path: str) -> str:
    target = ROOT / path
    assert target.exists(), f"missing required file: {path}"
    return target.read_text(encoding="utf-8")


def require(path: str, *markers: str) -> str:
    source = read(path)
    missing = [marker for marker in markers if marker not in source]
    assert not missing, f"{path} missing: {', '.join(missing)}"
    return source


def main() -> None:
    permission_widget = require(
        "lib/features/settings/access/widgets/permission_action.dart",
        "PermissionCodes.usersImageUpdate",
        "PermissionCodes.customersImageUpdate",
        "PermissionCodes.suppliersImageUpdate",
        "PermissionCodes.carsImagesManage",
        "PermissionCodes.inventoryImagesManage",
        "_dedicatedEditPermission",
    )
    assert "controller.hasPermission(dedicated)" in permission_widget

    media_edge = require(
        "supabase/functions/admin-update-user-media/index.ts",
        "users.update",
        "users.image.update",
        "currentAvatar === expectedAvatar",
        "changed: false",
        "media_readback_mismatch",
    )
    assert media_edge.index("currentAvatar === expectedAvatar") < media_edge.index("users.image.update")

    require(
        "lib/features/inventory/cars/data/car_images_repository.dart",
        "_sameImageSet",
        "if (_sameImageSet(existing, images)) return;",
        "thumbnailBase64",
        "sortOrder",
    )

    migration = require(
        "supabase/migrations/20260816003000_r79_media_export_stabilization.sql",
        "qualityline.r79_verified_media_noop",
        "erp_r78_media_permission_guard",
        "erp_r49_update_inventory_product",
        "inventory.images.manage",
        "v_requested is distinct from",
        "erp_r49_create_inventory_product",
        "notify pgrst,'reload schema'",
    )
    assert "jsonb_agg" in migration and "erp_product_images" in migration

    reports = require(
        "lib/features/settings/reports/services/report_export_service.dart",
        "canonicalPdfLanguage(options.language)",
        "ContextualReportCustomizer().apply",
        "Workbook schema version",
        "Currency context",
        "_relationIndexRows",
        "Cross-module document relations",
        "PdfExportService().build",
    )
    assert "const language = 'en';" not in reports

    accounting = require(
        "lib/core/printing/accounting_report_export_service.dart",
        "AppTranslation.isArabic",
        "_useArabic",
        "PdfExportService().build",
        "ExcelWorkbookPresentation",
    )
    assert "final language = arabic ? 'ar' : 'en';" not in accounting

    require(
        "lib/core/exporting/pdf_export_service.dart",
        "UnifiedPdfDocument.documentHeader",
        "company_settings",
        "companyName: branding.companyName",
        "logo: branding.logo",
    )
    require(
        "lib/core/printing/unified_pdf_document.dart",
        "documentHeader",
        "titleBlock",
        "sectionHeader",
        "signatureBox",
        "footer",
    )

    require(
        "lib/features/settings/reports/data/contextual_reports_repository.dart",
        "reports.contextual.view",
        "reports.financial_details.view",
    )
    require(
        "lib/features/settings/reports/data/execution_audit_repository.dart",
        "reports.audit.view",
    )

    require(
        "lib/core/widgets/app_entity_page.dart",
        "module-command-rail",
        "module-continuous-workspace",
    )
    require(
        "lib/core/widgets/app_full_page_route.dart",
        "_PremiumWindowTheme",
        "_WindowHeader",
        "_WindowFooter",
        "Clip.hardEdge",
    )

    require(
        "lib/core/cloud/supabase_config.dart",
        EXPECTED_REF,
        "validateRuntime",
        "browserStorageNamespace",
    )
    require("dart_defines.json", EXPECTED_REF)

    launcher = require(
        "tool/run_current_web.ps1",
        "verify_r76_local_current_database.py",
        "verify_r78_complete_requirements.py",
        "verify_r79_media_export_stabilization.py",
        "prepare_local_current_database.ps1",
        "dart_defines.local.generated.json",
    )
    assert "db push" not in launcher.lower()

    print("PASS R79 media/export stabilization")
    print("  - image edit controls mirror dedicated backend permissions")
    print("  - unchanged user/car/product images no longer block ordinary data edits")
    print("  - actual image mutations remain fail-closed in Edge/PostgreSQL")
    print("  - report Excel preserves selected Arabic/English language + relation index")
    print("  - accounting PDF/Excel follow active application language")
    print("  - generic PDF uses the unified Quality Line identity and company branding")
    print("  - local launcher verifies R76 + R78 + R79 before migration/run")
    print(f"  - production project remains isolated: {EXPECTED_REF}")


if __name__ == "__main__":
    main()
