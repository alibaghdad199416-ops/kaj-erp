BEGIN;

-- R75: safe runtime reconciliation. Preserve application data.
DROP POLICY IF EXISTS profiles_self_select ON public.profiles;
CREATE POLICY profiles_self_select ON public.profiles
  FOR SELECT TO authenticated
  USING ((id = (SELECT auth.uid())));

DROP POLICY IF EXISTS profiles_self_update ON public.profiles;
CREATE POLICY profiles_self_update ON public.profiles
  FOR UPDATE TO authenticated
  USING ((id = (SELECT auth.uid())))
  WITH CHECK ((id = (SELECT auth.uid())));

DROP POLICY IF EXISTS erp_user_ui_preferences_select_own ON public.erp_user_ui_preferences;
CREATE POLICY erp_user_ui_preferences_select_own ON public.erp_user_ui_preferences
  FOR SELECT TO authenticated
  USING ((user_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS erp_user_ui_preferences_insert_own ON public.erp_user_ui_preferences;
CREATE POLICY erp_user_ui_preferences_insert_own ON public.erp_user_ui_preferences
  FOR INSERT TO authenticated
  WITH CHECK ((user_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS erp_user_ui_preferences_update_own ON public.erp_user_ui_preferences;
CREATE POLICY erp_user_ui_preferences_update_own ON public.erp_user_ui_preferences
  FOR UPDATE TO authenticated
  USING ((user_id = (SELECT auth.uid())))
  WITH CHECK ((user_id = (SELECT auth.uid())));

DROP POLICY IF EXISTS erp_user_ui_preferences_delete_own ON public.erp_user_ui_preferences;
CREATE POLICY erp_user_ui_preferences_delete_own ON public.erp_user_ui_preferences
  FOR DELETE TO authenticated
  USING ((user_id = (SELECT auth.uid())));

DROP INDEX IF EXISTS public.erp_accounting_projects_company_updated_idx;
DROP INDEX IF EXISTS public.erp_car_images_company_updated_idx;
DROP INDEX IF EXISTS public.erp_car_warehouse_transfers_company_updated_idx;
DROP INDEX IF EXISTS public.erp_cars_updated_idx;
DROP INDEX IF EXISTS public.erp_cash_accounts_company_updated_idx;
DROP INDEX IF EXISTS public.erp_cash_transactions_company_updated_idx;
DROP INDEX IF EXISTS public.erp_cash_transactions_report_lookup_idx;
DROP INDEX IF EXISTS public.erp_cash_transfers_company_updated_idx;
DROP INDEX IF EXISTS public.erp_cost_centers_company_updated_idx;
DROP INDEX IF EXISTS public.erp_customers_updated_idx;
DROP INDEX IF EXISTS public.erp_expenses_company_updated_idx;
DROP INDEX IF EXISTS public.erp_fiscal_closings_company_updated_idx;
DROP INDEX IF EXISTS public.erp_fiscal_period_events_company_updated_idx;
DROP INDEX IF EXISTS public.erp_fiscal_periods_company_updated_idx;
DROP INDEX IF EXISTS public.erp_fiscal_years_company_updated_idx;
DROP INDEX IF EXISTS public.erp_installments_company_updated_idx;
DROP INDEX IF EXISTS public.erp_inventory_company_updated_idx;
DROP INDEX IF EXISTS public.erp_inventory_groups_company_updated_idx;
DROP INDEX IF EXISTS public.erp_inventory_movements_company_updated_idx;
DROP INDEX IF EXISTS public.erp_inventory_product_sales_company_updated_idx;
DROP INDEX IF EXISTS public.erp_inventory_receipts_company_updated_idx;
DROP INDEX IF EXISTS public.erp_journal_entries_company_updated_idx;
DROP INDEX IF EXISTS public.erp_journal_lines_company_updated_idx;
DROP INDEX IF EXISTS public.erp_product_images_company_updated_idx;
DROP INDEX IF EXISTS public.erp_purchase_items_company_updated_idx;
DROP INDEX IF EXISTS public.erp_purchases_company_updated_idx;
DROP INDEX IF EXISTS public.erp_recurring_journal_lines_company_updated_idx;
DROP INDEX IF EXISTS public.erp_recurring_journal_templates_company_updated_idx;
DROP INDEX IF EXISTS public.erp_sales_company_updated_idx;
DROP INDEX IF EXISTS public.erp_saved_report_filters_company_updated_idx;
DROP INDEX IF EXISTS public.erp_suppliers_updated_idx;
DROP INDEX IF EXISTS public.erp_warehouse_stock_company_updated_idx;
DROP INDEX IF EXISTS public.erp_warehouse_transfer_items_company_updated_idx;
DROP INDEX IF EXISTS public.erp_warehouse_transfers_company_updated_idx;
DROP INDEX IF EXISTS public.erp_warehouses_company_updated_idx;

COMMIT;
