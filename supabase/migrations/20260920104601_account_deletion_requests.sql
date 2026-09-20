
create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  status text not null default 'requested'
    check (status in ('requested','processing','completed','rejected','cancelled')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  admin_note text,
  unique (store_id, customer_id)
);

alter table public.account_deletion_requests enable row level security;

revoke all on public.account_deletion_requests from anon;
revoke all on public.account_deletion_requests from authenticated;
grant select, insert on public.account_deletion_requests to authenticated;

create policy account_deletion_requests_customer_select
on public.account_deletion_requests for select
to authenticated
using ((select auth.uid()) = customer_id);

create policy account_deletion_requests_customer_insert
on public.account_deletion_requests for insert
to authenticated
with check ((select auth.uid()) = customer_id);

create index if not exists idx_account_deletion_requests_store_status_requested
  on public.account_deletion_requests(store_id, status, requested_at desc);

create or replace function public.request_account_deletion(p_store_id uuid)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_row public.account_deletion_requests;
begin
  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.customers c
    where c.id = v_user
  ) then
    raise exception 'CUSTOMER_PROFILE_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.account_deletion_requests (
    store_id,
    customer_id,
    status,
    requested_at,
    updated_at,
    completed_at,
    admin_note
  )
  values (
    p_store_id,
    v_user,
    'requested',
    now(),
    now(),
    null,
    null
  )
  on conflict (store_id, customer_id)
  do update set
    status = case
      when public.account_deletion_requests.status = 'completed'
        then public.account_deletion_requests.status
      else 'requested'
    end,
    requested_at = case
      when public.account_deletion_requests.status = 'completed'
        then public.account_deletion_requests.requested_at
      else now()
    end,
    updated_at = now(),
    completed_at = case
      when public.account_deletion_requests.status = 'completed'
        then public.account_deletion_requests.completed_at
      else null
    end,
    admin_note = case
      when public.account_deletion_requests.status = 'completed'
        then public.account_deletion_requests.admin_note
      else null
    end
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function public.request_account_deletion(uuid) from public, anon;
grant execute on function public.request_account_deletion(uuid) to authenticated;
