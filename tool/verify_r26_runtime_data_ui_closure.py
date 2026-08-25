from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks={}
sql=(ROOT/"supabase/migrations/20260808160000_r26_runtime_data_ui_contract_closure.sql").read_text(encoding='utf-8')
checks["cash incoming ledger wins"]="nullif(p_account->>'account_id','')" in sql and "erp_r22_save_cloud_cash_account" in sql
checks["car images dedicated rpc"]="erp_r26_list_car_images_for_car" in sql and "erp_r26_list_car_images_for_car" in (ROOT/"lib/features/inventory/cars/data/car_images_repository.dart").read_text(encoding='utf-8')
checks["safe image notifier"]="_notifySafely" in (ROOT/"lib/features/inventory/cars/controllers/car_images_controller.dart").read_text(encoding='utf-8')
checks["car grid no 190px extent"]="mainAxisExtent: 190" not in (ROOT/"lib/features/inventory/cars/pages/cars_page.dart").read_text(encoding='utf-8')
checks["fresh web fallback token"]="v744-cashbox-fixes" not in (ROOT/"web/index.html").read_text(encoding='utf-8')
for k,v in checks.items(): print(("PASS" if v else "FAIL"),k)
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit("R26 failed: "+", ".join(failed))
print("PASS R26 runtime data/UI closure")
