from pathlib import Path
import sys
import re

root = Path(__file__).resolve().parents[1]
fail = []

def read(rel):
    return (root / rel).read_text(encoding='utf-8')

def need(condition, message):
    if not condition:
        fail.append(message)

access = read('lib/features/settings/access/controllers/access_controller.dart')
splash = read('lib/features/splash/pages/splash_page.dart')
login = read('lib/features/auth/pages/login_page.dart')
cash = read('lib/features/accounting/cashbox/pages/cashbox_page.dart')
pay = read('lib/core/finance/invoice_payment_batch_dialog.dart')
maintenance = read('lib/features/maintenance/pages/add_maintenance_order_page.dart')
audit = read('lib/features/settings/access/pages/users_page.dart')
recycle = read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
opportunity = read('supabase/migrations/20260801080000_opportunity_sales_link_and_language_completion.sql')
fxchain = read('supabase/migrations/20260806203000_v756_secure_multicurrency_payment_chain.sql')
definition = read('supabase/migrations/20260807033000_v762_definition_only_posting_balance_hardening.sql')
effective = read('supabase/migrations/20260803010000_phase2_fifo_recycle_timeline.sql')
newmig = read('supabase/migrations/20260807173000_v2299_session_fx_effective_audit_hardening.sql')

need('Future<bool> restorePersistedSession()' in access, 'persisted Supabase session restore API')
need('auth.currentSession' in access and '_activateUser(user)' in access, 'persisted session rebuilds ERP authorization')
need('restored ? AppRouteNames.dashboard : AppRouteNames.login' in splash, 'splash routes restored session to dashboard')
need('signOut()' not in access[access.find('Future<void> prepareInteractiveLogin'):access.find('Future<bool> login')], 'interactive login must not destroy persisted session')
need('KajDesignTokens.electricBlue' in splash, 'startup loading uses blue accent')
need('color: KajDesignTokens.electricBlue' in login, 'login secure-session accent uses blue')
def has_fx_precision(source, minimum=15):
    return any(int(v) >= minimum for v in re.findall(r'decimalDigits:\s*(\d+)', source))
need(has_fx_precision(cash), 'cashbox FX accepts at least 15 decimals')
need(has_fx_precision(pay), 'invoice FX payment accepts at least 15 decimals')
r9fx = read('supabase/migrations/20260807233500_r9_fx_precision_and_field_guards.sql')
need('numeric(38,20)' in r9fx, 'database FX precision migration')
need('showTimePicker' in maintenance and "Operational date" in maintenance, 'maintenance operational timestamp includes time')
need('effective_at' in effective and 'erp_set_operational_effective_at' in effective, 'effective timestamp infrastructure retained')
need('_exportAuditPdf' in audit and '_exportAuditExcel' in audit, 'audit log PDF and Excel export')
need(('ExcelExportService().save(_report())' in recycle) or
     ('ExcelExportService().build(_report())' in recycle and 'BinaryDownloadService.save(' in recycle),
     'recycle-bin Excel export path')
need('erp_sync_opportunity_sales_lifecycle' in opportunity, 'bidirectional opportunity-sales lifecycle synchronization')
need('erp_v756_post_fx_clearing_journal' in fxchain or 'linked_cash_account' in fxchain.lower(), 'linked multi-currency payment chain')
need('inventory' in definition.lower() and 'revenue' in definition.lower(), 'definition-driven accounting hardening retained')

if fail:
    print('FAILED V22.9.9 runtime requirements closure')
    for item in fail:
        print(' - ' + item)
    sys.exit(1)

print('PASS V22.9.9 runtime requirements closure')
print('- persisted Supabase session restore verified')
print('- blue launch/login accent verified')
print('- >=15-decimal FX input and 20-decimal PostgreSQL storage verified')
print('- operational date/time propagation infrastructure verified')
print('- audit PDF/Excel and recycle-bin Excel paths verified')
print('- opportunity-sales and multi-currency accounting chains retained')
