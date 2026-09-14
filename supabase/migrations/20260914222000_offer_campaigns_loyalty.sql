-- Scheduled multi-product offer campaigns + "Altayebat Baskets" loyalty.
--
-- Offer campaigns let admins select several inventory products and give every
-- selected product its own offer price under one start/end window.
-- Loyalty deliberately avoids opaque points: every eligible delivered order
-- fills one basket. Completing the configured number of baskets unlocks an
-- automatic free-delivery reward on the next order that has a delivery fee.

begin;

-- ---------------------------------------------------------------------------
-- Offer campaigns
-- ---------------------------------------------------------------------------
create table if not exists public.store_offer_campaigns (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  title text not null,
  subtitle text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  notify_customers boolean not null default true,
  notified_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint store_offer_campaigns_window_check check (ends_at > starts_at)
);

create index if not exists store_offer_campaigns_store_window_idx
  on public.store_offer_campaigns(store_id, starts_at, ends_at);

alter table public.store_offer_campaigns enable row level security;

drop policy if exists store_offer_campaigns_read on public.store_offer_campaigns;
create policy store_offer_campaigns_read
on public.store_offer_campaigns for select
to authenticated
using (private.is_store_admin(store_id));

revoke all on public.store_offer_campaigns from anon, authenticated;
grant select on public.store_offer_campaigns to authenticated;
grant all on public.store_offer_campaigns to service_role;

alter table public.store_offers
  add column if not exists campaign_id uuid
    references public.store_offer_campaigns(id) on delete set null;

create index if not exists store_offers_campaign_idx
  on public.store_offers(campaign_id);

-- Keep the existing public refresh RPC name so old Flutter builds continue to
-- work. It now expires old offers AND activates scheduled offers that are due.
create or replace function private.refresh_expired_offers_for_store(p_store_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_offer public.store_offers%rowtype;
  v_campaign public.store_offer_campaigns%rowtype;
  v_count integer := 0;
begin
  -- 1) End active offers whose window closed and restore the regular price only
  -- when the product still carries the offer price.
  for v_offer in
    select *
    from public.store_offers
    where store_id = p_store_id
      and is_active = true
      and ends_at is not null
      and ends_at <= now()
    for update
  loop
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

  -- 2) Close scheduled offers that completely passed before any client/admin
  -- had a chance to run the refresh RPC.
  update public.store_offers
  set ended_at = coalesce(ended_at, now())
  where store_id = p_store_id
    and is_active = false
    and ended_at is null
    and ends_at is not null
    and ends_at <= now();

  get diagnostics v_count = v_count + row_count;

  -- 3) Activate due scheduled offers. Overlapping windows are prevented by the
  -- batch creation RPC, so this can safely update the authoritative product
  -- price before exposing the offer.
  for v_offer in
    select *
    from public.store_offers
    where store_id = p_store_id
      and is_active = false
      and ended_at is null
      and starts_at <= now()
      and (ends_at is null or ends_at > now())
    order by starts_at, created_at
    for update
  loop
    if exists (
      select 1
      from public.store_offers other
      where other.product_id = v_offer.product_id
        and other.id <> v_offer.id
        and other.is_active = true
    ) then
      continue;
    end if;

    update public.products
    set price = v_offer.offer_atomic_price,
        price_per_unit = v_offer.offer_price_per_unit,
        updated_at = now()
    where id = v_offer.product_id
      and store_id = v_offer.store_id;

    update public.store_offers
    set is_active = true
    where id = v_offer.id;

    v_count := v_count + 1;
  end loop;

  -- 4) Create one durable inbox notification per campaign, not one notification
  -- per product. Push remains best-effort and can be layered on later without
  -- changing campaign pricing semantics.
  for v_campaign in
    select *
    from public.store_offer_campaigns c
    where c.store_id = p_store_id
      and c.notify_customers = true
      and c.notified_at is null
      and c.starts_at <= now()
      and c.ends_at > now()
      and exists (
        select 1 from public.store_offers o
        where o.campaign_id = c.id and o.is_active = true
      )
    for update
  loop
    insert into public.customer_notifications(
      store_id, customer_id, type, title, body, data
    )
    select distinct
      p_store_id,
      o.customer_id,
      'offer',
      v_campaign.title,
      coalesce(nullif(trim(coalesce(v_campaign.subtitle, '')), ''),
               'بدأ عرض جديد في أسواق الطيبات. افتح التطبيق وشاهد الأصناف المختارة.'),
      jsonb_build_object(
        'kind', 'offer_campaign',
        'campaign_id', v_campaign.id
      )
    from public.orders o
    where o.store_id = p_store_id;

    update public.store_offer_campaigns
    set notified_at = now()
    where id = v_campaign.id;
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

