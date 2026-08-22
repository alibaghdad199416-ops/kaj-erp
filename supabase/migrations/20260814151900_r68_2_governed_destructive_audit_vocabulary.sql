begin;

alter table public.erp_audit_log
  drop constraint if exists erp_audit_log_operation_check;
alter table public.erp_audit_log
  add constraint erp_audit_log_operation_check check(operation=any(array[
    'INSERT','UPDATE','DELETE','RESTORE','LOGIN','LOGOUT','EXPORT','OTHER',
    'EMPTY_RECYCLE_BIN','CLEAR_NOTIFICATIONS',
    'DELETE_FINANCIAL_TRANSACTION_FAMILY'
  ]));

commit;
