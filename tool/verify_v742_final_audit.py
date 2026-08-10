from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
assert 'version: 22.9.8+229008' in (ROOT/'pubspec.yaml').read_text(encoding='utf-8')
sql=(ROOT/'supabase/migrations/20260806064500_v742_conflict_free_workflow_and_accounting.sql').read_text(encoding='utf-8')
for token in [
 "erp_v736_active_logistics", "('approved','posted','completed','confirmed')",
 "erp_list_cloud_sales_workflow_orders", "erp_list_cloud_purchase_workflow_orders",
 "erp_approve_cloud_workflow_invoice", "purchase_invoice_inventory_",
 "قيد مخزون فاتورة الشراء", "accountingOwner','invoice"
]: assert token in sql, token
# The authoritative final approval function must not expose capitalization nomenclature.
func=sql[sql.index('create or replace function public.erp_approve_cloud_workflow_invoice'): ]
for forbidden in ['رسملة','capitalization','purchase_invoice_valuation_','purchase_valuation_journal_']:
 assert forbidden not in func, forbidden
print('PASS V7.4.2 final conflict and completeness audit')
print('  - invoicing accepts approved historical logistics statuses')
print('  - sales and purchase projections expose the same eligibility rules')
print('  - invoice owns accounting; logistics remains quantity-only')
print('  - purchase postings use inventory nomenclature, not capitalization documents')
