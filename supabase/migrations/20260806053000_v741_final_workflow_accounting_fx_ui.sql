-- Quality Line ERP 18.9.11 / V7.4.1
-- Final workflow compatibility, definition-accounting, FX settlement and UI metadata.
begin;

-- Normalize historical logistics statuses so older approved deliveries/receipts
-- can continue to invoicing without recreating warehouse movements.
update public.erp_commercial_workflow_documents
set status='approved', updated_at=now()
where document_type in ('delivery','receipt','maintenance_issue')
  and lower(coalesce(status,'')) in ('posted','completed','confirmed')
  and not is_deleted;

-- Mark active workflow documents with concise accounting ownership metadata.
update public.erp_commercial_workflow_documents
set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
  'accountingOwner','invoice',
  'logisticsQuantityOnly',document_type in ('delivery','receipt','maintenance_issue'),
  'compactReference',left(regexp_replace(coalesce(document_number,''),'[^A-Za-z0-9]','','g'),7)
), updated_at=now()
where document_type in ('delivery','receipt','maintenance_issue','invoice')
  and not is_deleted;

-- Existing V7.4.0 posting functions remain authoritative: item/vehicle/service
-- definition accounts own inventory, cost and revenue routing; invoices and
-- payments own journals; logistics owns quantity only. FX payments preserve
-- source cashbox, bridge cashbox, rate, source amount and invoice amount.

commit;
