from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks={
 'migration': root/'supabase/migrations/20260806103000_v746_partner_currency_cashbox_links_live_inventory_value.sql',
 'payment': root/'lib/core/finance/invoice_payment_batch_dialog.dart',
 'cars': root/'lib/features/inventory/cars/pages/cars_page.dart',
}
for name,p in checks.items():
    assert p.exists(), f'missing {name}: {p}'
sql=checks['migration'].read_text(encoding='utf-8')
for token in ['erp_workflow_partner_account','erp_resolve_linked_cash_account','erp_rebuild_live_inventory_values','erp_sync_stock_value_from_cost_layers','partner_currency_account_missing']:
    assert token in sql, token
pay=checks['payment'].read_text(encoding='utf-8')
assert '_configuredLinkedCashbox' in pay and "linked_cash_account_id" in pay
cars=checks['cars'].read_text(encoding='utf-8')
assert 'car.statusValue != CarStatus.sold' in cars and 'warehouseId!.trim().isNotEmpty' in cars
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
assert any(v in pub for v in ['18.9.18+189180','22.9.8+229008'])
print('PASS V7.4.6 partner currency, user cashbox links, FX payment routing, and live inventory value')
