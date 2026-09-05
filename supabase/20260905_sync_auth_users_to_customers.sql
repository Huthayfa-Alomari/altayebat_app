create or replace function private.ensure_customer_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.customers (id, phone, name)
  values (
    new.id,
    nullif(new.phone, ''),
    nullif(
      coalesce(
        new.raw_user_meta_data ->> 'name',
        new.raw_user_meta_data ->> 'full_name'
      ),
      ''
    )
  )
  on conflict (id) do update
    set phone = coalesce(excluded.phone, public.customers.phone),
        name = coalesce(excluded.name, public.customers.name),
        updated_at = now();

  return new;
end;
$$;

drop trigger if exists trg_ensure_customer_for_auth_user on auth.users;

create trigger trg_ensure_customer_for_auth_user
after insert or update of phone, raw_user_meta_data on auth.users
for each row
execute function private.ensure_customer_for_auth_user();

insert into public.customers (id, phone, name)
select
  u.id,
  nullif(u.phone, ''),
  nullif(
    coalesce(
      u.raw_user_meta_data ->> 'name',
      u.raw_user_meta_data ->> 'full_name'
    ),
    ''
  )
from auth.users u
left join public.customers c on c.id = u.id
where c.id is null
on conflict (id) do nothing;
