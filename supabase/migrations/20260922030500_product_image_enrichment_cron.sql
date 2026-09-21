create extension if not exists pg_net with schema extensions;

create or replace function private.run_product_image_enrichment_cron()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job private.product_image_enrichment_jobs%rowtype;
  v_pending bigint;
  v_request_id bigint;
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

  select count(*)
    into v_pending
  from public.products p
  where p.store_id = v_job.store_id
    and p.is_available = true
    and p.image_url is null
    and p.image_enrichment_status is null;

  if v_pending = 0 then
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
      'batch_size', 12
    ),
    timeout_milliseconds := 55000
  )
  into v_request_id;

  return v_request_id;
end;
$$;

revoke all on function private.run_product_image_enrichment_cron()
from public, anon, authenticated;
