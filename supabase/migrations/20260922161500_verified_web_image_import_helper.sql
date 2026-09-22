create or replace function private.import_product_image_candidate(
  p_store_id uuid,
  p_product_id uuid,
  p_image_url text,
  p_source text default 'manual-web',
  p_external_name text default null
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_request_id bigint;
begin
  select token into v_token
  from private.product_image_enrichment_jobs
  where store_id = p_store_id
    and token is not null
  limit 1;

  if v_token is null then
    raise exception 'No active image import token for store';
  end if;

  select net.http_post(
    url := 'https://wfvuojrhxewogdnynytf.supabase.co/functions/v1/enrich-product-images',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-image-job-token', v_token
    ),
    body := jsonb_build_object(
      'store_id', p_store_id,
      'mode', 'manual_candidate',
      'product_id', p_product_id,
      'image_url', p_image_url,
      'source', p_source,
      'external_name', p_external_name
    ),
    timeout_milliseconds := 55000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.import_product_image_candidate(uuid,uuid,text,text,text)
from public, anon, authenticated;
