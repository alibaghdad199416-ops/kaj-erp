CREATE OR REPLACE FUNCTION public.erp_list_cloud_sales_workflow_orders(p_company_id uuid) RETURNS setof jsonb LANGUAGE SQL SECURITY DEFINER SET search_path=public AS 
