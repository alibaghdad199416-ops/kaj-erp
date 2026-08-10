from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks={
 'car card uses R44 bulk thumbnails without per-card RPC': "loadImages(" not in (ROOT/'lib/features/inventory/cars/widgets/car_card.dart').read_text(encoding='utf-8',errors='replace') and "thumbnailBytesFor(carId)" in (ROOT/'lib/features/inventory/cars/widgets/car_card.dart').read_text(encoding='utf-8',errors='replace'),
 'duplicate image load coalesced': "if (_loading.contains(carId)) return;" in (ROOT/'lib/features/inventory/cars/controllers/car_images_controller.dart').read_text(encoding='utf-8',errors='replace'),
 'r25 migration present': (ROOT/'supabase/migrations/20260808123000_r25_functional_runtime_closure.sql').exists(),
}
sql=(ROOT/'supabase/migrations/20260808123000_r25_functional_runtime_closure.sql').read_text(encoding='utf-8',errors='replace')
checks.update({
 'fifo cancellation alias fixed': 'remaining_quantity+fc.quantity' in sql and ' c record;' not in sql,
 'delivery refreshes canonical vehicle': 'erp_v732_refresh_car_state' in sql and 'erp_phase2_approve_sales_delivery' in sql,
 'sales invoice accepts post-delivery order': "not in ('draft','cancelled','canceled','reversed','deleted','void')" in sql,
 'sold vehicle maintenance source canonical': "document_type='invoice' and d.status='approved'" in sql,
 'cashbox ledger canonicalized': "jsonb_build_object('accountId',v_ledger,'account_id',v_ledger)" in sql,
 'cashbox duplicate ledger rejected': 'cashbox_ledger_account_already_bound' in sql,
})
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R25 failed: '+', '.join(failed))
print('PASS R25 functional closure')
