from pathlib import Path
m=Path('supabase/migrations/20260807000000_v759_no_capitalization_balance_integrity.sql').read_text(encoding='utf-8')
assert 'erp_v759_normal_balance' in m
assert 'erp_v759_accounting_integrity_audit' in m
assert "account_type in ('liability','equity','revenue')" in m
assert "code in ('1391','1392')" in m
assert 'جسر تحويل مشتريات متعدد العملات' in m
print('PASS V7.5.9 no operational capitalization and debit/credit/balance integrity')
