create or replace function private.sync_rider_presence_from_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.driver_id is not null
     and new.status in ('preparing', 'out_for_delivery') then
    update public.drivers
       set availability_status = 'busy',
           status_updated_at = now()
     where id = new.driver_id
       and auth_user_id is not null
       and approval_status = 'approved'
       and is_active = true;
  end if;

  if old.driver_id is not null
     and (
       new.driver_id is distinct from old.driver_id
       or new.status in ('delivered', 'cancelled')
     )
     and not exists (
       select 1
       from public.orders o
       where o.driver_id = old.driver_id
         and o.id <> new.id
         and o.status in ('preparing', 'out_for_delivery')
     ) then
    update public.drivers
       set availability_status = case
             when availability_status = 'busy' then 'available'
             else availability_status
           end,
           status_updated_at = now()
     where id = old.driver_id
       and auth_user_id is not null;
  end if;

  return new;
end;
$$;

revoke all on function private.sync_rider_presence_from_order() from public, anon, authenticated;

drop trigger if exists orders_sync_rider_presence_trg on public.orders;
create trigger orders_sync_rider_presence_trg
after update of driver_id, status on public.orders
for each row
when (
  old.driver_id is distinct from new.driver_id
  or old.status is distinct from new.status
)
execute function private.sync_rider_presence_from_order();
