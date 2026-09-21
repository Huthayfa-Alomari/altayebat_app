create table if not exists private.product_image_enrichment_jobs (
  store_id uuid primary key references public.stores(id) on delete cascade,
  token text,
  enabled boolean not null default false,
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

revoke all on private.product_image_enrichment_jobs from public, anon, authenticated;

create or replace function public.internal_validate_product_image_job_token(
  p_store_id uuid,
  p_token text
)
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from private.product_image_enrichment_jobs j
    where j.store_id = p_store_id
      and j.enabled = true
      and j.token is not null
      and j.token = p_token
  );
$$;

revoke all on function public.internal_validate_product_image_job_token(uuid,text)
from public, anon, authenticated;
grant execute on function public.internal_validate_product_image_job_token(uuid,text)
to service_role;
