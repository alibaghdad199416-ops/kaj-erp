from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = "supabase/migrations/20260816020000_r85_record_scope_search_reports_closure.sql"


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
    migration = require(
        MIGRATION,
        "erp_r85_customer_service_scope_guard",
        "erp_service_cases",
        "erp_partner_activities",
        "erp_list_cloud_reservations",
        "erp_r85_search_result_visible",
        "erp_r49_cloud_global_search",
        "erp_r84_record_visible",
        "erp_r85_current_creator_aliases",
        "erp_r85_report_default_resource",
        "erp_r85_report_section_resource",
        "erp_r85_filter_report_sections",
        "createdBy",
        "performedBy",
        "fail-closed",
        "erp_r9_cloud_contextual_report",
        "erp_r9_cloud_model_report",
        "erp_r9_cloud_customer_service_report",
        "as restrictive for select",
        "notify pgrst,'reload schema'",
    )
    assert "forbidden_label:" not in migration, "invalid SQL block label survived R85"

    for result_type, resource in (
        ("السيارات", "cars"),
        ("المنتجات", "inventory"),
        ("المخازن", "warehouses"),
        ("العملاء", "customers"),
        ("المجهزون", "suppliers"),
        ("أوامر البيع", "sales"),
        ("أوامر الشراء", "purchases"),
        ("الصيانة", "maintenance"),
        ("خدمة العملاء", "customer_service"),
        ("القيود المحاسبية", "accounting"),
        ("الدفعات", "installments"),
        ("الفرص التجارية", "customer_service"),
    ):
        assert f"v_type='{result_type}'" in migration or f"v_type in ('{result_type}'" in migration, (
            f"quick search type not scoped: {result_type}"
        )
        assert f"'{resource}'" in migration, f"resource missing from R85: {resource}"

    require(
        "supabase/migrations/20260816013000_r84_user_record_scope_atomic_profile_closure.sql",
        "erp_r84_record_scope_mode",
        "erp_r84_record_visible",
        "records.own",
        "records.all",
    )
    require(
        "lib/features/settings/reports/data/contextual_reports_repository.dart",
        "erp_r9_cloud_customer_service_report",
        "erp_r9_cloud_model_report",
        "erp_r9_cloud_contextual_report",
        "reports.contextual.view",
        "reports.financial_details.view",
    )

    print("PASS R85 secondary record-scope closure")
    print("  - Quick Search checks ownership before returning business results")
    print("  - opportunities, reservations, service cases and partner activities are scoped")
    print("  - contextual/model/customer-service report rows respect records.own")
    print("  - unknown own-scope report sections fail closed instead of leaking rows")


if __name__ == "__main__":
    main()
