from pathlib import Path
import re,sys,json
ROOT=Path(__file__).resolve().parents[1]
checks={}

def txt(rel): return (ROOT/rel).read_text(encoding='utf-8')
checks['R35 cloud command client']=any(x in txt('lib/core/cloud/cloud_feature_command.dart') for x in ('erp_r35_cloud_command','erp_r37_cloud_command')) and 'erp_r28_cloud_command' not in txt('lib/core/cloud/cloud_feature_command.dart')
checks['R35 cloud command migration']='erp_r35_cloud_command' in txt('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql')
checks['canonical maintenance create client']=any(x in txt('lib/features/maintenance/data/maintenance_repository.dart') for x in ('erp_r35_create_cloud_maintenance_order','erp_r37_create_cloud_maintenance_order','erp_r39_create_cloud_maintenance_order','erp_r49_create_cloud_maintenance_order','erp_r56_create_cloud_maintenance_order'))
checks['canonical maintenance sold invoice source']='erp_sales_order_items_cloud' in txt('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql') and "document_type='invoice'" in txt('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql')
checks['opportunity workflow trigger']='trg_r35_sync_opportunity_workflow' in txt('supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql')
inventory_stage4 = txt('lib/design_system/kaj_inventory_stage4_components.dart')
checks['inventory loading responsive']='constraints.maxHeight' in inventory_stage4 and re.search(r'\.clamp\(\s*24\.0,\s*natural,?\s*\)', inventory_stage4) is not None
checks['no automatic detached scrollbar']='return Scrollbar(' not in txt('lib/core/widgets/app_scroll_behavior.dart')
pdf_web=txt('lib/core/exporting/pdf_print_service_web.dart')
checks['web pdf direct download']=(
    'html.AnchorElement' in pdf_web and
    '..download = safeFileName' in pdf_web and
    'html.window.open(' not in pdf_web
)
pdf_support=txt('lib/core/printing/pdf_text_support.dart')
checks['web fonts are bundled without AssetManifest/CDN']=(
    'assets/fonts/NotoNaskhArabic-Regular.ttf' in pdf_support and
    'assets/fonts/NotoNaskhArabic-Bold.ttf' in pdf_support and
    'if (kIsWeb)' not in pdf_support and
    'pw.Font.helvetica()' not in pdf_support
)
checks['product details resilient']='Editing the product itself must remain available' in txt('lib/features/inventory/pages/inventory_page.dart')
checks['asset history canonical movement log']='erp_r28_inventory_movement_log' in txt('lib/features/inventory/asset_history/repositories/asset_history_repository.dart')
checks['asset history English Excel/PDF']='language: \'en\'' in txt('lib/features/inventory/asset_history/pages/asset_history_page.dart') and "label: 'Performed by'" in txt('lib/features/inventory/asset_history/pages/asset_history_page.dart')
checks['opportunity exports']='Commercial Opportunities' in txt('lib/features/customer_service/pages/customer_service_page.dart') and '_exportOpportunitiesExcel' in txt('lib/features/customer_service/pages/customer_service_page.dart') and '_exportOpportunitiesPdf' in txt('lib/features/customer_service/pages/customer_service_page.dart')
checks['workflow cards localized']="String t(String arText, String enText)" in txt('lib/core/widgets/commercial_workflow_order_card.dart') and "'Purchase Order'" in txt('lib/core/widgets/commercial_workflow_order_card.dart')
checks['details hide raw transport maps']=all(x in txt('lib/features/sales/workflow/pages/order_details_dialog.dart') for x in ('rawData','recordMeta','invoiceRawData'))
checks['R35 metadata']=any(token in txt('web/version.json') for token in ('r35-runtime-functional-closure','r36-ui-export-acceptance','r37-full-functional-presentation-closure','r38-final-functional-acceptance','r39-canonical-acceptance','r40-language-runtime-acceptance','r41-export-language-canonical-closure','r42-production-cashbox-guard-closure','r43-performance-functional-closure','r47-production-runtime-dependency-closure','r49-'))
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed:
 print('R35 failed:',', '.join(failed)); sys.exit(1)
print(f'PASS R35 runtime functional closure — {len(checks)} gates')
