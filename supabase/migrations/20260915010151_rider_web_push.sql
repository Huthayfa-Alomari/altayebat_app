-- Rider Web Push / FCM token registry.
-- Tokens are private and can only be registered by the authenticated rider who owns them.

create table if not exists public.rider_push_tokens (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  driver_id uuid not null references public.drivers(id) on delete cascade,
  token text not null unique,
  platform text not null default 'web'
    check (platform in ('web', 'android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists rider_push_tokens_driver_idx
  on public.rider_push_tokens(driver_id, store_id);

create index if not exists rider_push_tokens_store_idx
  on public.rider_push_tokens(store_id);

alter table public.rider_push_tokens enable row level security;

revoke all on public.rider_push_tokens from anon, authenticated;
grant select, insert, update, delete on public.rider_push_tokens to service_role;

create or replace function public.register_rider_push_token(
  p_token text,
  p_platform text default 'web'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_token text := btrim(coalesce(p_token, ''));
  v_platform text := lower(btrim(coalesce(p_platform, 'web')));
  v_driver public.drivers%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if length(v_token) < 20 or length(v_token) > 4096 then
    raise exception 'INVALID_PUSH_TOKEN' using errcode = '22023';
  end if;
  if v_platform not in ('web', 'android', 'ios') then
    raise exception 'INVALID_PUSH_PLATFORM' using errcode = '22023';
  end if;

  select d.* into v_driver
  from public.drivers d
  where d.auth_user_id = v_uid
  limit 1;

  if not found
     or v_driver.approval_status <> 'approved'
     or not coalesce(v_driver.is_active, false) then
    raise exception 'RIDER_NOT_APPROVED' using errcode = '42501';
  end if;

  insert into public.rider_push_tokens(
    store_id, driver_id, token, platform, updated_at, last_seen_at
  ) values (
    v_driver.store_id, v_driver.id, v_token, v_platform, now(), now()
  )
  on conflict (token) do update
  set store_id = excluded.store_id,
      driver_id = excluded.driver_id,
      platform = excluded.platform,
      updated_at = now(),
      last_seen_at = now();

  return jsonb_build_object(
    'ok', true,
    'driver_id', v_driver.id,
    'store_id', v_driver.store_id,
    'platform', v_platform
  );
end;
$$;

create or replace function public.unregister_rider_push_token(p_token text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_driver_id uuid;
  v_deleted integer := 0;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  select d.id into v_driver_id
  from public.drivers d
  where d.auth_user_id = v_uid
  limit 1;

  if v_driver_id is null then
    return false;
  end if;

  delete from public.rider_push_tokens
  where token = btrim(coalesce(p_token, ''))
    and driver_id = v_driver_id;

  get diagnostics v_deleted = row_count;
  return v_deleted > 0;
end;
$$;

revoke all on function public.register_rider_push_token(text,text) from public, anon;
revoke all on function public.unregister_rider_push_token(text) from public, anon;

grant execute on function public.register_rider_push_token(text,text) to authenticated;
grant execute on function public.unregister_rider_push_token(text) to authenticated;
