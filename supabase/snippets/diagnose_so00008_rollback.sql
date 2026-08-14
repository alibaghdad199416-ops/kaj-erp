\set ON_ERROR_STOP on
begin;
select set_config(
  'request.jwt.claims',
  '{"sub":"5dfff075-0653-4918-bcce-293eea5e68d6","role":"authenticated"}',
  true
);
set local role authenticated;
select public.erp_r22_approve_sales_invoice(
  '11111111-1111-4111-8111-111111111111'::uuid,
  'a98b23dd-67b7-4f72-933c-1bee4f55ef05'::uuid
);
select jsonb_pretty(public.erp_r62_get_commercial_order_snapshot(
  '11111111-1111-4111-8111-111111111111'::uuid,
  'b0839af5-e93e-4ea5-b75a-0b7b61cd4946'::uuid,
  false
));
select jsonb_pretty(public.erp_r62_get_commercial_order_snapshot(
  '11111111-1111-4111-8111-111111111111'::uuid,
  'e51575dd-e0df-408e-96c2-d10fbc07fc21'::uuid,
  true
));
rollback;
