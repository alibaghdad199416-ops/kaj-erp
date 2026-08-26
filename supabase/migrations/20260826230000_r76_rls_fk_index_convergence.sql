BEGIN;

-- R76: split ALL admin policies so SELECT does not overlap member SELECT,
-- and add the remaining verified foreign-key support indexes.
DROP POLICY IF EXISTS branches_admin_insert ON public.branches;
DROP POLICY IF EXISTS branches_admin_update ON public.branches;
DROP POLICY IF EXISTS branches_admin_delete ON public.branches;
DROP POLICY IF EXISTS branches_admin_write ON public.branches;
CREATE POLICY branches_admin_insert ON public.branches FOR INSERT TO authenticated WITH CHECK (is_company_admin(company_id));
CREATE POLICY branches_admin_update ON public.branches FOR UPDATE TO authenticated USING (is_company_admin(company_id)) WITH CHECK (is_company_admin(company_id));
CREATE POLICY branches_admin_delete ON public.branches FOR DELETE TO authenticated USING (is_company_admin(company_id));

DROP POLICY IF EXISTS exchange_rates_admin_insert ON public.exchange_rates;
DROP POLICY IF EXISTS exchange_rates_admin_update ON public.exchange_rates;
DROP POLICY IF EXISTS exchange_rates_admin_delete ON public.exchange_rates;
DROP POLICY IF EXISTS exchange_rates_admin_write ON public.exchange_rates;
CREATE POLICY exchange_rates_admin_insert ON public.exchange_rates FOR INSERT TO authenticated WITH CHECK (is_company_admin(company_id));
CREATE POLICY exchange_rates_admin_update ON public.exchange_rates FOR UPDATE TO authenticated USING (is_company_admin(company_id)) WITH CHECK (is_company_admin(company_id));
CREATE POLICY exchange_rates_admin_delete ON public.exchange_rates FOR DELETE TO authenticated USING (is_company_admin(company_id));

CREATE INDEX IF NOT EXISTS company_memberships_user_id_idx ON public.company_memberships (user_id);
CREATE INDEX IF NOT EXISTS erp_asset_depreciation_entries_asset_id_idx ON public.erp_asset_depreciation_entries (asset_id);
CREATE INDEX IF NOT EXISTS erp_maintenance_material_issue_lines_issue_id_idx ON public.erp_maintenance_material_issue_lines (issue_id);
CREATE INDEX IF NOT EXISTS erp_maintenance_material_issue_lines_maintenance_order_id_idx ON public.erp_maintenance_material_issue_lines (maintenance_order_id);
CREATE INDEX IF NOT EXISTS erp_maintenance_material_issues_maintenance_order_id_idx ON public.erp_maintenance_material_issues (maintenance_order_id);
CREATE INDEX IF NOT EXISTS erp_role_permission_grants_permission_code_idx ON public.erp_role_permission_grants (permission_code);
CREATE INDEX IF NOT EXISTS erp_role_record_scopes_role_id_idx ON public.erp_role_record_scopes (role_id);
CREATE INDEX IF NOT EXISTS role_permissions_permission_code_idx ON public.role_permissions (permission_code);

COMMIT;
