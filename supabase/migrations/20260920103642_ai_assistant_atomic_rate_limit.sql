
create or replace function public.begin_ai_basket_request(
  p_store_id uuid,
  p_customer_id uuid,
  p_prompt text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_minute_count integer;
  v_hour_count integer;
begin
  if p_store_id is null or p_customer_id is null then
    raise exception 'INVALID_AI_REQUEST' using errcode = '22023';
  end if;

  if p_prompt is null or char_length(btrim(p_prompt)) < 3 or char_length(p_prompt) > 600 then
    raise exception 'INVALID_AI_PROMPT' using errcode = '22023';
  end if;

  -- Serialize rate-limit decisions per customer so concurrent requests cannot race.
  perform pg_advisory_xact_lock(hashtextextended(p_customer_id::text, 0));

  select count(*)
    into v_minute_count
  from public.ai_basket_requests r
  where r.customer_id = p_customer_id
    and r.created_at >= now() - interval '1 minute';

  if v_minute_count >= 6 then
    raise exception 'AI_RATE_LIMIT_MINUTE' using errcode = 'P0001';
  end if;

  select count(*)
    into v_hour_count
  from public.ai_basket_requests r
  where r.customer_id = p_customer_id
    and r.created_at >= now() - interval '1 hour';

  if v_hour_count >= 60 then
    raise exception 'AI_RATE_LIMIT_HOUR' using errcode = 'P0001';
  end if;

  insert into public.ai_basket_requests (
    store_id,
    customer_id,
    prompt,
    status,
    started_at
  )
  values (
    p_store_id,
    p_customer_id,
    btrim(p_prompt),
    'processing',
    now()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.begin_ai_basket_request(uuid, uuid, text)
from public, anon, authenticated;

grant execute on function public.begin_ai_basket_request(uuid, uuid, text)
to service_role;

create index if not exists idx_ai_basket_customer_created
  on public.ai_basket_requests(customer_id, created_at desc);
