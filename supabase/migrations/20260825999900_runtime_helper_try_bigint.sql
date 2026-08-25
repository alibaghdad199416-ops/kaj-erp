begin;

-- Small typed conversion helper used by the runtime-repair migration.
-- Keep conversion failures non-fatal for nullable version metadata.
create or replace function public.erp_try_bigint(p_value text,p_default bigint default 0)
returns bigint
language plpgsql
immutable
as $$
begin
  return coalesce(nullif(btrim(p_value), '')::bigint,p_default);
exception when invalid_text_representation or numeric_value_out_of_range then
  return p_default;
end;
$$;

commit;