create or replace function public.admin_create_offer_campaign(
  p_store_id uuid,
  p_items jsonb,
  p_title text,
  p_subtitle text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_notify_customers boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_campaign_id uuid;
  v_product public.products%rowtype;
  v_item record;
  v_offer_id uuid;
  v_offer_atomic numeric(14,6);
  v_title text := coalesce(nullif(trim(p_title), ''), 'عروض الطيبات');
  v_offer_ids jsonb := '[]'::jsonb;
  v_start timestamptz := coalesce(p_starts_at, now());
  v_active_now boolean;
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'OFFER_ITEMS_REQUIRED' using errcode = '22023';
  end if;

  if jsonb_array_length(p_items) > 100 then
    raise exception 'TOO_MANY_OFFER_ITEMS' using errcode = '22023';
  end if;

  if p_ends_at is null or p_ends_at <= v_start then
    raise exception 'INVALID_OFFER_WINDOW' using errcode = '22023';
  end if;

  perform private.refresh_expired_offers_for_store(p_store_id);
  v_active_now := v_start <= now() and p_ends_at > now();

  insert into public.store_offer_campaigns(
    store_id, title, subtitle, starts_at, ends_at,
    notify_customers, created_by
  ) values (
    p_store_id,
    v_title,
    nullif(trim(coalesce(p_subtitle, '')), ''),
    v_start,
    p_ends_at,
    coalesce(p_notify_customers, true),
    (select auth.uid())
  ) returning id into v_campaign_id;

  for v_item in
    select x.product_id, x.offer_price_per_unit
    from jsonb_to_recordset(p_items)
      as x(product_id uuid, offer_price_per_unit numeric)
  loop
    if v_item.product_id is null or v_item.offer_price_per_unit is null then
      raise exception 'INVALID_OFFER_ITEM' using errcode = '22023';
    end if;

    select * into v_product
    from public.products
    where id = v_item.product_id
      and store_id = p_store_id
      and is_available = true
    for update;

    if not found then
      raise exception 'PRODUCT_NOT_FOUND_OR_UNAVAILABLE' using errcode = 'P0002';
    end if;

    if coalesce(v_product.price_per_unit, 0) <= 0
       or v_item.offer_price_per_unit <= 0
       or v_item.offer_price_per_unit >= v_product.price_per_unit then
      raise exception 'OFFER_PRICE_MUST_BE_LOWER: %', v_product.name
        using errcode = '22023';
    end if;

    if exists (
      select 1
      from public.store_offers existing
      where existing.product_id = v_item.product_id
        and existing.store_id = p_store_id
        and existing.ended_at is null
        and existing.starts_at < p_ends_at
        and coalesce(existing.ends_at, 'infinity'::timestamptz) > v_start
    ) then
      raise exception 'OFFER_WINDOW_OVERLAP: %', v_product.name
        using errcode = '23505';
    end if;

    v_offer_atomic := round(
      v_item.offer_price_per_unit /
        greatest(coalesce(v_product.inventory_scale, 1), 1),
      6
    );

    if v_offer_atomic <= 0 then
      raise exception 'OFFER_ATOMIC_PRICE_TOO_SMALL: %', v_product.name
        using errcode = '22023';
    end if;

    insert into public.store_offers(
      store_id, product_id, campaign_id,
      title, subtitle,
      regular_price_per_unit, offer_price_per_unit,
      regular_atomic_price, offer_atomic_price,
      starts_at, ends_at, is_active,
      notify_customers, created_by
    ) values (
      p_store_id,
      v_product.id,
      v_campaign_id,
      v_title,
      nullif(trim(coalesce(p_subtitle, '')), ''),
      v_product.price_per_unit,
      v_item.offer_price_per_unit,
      v_product.price,
      v_offer_atomic,
      v_start,
      p_ends_at,
      v_active_now,
      false,
      (select auth.uid())
    ) returning id into v_offer_id;

    v_offer_ids := v_offer_ids || jsonb_build_array(v_offer_id);

    if v_active_now then
      update public.products
      set price = v_offer_atomic,
          price_per_unit = v_item.offer_price_per_unit,
          updated_at = now()
      where id = v_product.id and store_id = p_store_id;
    end if;
  end loop;

  if v_active_now and coalesce(p_notify_customers, true) then
    insert into public.customer_notifications(
      store_id, customer_id, type, title, body, data
    )
    select distinct
      p_store_id,
      o.customer_id,
      'offer',
      v_title,
      coalesce(nullif(trim(coalesce(p_subtitle, '')), ''),
               'بدأ عرض جديد في أسواق الطيبات. افتح التطبيق وشاهد الأصناف المختارة.'),
      jsonb_build_object(
        'kind', 'offer_campaign',
        'campaign_id', v_campaign_id
      )
    from public.orders o
    where o.store_id = p_store_id;

    update public.store_offer_campaigns
    set notified_at = now()
    where id = v_campaign_id;
  end if;

  return jsonb_build_object(
    'campaign_id', v_campaign_id,
    'offer_ids', v_offer_ids,
    'offer_count', jsonb_array_length(v_offer_ids),
    'active_now', v_active_now,
    'starts_at', v_start,
    'ends_at', p_ends_at
  );
end;
$$;

revoke all on function public.admin_create_offer_campaign(
  uuid, jsonb, text, text, timestamptz, timestamptz, boolean
) from public, anon;
grant execute on function public.admin_create_offer_campaign(
  uuid, jsonb, text, text, timestamptz, timestamptz, boolean
) to authenticated;

-- ---------------------------------------------------------------------------
-- Loyalty: "سلال الطيبات"
-- One eligible delivered order = one basket. Completing the basket cycle earns
-- one automatic free-delivery reward. There are no confusing point values or
-- conversion rates for the customer to remember.
-- ---------------------------------------------------------------------------
create table if not exists public.loyalty_programs (
  store_id uuid primary key references public.stores(id) on delete cascade,
  is_enabled boolean not null default true,
  program_name text not null default 'مكافآت الطيبات',
  baskets_required integer not null default 5
    check (baskets_required between 2 and 20),
  min_order_total numeric(12,3) not null default 5
    check (min_order_total >= 0),
  reward_type text not null default 'free_delivery'
    check (reward_type in ('free_delivery')),
  reward_title text not null default 'التوصيل علينا بالطلب القادم',
  updated_at timestamptz not null default now(),
  updated_by uuid
);

insert into public.loyalty_programs(store_id)
select s.id from public.stores s
on conflict (store_id) do nothing;

alter table public.loyalty_programs enable row level security;

drop policy if exists loyalty_programs_read on public.loyalty_programs;
create policy loyalty_programs_read
on public.loyalty_programs for select
to authenticated
using (true);

drop policy if exists loyalty_programs_admin_insert on public.loyalty_programs;
create policy loyalty_programs_admin_insert
on public.loyalty_programs for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists loyalty_programs_admin_update on public.loyalty_programs;
create policy loyalty_programs_admin_update
on public.loyalty_programs for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

revoke all on public.loyalty_programs from anon, authenticated;
grant select, insert, update on public.loyalty_programs to authenticated;
grant all on public.loyalty_programs to service_role;

create table if not exists public.customer_loyalty_wallets (
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  baskets_current integer not null default 0 check (baskets_current >= 0),
  lifetime_baskets integer not null default 0 check (lifetime_baskets >= 0),
  rewards_available integer not null default 0 check (rewards_available >= 0),
  rewards_redeemed integer not null default 0 check (rewards_redeemed >= 0),
  updated_at timestamptz not null default now(),
  primary key (store_id, customer_id)
);

create index if not exists customer_loyalty_wallets_customer_idx
  on public.customer_loyalty_wallets(customer_id, store_id);

alter table public.customer_loyalty_wallets enable row level security;

drop policy if exists customer_loyalty_wallets_read on public.customer_loyalty_wallets;
create policy customer_loyalty_wallets_read
on public.customer_loyalty_wallets for select
to authenticated
using (
  customer_id = (select auth.uid())
  or private.is_store_admin(store_id)
);

revoke all on public.customer_loyalty_wallets from anon, authenticated;
grant select on public.customer_loyalty_wallets to authenticated;
grant all on public.customer_loyalty_wallets to service_role;

create table if not exists public.loyalty_events (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  order_id uuid references public.orders(id) on delete set null,
  event_type text not null
    check (event_type in ('basket_earned','reward_unlocked','reward_redeemed','adjustment')),
  delta_baskets integer not null default 0,
  delta_rewards integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create unique index if not exists loyalty_events_order_event_unique_idx
  on public.loyalty_events(order_id, event_type)
  where order_id is not null
    and event_type in ('basket_earned','reward_redeemed');
create index if not exists loyalty_events_customer_created_idx
  on public.loyalty_events(customer_id, created_at desc);

alter table public.loyalty_events enable row level security;

drop policy if exists loyalty_events_read on public.loyalty_events;
create policy loyalty_events_read
on public.loyalty_events for select
to authenticated
using (
  customer_id = (select auth.uid())
  or private.is_store_admin(store_id)
);

revoke all on public.loyalty_events from anon, authenticated;
grant select on public.loyalty_events to authenticated;
grant all on public.loyalty_events to service_role;

create or replace function public.get_my_loyalty_status(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_program public.loyalty_programs%rowtype;
  v_wallet public.customer_loyalty_wallets%rowtype;
  v_remaining integer;
begin
  select * into v_program
  from public.loyalty_programs
  where store_id = p_store_id;

  if not found or not v_program.is_enabled then
    return jsonb_build_object('enabled', false);
  end if;

  if v_user_id is not null then
    select * into v_wallet
    from public.customer_loyalty_wallets
    where store_id = p_store_id and customer_id = v_user_id;
  end if;

  v_remaining := greatest(
    0,
    v_program.baskets_required - coalesce(v_wallet.baskets_current, 0)
  );

  return jsonb_build_object(
    'enabled', true,
    'program_name', v_program.program_name,
    'baskets_current', coalesce(v_wallet.baskets_current, 0),
    'baskets_required', v_program.baskets_required,
    'orders_remaining', v_remaining,
    'lifetime_baskets', coalesce(v_wallet.lifetime_baskets, 0),
    'rewards_available', coalesce(v_wallet.rewards_available, 0),
    'rewards_redeemed', coalesce(v_wallet.rewards_redeemed, 0),
    'reward_type', v_program.reward_type,
    'reward_title', v_program.reward_title,
    'min_order_total', v_program.min_order_total
  );
end;
$$;

revoke all on function public.get_my_loyalty_status(uuid) from public, anon;
grant execute on function public.get_my_loyalty_status(uuid) to authenticated;

-- Redeem the reward automatically before an order is inserted. This makes the
-- experience coupon-free: if the customer has a free-delivery reward and the
-- new order has a delivery fee, the system applies it without another tap.
create or replace function private.trg_redeem_loyalty_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_program public.loyalty_programs%rowtype;
  v_fee numeric(12,3);
  v_updated integer;
begin
  v_fee := coalesce(new.delivery_fee, 0);
  if new.customer_id is null or new.store_id is null or v_fee <= 0 then
    return new;
  end if;

  select * into v_program
  from public.loyalty_programs
  where store_id = new.store_id and is_enabled = true;

  if not found or v_program.reward_type <> 'free_delivery' then
    return new;
  end if;

  update public.customer_loyalty_wallets
  set rewards_available = rewards_available - 1,
      rewards_redeemed = rewards_redeemed + 1,
      updated_at = now()
  where store_id = new.store_id
    and customer_id = new.customer_id
    and rewards_available > 0;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    return new;
  end if;

  new.delivery_fee := 0;
  new.total := greatest(0, coalesce(new.total, 0) - v_fee);

  insert into public.loyalty_events(
    store_id, customer_id, order_id, event_type,
    delta_rewards, metadata
  ) values (
    new.store_id,
    new.customer_id,
    new.id,
    'reward_redeemed',
    -1,
    jsonb_build_object(
      'reward_type', 'free_delivery',
      'saved_delivery_fee', v_fee
    )
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_redeem_loyalty_delivery on public.orders;
create trigger trg_redeem_loyalty_delivery
before insert on public.orders
for each row
execute function private.trg_redeem_loyalty_delivery();

-- Earn one basket only when the order actually reaches delivered. The unique
-- basket_earned event makes the trigger idempotent if a status update is retried.
create or replace function private.trg_award_loyalty_basket()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_program public.loyalty_programs%rowtype;
  v_wallet public.customer_loyalty_wallets%rowtype;
  v_event_id uuid;
  v_new_baskets integer;
  v_unlocked integer;
begin
  if new.status <> 'delivered'
     or old.status is not distinct from new.status
     or new.customer_id is null then
    return new;
  end if;

  select * into v_program
  from public.loyalty_programs
  where store_id = new.store_id and is_enabled = true;

  if not found then
    return new;
  end if;

  if coalesce(new.subtotal, new.total, 0) < v_program.min_order_total then
    return new;
  end if;

  insert into public.loyalty_events(
    store_id, customer_id, order_id, event_type,
    delta_baskets, metadata
  ) values (
    new.store_id,
    new.customer_id,
    new.id,
    'basket_earned',
    1,
    jsonb_build_object('order_total', new.total)
  )
  on conflict do nothing
  returning id into v_event_id;

  if v_event_id is null then
    return new;
  end if;

  insert into public.customer_loyalty_wallets(
    store_id, customer_id
  ) values (
    new.store_id, new.customer_id
  )
  on conflict (store_id, customer_id) do nothing;

  select * into v_wallet
  from public.customer_loyalty_wallets
  where store_id = new.store_id and customer_id = new.customer_id
  for update;

  v_new_baskets := v_wallet.baskets_current + 1;
  v_unlocked := v_new_baskets / v_program.baskets_required;

  update public.customer_loyalty_wallets
  set baskets_current = v_new_baskets % v_program.baskets_required,
      lifetime_baskets = lifetime_baskets + 1,
      rewards_available = rewards_available + v_unlocked,
      updated_at = now()
  where store_id = new.store_id and customer_id = new.customer_id;

  if v_unlocked > 0 then
    insert into public.loyalty_events(
      store_id, customer_id, order_id, event_type,
      delta_rewards, metadata
    ) values (
      new.store_id,
      new.customer_id,
      new.id,
      'reward_unlocked',
      v_unlocked,
      jsonb_build_object('reward_title', v_program.reward_title)
    );

    insert into public.customer_notifications(
      store_id, customer_id, order_id, type, title, body, data
    ) values (
      new.store_id,
      new.customer_id,
      new.id,
      'system',
      '🎁 اكتملت سلة المكافآت',
      v_program.reward_title || ' — ستتطبق تلقائيًا على طلبك القادم.',
      jsonb_build_object(
        'kind', 'loyalty_reward',
        'reward_type', v_program.reward_type
      )
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_award_loyalty_basket on public.orders;
create trigger trg_award_loyalty_basket
after update of status on public.orders
for each row
execute function private.trg_award_loyalty_basket();

revoke all on function private.trg_redeem_loyalty_delivery()
  from public, anon, authenticated;
revoke all on function private.trg_award_loyalty_basket()
  from public, anon, authenticated;

commit;
