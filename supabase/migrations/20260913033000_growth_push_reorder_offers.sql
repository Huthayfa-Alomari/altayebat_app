-- Altayebat growth features: offers, notification inbox and push tokens.
-- Reorder itself reuses the existing customer-owned orders/order_items RLS and
-- current product rows so prices and stock are always revalidated at reorder time.

begin;

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Product offers
-- The existing checkout reads products.price. Activating an offer therefore
-- atomically updates products.price/price_per_unit and stores the regular price
-- on the offer row. This keeps every existing checkout/payment path authoritative
-- on the server and avoids a client-only discount.
-- ---------------------------------------------------------------------------
create table if not exists public.store_offers (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  title text not null,
  subtitle text,
  regular_price_per_unit numeric(14,6) not null check (regular_price_per_unit > 0),
  offer_price_per_unit numeric(14,6) not null check (offer_price_per_unit > 0),
  regular_atomic_price numeric(14,6) not null check (regular_atomic_price > 0),
  offer_atomic_price numeric(14,6) not null check (offer_atomic_price > 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  is_active boolean not null default true,
  notify_customers boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  constraint store_offers_discount_check
    check (offer_price_per_unit < regular_price_per_unit),
  constraint store_offers_window_check
    check (ends_at is null or ends_at > starts_at)
);

create unique index if not exists store_offers_one_active_per_product_idx
  on public.store_offers(product_id)
  where is_active = true;
create index if not exists store_offers_store_active_idx
  on public.store_offers(store_id, is_active, created_at desc);
create index if not exists store_offers_expiry_idx
  on public.store_offers(ends_at)
  where is_active = true and ends_at is not null;

alter table public.store_offers enable row level security;

drop policy if exists store_offers_read on public.store_offers;
create policy store_offers_read
on public.store_offers for select
to authenticated
using (
  private.is_store_admin(store_id)
  or (
    is_active = true
    and starts_at <= now()
    and (ends_at is null or ends_at > now())
  )
);

revoke all on public.store_offers from anon, authenticated;
grant select on public.store_offers to authenticated;
grant select, insert, update, delete on public.store_offers to service_role;

-- ---------------------------------------------------------------------------
-- Customer notification inbox. Push is an additional delivery channel; the
-- inbox remains the durable source of truth if a device has notifications off.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_notifications (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  type text not null check (type in ('order_status', 'offer', 'system')),
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists customer_notifications_customer_created_idx
  on public.customer_notifications(customer_id, created_at desc);
create index if not exists customer_notifications_customer_unread_idx
  on public.customer_notifications(customer_id, created_at desc)
  where read_at is null;
create index if not exists customer_notifications_order_idx
  on public.customer_notifications(order_id)
  where order_id is not null;

alter table public.customer_notifications enable row level security;

drop policy if exists customer_notifications_read on public.customer_notifications;
create policy customer_notifications_read
on public.customer_notifications for select
to authenticated
using ((select auth.uid()) = customer_id);

drop policy if exists customer_notifications_mark_read on public.customer_notifications;
create policy customer_notifications_mark_read
on public.customer_notifications for update
to authenticated
using ((select auth.uid()) = customer_id)
with check ((select auth.uid()) = customer_id);

revoke all on public.customer_notifications from anon, authenticated;
grant select, update on public.customer_notifications to authenticated;
grant select, insert, update, delete on public.customer_notifications to service_role;

-- ---------------------------------------------------------------------------
-- Push tokens. Customers never need to read tokens back from Data API.
-- ---------------------------------------------------------------------------
create table if not exists public.customer_push_tokens (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists customer_push_tokens_customer_idx
  on public.customer_push_tokens(customer_id, store_id);
create index if not exists customer_push_tokens_store_idx
  on public.customer_push_tokens(store_id);

alter table public.customer_push_tokens enable row level security;
revoke all on public.customer_push_tokens from anon, authenticated;
grant select, insert, update, delete on public.customer_push_tokens to service_role;

create or replace function public.register_push_token(
  p_store_id uuid,
  p_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_token text := trim(coalesce(p_token, ''));
  v_platform text := lower(trim(coalesce(p_platform, '')));
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if length(v_token) < 20 or length(v_token) > 4096 then
    raise exception 'Invalid push token' using errcode = '22023';
  end if;
  if v_platform not in ('android', 'ios') then
    raise exception 'Invalid push platform' using errcode = '22023';
  end if;
  if not exists (select 1 from public.customers c where c.id = v_user_id) then
    -- Anonymous browsing sessions do not have a customer profile yet. Push token
    -- registration will be retried after profile creation/next app launch.
    return;
  end if;
  if not exists (select 1 from public.stores s where s.id = p_store_id) then
    raise exception 'Store not found' using errcode = 'P0002';
  end if;

  insert into public.customer_push_tokens(
    store_id, customer_id, token, platform, updated_at, last_seen_at
  ) values (
    p_store_id, v_user_id, v_token, v_platform, now(), now()
  )
  on conflict (token) do update
  set store_id = excluded.store_id,
      customer_id = excluded.customer_id,
      platform = excluded.platform,
      updated_at = now(),
      last_seen_at = now();
end;
$$;

revoke all on function public.register_push_token(uuid, text, text)
  from public, anon;
grant execute on function public.register_push_token(uuid, text, text)
  to authenticated;

create or replace function public.unregister_push_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.customer_push_tokens
  where token = trim(coalesce(p_token, ''))
    and customer_id = (select auth.uid());
end;
$$;

revoke all on function public.unregister_push_token(text) from public, anon;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Offer lifecycle helpers.
-- ---------------------------------------------------------------------------
create or replace function private.refresh_expired_offers_for_store(p_store_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.store_offers%rowtype;
  v_count integer := 0;
begin
  for v_offer in
    select *
    from public.store_offers
    where store_id = p_store_id
      and is_active = true
      and ends_at is not null
      and ends_at <= now()
    for update
  loop
    -- Restore only while the product still carries this offer price. If an admin
    -- manually changed the product meanwhile, preserve the newer manual price.
    update public.products
    set price = v_offer.regular_atomic_price,
        price_per_unit = v_offer.regular_price_per_unit,
        updated_at = now()
    where id = v_offer.product_id
      and store_id = v_offer.store_id
      and abs(price - v_offer.offer_atomic_price) < 0.000001
      and abs(price_per_unit - v_offer.offer_price_per_unit) < 0.000001;

    update public.store_offers
    set is_active = false,
        ended_at = coalesce(ended_at, now())
    where id = v_offer.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function private.refresh_expired_offers_for_store(uuid)
  from public, anon, authenticated;

create or replace function public.refresh_expired_offers(p_store_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return private.refresh_expired_offers_for_store(p_store_id);
end;
$$;

revoke all on function public.refresh_expired_offers(uuid) from public, anon;
grant execute on function public.refresh_expired_offers(uuid) to authenticated;

create or replace function public.admin_create_product_offer(
  p_store_id uuid,
  p_product_id uuid,
  p_title text,
  p_subtitle text,
  p_offer_price_per_unit numeric,
  p_ends_at timestamptz default null,
  p_notify_customers boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product public.products%rowtype;
  v_offer_id uuid;
  v_offer_atomic numeric(14,6);
  v_title text;
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  perform private.refresh_expired_offers_for_store(p_store_id);

  select * into v_product
  from public.products
  where id = p_product_id and store_id = p_store_id
  for update;

  if not found then
    raise exception 'PRODUCT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if coalesce(v_product.price_per_unit, 0) <= 0 then
    raise exception 'INVALID_REGULAR_PRICE' using errcode = '22023';
  end if;
  if p_offer_price_per_unit is null
     or p_offer_price_per_unit <= 0
     or p_offer_price_per_unit >= v_product.price_per_unit then
    raise exception 'OFFER_PRICE_MUST_BE_LOWER' using errcode = '22023';
  end if;
  if p_ends_at is not null and p_ends_at <= now() then
    raise exception 'OFFER_END_MUST_BE_FUTURE' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.store_offers
    where product_id = p_product_id and is_active = true
  ) then
    raise exception 'ACTIVE_OFFER_EXISTS' using errcode = '23505';
  end if;

  v_offer_atomic := round(
    p_offer_price_per_unit / greatest(coalesce(v_product.inventory_scale, 1), 1),
    6
  );
  if v_offer_atomic <= 0 then
    raise exception 'OFFER_ATOMIC_PRICE_TOO_SMALL' using errcode = '22023';
  end if;

  v_title := coalesce(nullif(trim(p_title), ''), 'عرض على ' || v_product.name);

  insert into public.store_offers(
    store_id, product_id, title, subtitle,
    regular_price_per_unit, offer_price_per_unit,
    regular_atomic_price, offer_atomic_price,
    ends_at, notify_customers, created_by
  ) values (
    p_store_id, p_product_id, v_title, nullif(trim(coalesce(p_subtitle, '')), ''),
    v_product.price_per_unit, p_offer_price_per_unit,
    v_product.price, v_offer_atomic,
    p_ends_at, coalesce(p_notify_customers, true), (select auth.uid())
  ) returning id into v_offer_id;

  update public.products
  set price_per_unit = p_offer_price_per_unit,
      price = v_offer_atomic,
      updated_at = now()
  where id = p_product_id and store_id = p_store_id;

  if coalesce(p_notify_customers, true) then
    insert into public.customer_notifications(
      store_id, customer_id, type, title, body, data
    )
    select distinct
      p_store_id,
      o.customer_id,
      'offer',
      v_title,
      coalesce(nullif(trim(coalesce(p_subtitle, '')), ''),
        v_product.name || ' الآن بسعر ' || trim(to_char(p_offer_price_per_unit, 'FM999999990.000')) || ' د.أ'),
      jsonb_build_object(
        'offer_id', v_offer_id,
        'product_id', p_product_id,
        'kind', 'offer'
      )
    from public.orders o
    where o.store_id = p_store_id;
  end if;

  return v_offer_id;
end;
$$;

revoke all on function public.admin_create_product_offer(
  uuid, uuid, text, text, numeric, timestamptz, boolean
) from public, anon;
grant execute on function public.admin_create_product_offer(
  uuid, uuid, text, text, numeric, timestamptz, boolean
) to authenticated;

create or replace function public.admin_end_product_offer(p_offer_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.store_offers%rowtype;
begin
  select * into v_offer
  from public.store_offers
  where id = p_offer_id
  for update;

  if not found then
    raise exception 'OFFER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not private.is_store_admin(v_offer.store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if not v_offer.is_active then
    return;
  end if;

  update public.products
  set price = v_offer.regular_atomic_price,
      price_per_unit = v_offer.regular_price_per_unit,
      updated_at = now()
  where id = v_offer.product_id
    and store_id = v_offer.store_id
    and abs(price - v_offer.offer_atomic_price) < 0.000001
    and abs(price_per_unit - v_offer.offer_price_per_unit) < 0.000001;

  update public.store_offers
  set is_active = false,
      ended_at = now()
  where id = p_offer_id;
end;
$$;

revoke all on function public.admin_end_product_offer(uuid) from public, anon;
grant execute on function public.admin_end_product_offer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Durable order-status notifications. Sending the remote push happens from the
-- Edge Function after an admin/SUNMI status change; this trigger guarantees the
-- notification center is still correct even if FCM is temporarily unavailable.
-- ---------------------------------------------------------------------------
create or replace function private.enqueue_order_status_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_body text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  v_title := case new.status
    when 'preparing' then 'بدأنا تجهيز طلبك'
    when 'out_for_delivery' then 'طلبك في الطريق'
    when 'delivered' then 'تم توصيل طلبك'
    when 'cancelled' then 'تم إلغاء الطلب'
    else 'تحديث على طلبك'
  end;

  v_body := case new.status
    when 'preparing' then 'فريق أسواق الطيبات يعمل الآن على تجهيز طلبك.'
    when 'out_for_delivery' then 'السائق خرج بطلبك. يمكنك متابعة التوصيل من التطبيق.'
    when 'delivered' then 'نتمنى أن تكون تجربتك ممتازة. شكراً لتسوقك معنا.'
    when 'cancelled' then 'تم إلغاء الطلب. افتح التطبيق لمعرفة التفاصيل أو إعادة الطلب.'
    else 'تم تحديث حالة طلبك.'
  end;

  insert into public.customer_notifications(
    store_id, customer_id, order_id, type, title, body, data
  ) values (
    new.store_id,
    new.customer_id,
    new.id,
    'order_status',
    v_title,
    v_body,
    jsonb_build_object('order_id', new.id, 'status', new.status, 'kind', 'order_status')
  );

  return new;
end;
$$;

revoke all on function private.enqueue_order_status_notification()
  from public, anon, authenticated;

drop trigger if exists trg_orders_customer_notification on public.orders;
create trigger trg_orders_customer_notification
after update of status on public.orders
for each row
when (old.status is distinct from new.status)
execute function private.enqueue_order_status_notification();

commit;
