grant update on public.account_deletion_requests to authenticated;

create policy account_deletion_requests_admin_select
on public.account_deletion_requests for select
to authenticated
using (private.is_store_admin(store_id));

create policy account_deletion_requests_admin_update
on public.account_deletion_requests for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

create or replace function public.admin_set_account_deletion_status(
  p_request_id uuid,
  p_status text,
  p_admin_note text default null
)
returns public.account_deletion_requests
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.account_deletion_requests;
begin
  if p_status not in ('processing','completed','rejected','cancelled') then
    raise exception 'INVALID_STATUS' using errcode='22023';
  end if;

  select *
    into v_row
  from public.account_deletion_requests r
  where r.id=p_request_id
  for update;

  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode='P0001';
  end if;

  if not private.is_store_admin(v_row.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  update public.account_deletion_requests
  set status=p_status,
      admin_note=nullif(btrim(p_admin_note),''),
      completed_at=case when p_status='completed' then now() else null end,
      updated_at=now()
  where id=p_request_id
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.admin_set_account_deletion_status(uuid,text,text)
from public,anon;
grant execute on function public.admin_set_account_deletion_status(uuid,text,text)
to authenticated;

