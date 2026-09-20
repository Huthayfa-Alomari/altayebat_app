create or replace function private.is_valid_gtin(p_value text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v text := btrim(coalesce(p_value,''));
  v_len integer;
  v_sum integer := 0;
  v_i integer;
  v_digit integer;
  v_check integer;
  v_expected integer;
begin
  if v !~ '^[0-9]+$' then return false; end if;
  v_len := length(v);
  if v_len not in (8,12,13,14) then return false; end if;

  v_check := substring(v from v_len for 1)::integer;
  for v_i in 1..(v_len-1) loop
    v_digit := substring(v from v_i for 1)::integer;
    -- GTIN weighting is calculated from the right: 3,1,3,1...
    if ((v_len - v_i) % 2) = 1 then
      v_sum := v_sum + (v_digit * 3);
    else
      v_sum := v_sum + v_digit;
    end if;
  end loop;
  v_expected := (10 - (v_sum % 10)) % 10;
  return v_check = v_expected;
end;
$$;

revoke all on function private.is_valid_gtin(text) from public, anon, authenticated;

create or replace function public.admin_import_product_barcodes(
  p_store_id uuid,
  p_rows jsonb,
  p_dry_run boolean default true
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
  v_row_no integer := 0;
  v_total integer := 0;
  v_valid integer := 0;
  v_updated integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_results jsonb := '[]'::jsonb;
  v_product_id uuid;
  v_product_name text;
  v_match_count integer;
  v_sku text;
  v_barcode text;
  v_raw_product_id text;
  v_seen text[] := array[]::text[];
  v_duplicate_name text;
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'ROWS_MUST_BE_ARRAY' using errcode='22023';
  end if;

  v_total := jsonb_array_length(p_rows);
  if v_total < 1 then
    return jsonb_build_object(
      'dry_run',p_dry_run,'total',0,'valid',0,'updated',0,
      'errors','[]'::jsonb,'results','[]'::jsonb
    );
  end if;
  if v_total > 1000 then
    raise exception 'TOO_MANY_ROWS' using errcode='22023';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    v_row_no := v_row_no + 1;
    v_product_id := null;
    v_product_name := null;
    v_match_count := 0;
    v_raw_product_id := nullif(btrim(v_row->>'product_id'),'');
    v_sku := nullif(btrim(v_row->>'sku'),'');
    v_barcode := nullif(btrim(v_row->>'barcode'),'');

    if v_barcode is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row',v_row_no,'reason','EMPTY_BARCODE','sku',v_sku
      ));
      continue;
    end if;

    if not private.is_valid_gtin(v_barcode) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row',v_row_no,'reason','INVALID_GTIN','barcode',v_barcode,'sku',v_sku
      ));
      continue;
    end if;

    if v_barcode = any(v_seen) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row',v_row_no,'reason','DUPLICATE_IN_FILE','barcode',v_barcode,'sku',v_sku
      ));
      continue;
    end if;
    v_seen := array_append(v_seen,v_barcode);

    if v_raw_product_id is not null then
      begin
        v_product_id := v_raw_product_id::uuid;
      exception when invalid_text_representation then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'row',v_row_no,'reason','INVALID_PRODUCT_ID','product_id',v_raw_product_id,'barcode',v_barcode
        ));
        continue;
      end;

      select p.name into v_product_name
      from public.products p
      where p.store_id=p_store_id and p.id=v_product_id;

      if not found then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'row',v_row_no,'reason','PRODUCT_NOT_FOUND','product_id',v_raw_product_id,'barcode',v_barcode
        ));
        continue;
      end if;
    elsif v_sku is not null then
      select count(*), min(p.id), min(p.name)
        into v_match_count,v_product_id,v_product_name
      from public.products p
      where p.store_id=p_store_id and p.sku=v_sku;

      if v_match_count = 0 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'row',v_row_no,'reason','SKU_NOT_FOUND','sku',v_sku,'barcode',v_barcode
        ));
        continue;
      elsif v_match_count > 1 then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object(
          'row',v_row_no,'reason','AMBIGUOUS_SKU','sku',v_sku,'barcode',v_barcode
        ));
        continue;
      end if;
    else
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row',v_row_no,'reason','PRODUCT_REFERENCE_REQUIRED','barcode',v_barcode
      ));
      continue;
    end if;

    select p.name into v_duplicate_name
    from public.products p
    where p.store_id=p_store_id
      and p.barcode=v_barcode
      and p.id<>v_product_id
    limit 1;

    if found then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object(
        'row',v_row_no,'reason','BARCODE_ALREADY_USED','barcode',v_barcode,
        'product_id',v_product_id,'product_name',v_product_name,
        'existing_product_name',v_duplicate_name
      ));
      continue;
    end if;

    v_valid := v_valid + 1;
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'row',v_row_no,'status',case when p_dry_run then 'VALID' else 'UPDATED' end,
      'product_id',v_product_id,'product_name',v_product_name,'sku',v_sku,'barcode',v_barcode
    ));

    if not p_dry_run then
      update public.products
      set barcode=v_barcode, updated_at=now()
      where store_id=p_store_id and id=v_product_id;
      v_updated := v_updated + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'dry_run',p_dry_run,
    'total',v_total,
    'valid',v_valid,
    'updated',v_updated,
    'errors',v_errors,
    'results',v_results
  );
end;
$$;

revoke all on function public.admin_import_product_barcodes(uuid,jsonb,boolean) from public,anon;
grant execute on function public.admin_import_product_barcodes(uuid,jsonb,boolean) to authenticated;

