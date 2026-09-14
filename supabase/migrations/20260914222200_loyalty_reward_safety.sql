-- Make automatic loyalty reward redemption safe for order inserts/cancellations.
-- The previous BEFORE INSERT function cannot write an event referencing the new
-- order until the order row exists, so we mark the order in BEFORE INSERT and
-- write the audit event in AFTER INSERT. Cancelled orders restore the reward.

begin;

alter table public.orders
  add column if not exists loyalty_reward_applied boolean not null default false,
  add column if not exists loyalty_savings numeric(12,3) not null default 0;

alter table public.loyalty_events
  drop constraint if exists loyalty_events_event_type_check;

alter table public.loyalty_events
  add constraint loyalty_events_event_type_check
  check (
    event_type in (
      'basket_earned',
      'reward_unlocked',
      'reward_redeemed',
      'reward_restored',
      'adjustment'
    )
  );

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

  new.loyalty_reward_applied := true;
  new.loyalty_savings := v_fee;
  new.delivery_fee := 0;
  new.total := greatest(0, coalesce(new.total, 0) - v_fee);

  return new;
end;
$$;

create or replace function private.trg_log_loyalty_redemption()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce(new.loyalty_reward_applied, false) then
    return new;
  end if;

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
      'saved_delivery_fee', coalesce(new.loyalty_savings, 0)
    )
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_log_loyalty_redemption on public.orders;
create trigger trg_log_loyalty_redemption
after insert on public.orders
for each row
execute function private.trg_log_loyalty_redemption();

create or replace function private.trg_restore_cancelled_loyalty_reward()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
begin
  if new.status <> 'cancelled'
     or old.status is not distinct from new.status
     or not coalesce(new.loyalty_reward_applied, false)
     or old.status = 'delivered' then
    return new;
  end if;

  if exists (
    select 1
    from public.loyalty_events e
    where e.order_id = new.id
      and e.event_type = 'reward_restored'
  ) then
    return new;
  end if;

  insert into public.loyalty_events(
    store_id, customer_id, order_id, event_type,
    delta_rewards, metadata
  ) values (
    new.store_id,
    new.customer_id,
    new.id,
    'reward_restored',
    1,
    jsonb_build_object('reason', 'order_cancelled')
  )
  returning id into v_event_id;

  if v_event_id is not null then
    insert into public.customer_loyalty_wallets(
      store_id, customer_id, rewards_available
    ) values (
      new.store_id, new.customer_id, 1
    )
    on conflict (store_id, customer_id) do update
    set rewards_available = public.customer_loyalty_wallets.rewards_available + 1,
        rewards_redeemed = greatest(
          0,
          public.customer_loyalty_wallets.rewards_redeemed - 1
        ),
        updated_at = now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_restore_cancelled_loyalty_reward on public.orders;
create trigger trg_restore_cancelled_loyalty_reward
after update of status on public.orders
for each row
execute function private.trg_restore_cancelled_loyalty_reward();

revoke all on function private.trg_redeem_loyalty_delivery()
  from public, anon, authenticated;
revoke all on function private.trg_log_loyalty_redemption()
  from public, anon, authenticated;
revoke all on function private.trg_restore_cancelled_loyalty_reward()
  from public, anon, authenticated;

commit;
