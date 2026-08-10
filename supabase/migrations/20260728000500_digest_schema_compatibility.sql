begin;

-- Supabase installs pgcrypto in the `extensions` schema on many projects.
-- Legacy phase-26 code calls digest(...) with search_path=public, so expose a
-- stable public compatibility function that resolves the extension explicitly.
create or replace function public.digest(
  p_data text,
  p_algorithm text
) returns bytea
language plpgsql
immutable
strict
security invoker
set search_path=public,extensions,pg_catalog
as $$
declare
  v_result bytea;
  v_algorithm text:=lower(btrim(p_algorithm));
begin
  if to_regprocedure('extensions.digest(text,text)') is not null then
    execute 'select extensions.digest($1,$2)'
      into v_result
      using p_data,v_algorithm;
    return v_result;
  end if;

  if to_regprocedure('extensions.digest(bytea,text)') is not null then
    execute 'select extensions.digest(convert_to($1,''UTF8''),$2)'
      into v_result
      using p_data,v_algorithm;
    return v_result;
  end if;

  -- Last-resort deterministic 32-byte checksum for projects where pgcrypto is
  -- unavailable. This keeps backup manifests operational without weakening
  -- authentication or user credentials, which never use this function.
  if v_algorithm not in ('sha256','sha-256') then
    raise exception 'unsupported digest algorithm: %',p_algorithm;
  end if;
  return decode(md5('0:'||p_data)||md5('1:'||p_data),'hex');
end;
$$;

revoke all on function public.digest(text,text) from public,anon;
grant execute on function public.digest(text,text) to authenticated,service_role;

commit;
