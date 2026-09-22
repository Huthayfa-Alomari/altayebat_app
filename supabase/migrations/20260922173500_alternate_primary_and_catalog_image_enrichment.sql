create or replace function private.run_product_image_enrichment_cron()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.product_image_enrichment_jobs%rowtype;
  v_pending_missing bigint;
  v_pending_secondary bigint;
  v_pending_refresh bigint;
  v_request_id bigint;
  v_mode text;
  v_batch_size integer;
  v_minute integer;
begin
  select *
    into v_job
  from private.product_image_enrichment_jobs
  where enabled = true
    and token is not null
  order by updated_at
  limit 1;

  if not found then
    return null;
  end if;

  update public.products p
  set image_secondary_status = null
  where p.store_id = v_job.store_id
    and p.image_secondary_status in ('rate_limited','error')
    and p.image_secondary_checked_at < now() - interval '20 hours';

  select count(*)
    into v_pending_missing
  from public.products p
  where p.store_id = v_job.store_id
    and p.is_available = true
    and p.image_url is null
    and p.image_enrichment_status is null;

  select count(*)
    into v_pending_secondary
  from public.products p
  where p.store_id = v_job.store_id
    and p.is_available = true
    and p.image_url is null
    and p.image_enrichment_status = 'not_found'
    and p.image_secondary_status is null;

  select count(*)
    into v_pending_refresh
  from public.products p
  where p.store_id = v_job.store_id
    and p.is_available = true
    and p.image_url is not null
    and p.image_source in (
      'open-food-facts-network',
      'open-food-facts',
      'open-beauty-facts',
      'open-pet-food-facts',
      'open-products-facts'
    )
    and p.image_match_method = 'exact_gtin';

  v_minute := extract(minute from clock_timestamp())::integer;

  if v_pending_missing > 0 and v_pending_secondary > 0 then
    if mod(v_minute, 2) = 0 then
      v_mode := 'fill_missing';
      v_batch_size := 12;
    else
      v_mode := 'catalog_fallback';
      v_batch_size := 6;
    end if;
  elsif v_pending_missing > 0 then
    v_mode := 'fill_missing';
    v_batch_size := 12;
  elsif v_pending_secondary > 0 then
    v_mode := 'catalog_fallback';
    v_batch_size := 6;
  elsif v_pending_refresh > 0 then
    v_mode := 'refresh_existing';
    v_batch_size := 8;
  else
    update private.product_image_enrichment_jobs
    set enabled = false,
        token = null,
        completed_at = now(),
        updated_at = now()
    where store_id = v_job.store_id;

    perform cron.unschedule('altayebat-product-image-enrichment');
    return null;
  end if;

  select net.http_post(
    url := 'https://wfvuojrhxewogdnynytf.supabase.co/functions/v1/enrich-product-images',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-image-job-token', v_job.token
    ),
    body := jsonb_build_object(
      'store_id', v_job.store_id,
      'batch_size', v_batch_size,
      'mode', v_mode
    ),
    timeout_milliseconds := 55000
  )
  into v_request_id;

  update private.product_image_enrichment_jobs
  set updated_at = now()
  where store_id = v_job.store_id;

  return v_request_id;
end;
$$;

revoke all on function private.run_product_image_enrichment_cron()
from public, anon, authenticated;
