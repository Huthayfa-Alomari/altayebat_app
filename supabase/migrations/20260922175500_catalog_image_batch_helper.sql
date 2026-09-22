create or replace function private.run_catalog_image_batch(
  p_store_id uuid,
  p_batch_size integer default 6
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token text;
  v_request_id bigint;
  v_batch integer;
begin
  select token into v_token
  from private.product_image_enrichment_jobs
  where store_id = p_store_id
    and token is not null
  limit 1;

  if v_token is null then
    raise exception 'No active image import token for store';
  end if;

  v_batch := greatest(1, least(coalesce(p_batch_size, 6), 8));

  select net.http_post(
    url := 'https://wfvuojrhxewogdnynytf.supabase.co/functions/v1/enrich-product-images',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-image-job-token', v_token
    ),
    body := jsonb_build_object(
      'store_id', p_store_id,
      'batch_size', v_batch,
      'mode', 'catalog_fallback'
    ),
    timeout_milliseconds := 55000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.run_catalog_image_batch(uuid,integer)
from public, anon, authenticated;
