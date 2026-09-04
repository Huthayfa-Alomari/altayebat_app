-- Altayebat order/payment integrity hardening
--
-- Restricts administrative writes to operational columns and makes card payment
-- state gateway-managed. This is defense in depth behind the Admin UI and RLS.

begin;

-- ---------------------------------------------------------------------------
-- Domain constraints. Existing production values were verified before rollout.
-- ---------------------------------------------------------------------------
alter table public.orders
  drop constraint if exists orders_payment_method_check;
alter table public.orders
  add constraint orders_payment_method_check
  check (payment_method in ('cash', 'cliq', 'card'));

alter table public.orders
  drop constraint if exists orders_payment_status_check;
alter table public.orders
  add constraint orders_payment_status_check
  check (payment_status in ('unpaid', 'pending', 'paid', 'failed', 'refunded'));

alter table public.orders
  drop constraint if exists orders_payment_method_status_check;
alter table public.orders
  add constraint orders_payment_method_status_check
  check (
    (payment_method = 'cash' and payment_status in ('unpaid', 'paid'))
    or (payment_method = 'cliq' and payment_status in ('pending', 'paid', 'failed'))
    or (payment_method = 'card' and payment_status in ('pending', 'paid', 'failed', 'refunded'))
  );

-- ---------------------------------------------------------------------------
-- Authenticated store admins only need operational order mutation. Revoke the
-- table-wide UPDATE privilege so ownership, totals and gateway references cannot
-- be changed through the Data API even when RLS allows access to the row.
-- ---------------------------------------------------------------------------
revoke update on public.orders from authenticated;
grant update (status, payment_status, updated_at, driver_id)
  on public.orders to authenticated;

-- ---------------------------------------------------------------------------
-- Card payment state can only be changed by trusted server-side roles. Keep this
-- trigger SECURITY INVOKER so current_user reflects the actual caller.
-- ---------------------------------------------------------------------------
create or replace function private.guard_order_payment_integrity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;

  if new.payment_method is distinct from old.payment_method then
    raise exception 'Payment method is immutable'
      using errcode = '42501';
  end if;

  if new.payment_reference is distinct from old.payment_reference then
    raise exception 'Payment reference is gateway managed'
      using errcode = '42501';
  end if;

  if old.payment_method = 'card'
     and new.payment_status is distinct from old.payment_status then
    raise exception 'Card payment status is gateway managed'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke execute on function private.guard_order_payment_integrity()
  from public, anon;
grant execute on function private.guard_order_payment_integrity()
  to authenticated, service_role;

drop trigger if exists guard_order_payment_integrity on public.orders;
create trigger guard_order_payment_integrity
before update on public.orders
for each row
execute function private.guard_order_payment_integrity();

commit;
