create or replace function public.admin_assign_delivery_driver(p_order_id uuid,p_driver_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_order record; v_driver record;
begin
 select o.id,o.store_id,o.status,o.driver_id into v_order from public.orders o where o.id=p_order_id;
 if not found or not private.is_store_admin(v_order.store_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_order.status in ('delivered','cancelled') then raise exception 'ORDER_CLOSED' using errcode='22023'; end if;
 select d.id,d.name,d.phone,d.is_active,d.approval_status into v_driver from public.drivers d where d.id=p_driver_id and d.store_id=v_order.store_id;
 if not found or not coalesce(v_driver.is_active,false) or v_driver.approval_status<>'approved' then raise exception 'DRIVER_UNAVAILABLE' using errcode='22023'; end if;
 if v_order.driver_id is distinct from p_driver_id then update public.driver_tracking_sessions set revoked_at=coalesce(revoked_at,now()) where order_id=p_order_id and revoked_at is null; end if;
 update public.orders set driver_id=p_driver_id,updated_at=now() where id=p_order_id;
 return jsonb_build_object('ok',true,'order_id',p_order_id,'driver_id',v_driver.id,'driver_name',v_driver.name,'driver_phone',v_driver.phone);
end;$$;

create or replace function public.admin_issue_driver_tracking_session(p_order_id uuid,p_driver_id uuid default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_order record; v_driver record; v_driver_id uuid; v_token text; v_expires_at timestamptz:=now()+interval '18 hours';
begin
 select o.id,o.store_id,o.status,o.driver_id into v_order from public.orders o where o.id=p_order_id;
 if not found or not private.is_store_admin(v_order.store_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_order.status in ('delivered','cancelled') then raise exception 'ORDER_CLOSED' using errcode='22023'; end if;
 v_driver_id:=coalesce(p_driver_id,v_order.driver_id);
 if v_driver_id is null then raise exception 'DRIVER_REQUIRED' using errcode='22023'; end if;
 select d.id,d.name,d.phone,d.is_active,d.approval_status into v_driver from public.drivers d where d.id=v_driver_id and d.store_id=v_order.store_id;
 if not found or not coalesce(v_driver.is_active,false) or v_driver.approval_status<>'approved' then raise exception 'DRIVER_UNAVAILABLE' using errcode='22023'; end if;
 update public.orders set driver_id=v_driver_id,updated_at=now() where id=p_order_id;
 update public.driver_tracking_sessions set revoked_at=coalesce(revoked_at,now()) where order_id=p_order_id and revoked_at is null;
 v_token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.driver_tracking_sessions(store_id,order_id,driver_id,token_hash,created_by,expires_at)
 values(v_order.store_id,p_order_id,v_driver_id,extensions.digest(lower(v_token),'sha256'),auth.uid(),v_expires_at);
 return jsonb_build_object('ok',true,'token',v_token,'expires_at',v_expires_at,'order_id',p_order_id,'driver_id',v_driver.id,'driver_name',v_driver.name,'driver_phone',v_driver.phone,'app_uri','altayebat://driver?token='||v_token,'web_path','/driver?token='||v_token);
end;$$;

create or replace function public.admin_set_delivery_driver_active(p_driver_id uuid,p_active boolean)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_store_id uuid; v_approval_status text;
begin
 select d.store_id,d.approval_status into v_store_id,v_approval_status from public.drivers d where d.id=p_driver_id;
 if v_store_id is null or not private.is_store_admin(v_store_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if coalesce(p_active,false) and v_approval_status<>'approved' then raise exception 'RIDER_NOT_APPROVED' using errcode='22023'; end if;
 update public.drivers set is_active=coalesce(p_active,false),availability_status=case when coalesce(p_active,false) then availability_status else 'offline' end,status_updated_at=now() where id=p_driver_id;
 if not coalesce(p_active,false) then update public.driver_tracking_sessions set revoked_at=coalesce(revoked_at,now()) where driver_id=p_driver_id and revoked_at is null; end if;
 return true;
end;$$;

revoke all on function public.admin_assign_delivery_driver(uuid,uuid) from public, anon;
revoke all on function public.admin_issue_driver_tracking_session(uuid,uuid) from public, anon;
revoke all on function public.admin_set_delivery_driver_active(uuid,boolean) from public, anon;
grant execute on function public.admin_assign_delivery_driver(uuid,uuid) to authenticated;
grant execute on function public.admin_issue_driver_tracking_session(uuid,uuid) to authenticated;
grant execute on function public.admin_set_delivery_driver_active(uuid,boolean) to authenticated;
