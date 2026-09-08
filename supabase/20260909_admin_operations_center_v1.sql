-- Production migration already applied on 2026-09-09.
-- Admin Operations Center + Supabase pg_cron orchestration.
-- Depends on the existing automation/report runner functions already present in production.

create or replace function private.run_ops_low_stock()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled loop
    perform public.n8n_run_low_stock_monitor(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_delayed_orders()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled loop
    perform public.n8n_run_delayed_orders_monitor(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_delivery()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled loop
    perform public.n8n_run_delivery_monitor(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_payments()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled loop
    perform public.n8n_run_payment_reconciliation_monitor(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_daily_report()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled and daily_report_enabled loop
    perform public.n8n_run_daily_sales_report(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_product_report()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled loop
    perform public.n8n_run_product_intelligence_report(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_weekly_report()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$ declare r record; begin
  for r in select store_id from public.store_automation_config where enabled and coalesce(weekly_report_enabled,true) loop
    perform public.n8n_run_weekly_management_report(r.store_id);
  end loop;
end; $$;

create or replace function private.run_ops_event_logger()
returns void language plpgsql security definer set search_path='public','private','pg_temp'
as $$
declare r public.automation_events%rowtype;
begin
  for r in
    select * from public.claim_automation_events_by_type(
      array['order.created','order.status_changed','order.delayed','report.daily_due','product.stock_low','call.escalated'],
      100,'supabase-ops-logger'
    )
  loop
    perform public.log_automation_delivery(
      r.id,'internal',true,null,null,
      jsonb_build_object(
        'processor','supabase-cron','event_type',r.event_type,
        'aggregate_type',r.aggregate_type,'aggregate_id',r.aggregate_id,'payload',r.payload
      )
    );
    perform public.complete_automation_event(r.id,true,null,null);
  end loop;
end; $$;

create or replace function public.admin_get_ops_dashboard(p_store_id uuid)
returns jsonb language plpgsql security definer set search_path='public','private','pg_temp'
as $$
declare
  v_config jsonb; v_alerts jsonb; v_reports jsonb; v_today jsonb;
  v_low_stock jsonb; v_delayed jsonb; v_delivery jsonb; v_payments jsonb;
  v_open_count integer;
begin
  if not private.is_store_admin(p_store_id) then raise exception 'FORBIDDEN'; end if;

  select to_jsonb(c) into v_config from public.store_automation_config c where c.store_id=p_store_id;

  select coalesce(jsonb_agg(to_jsonb(a) order by
    case a.severity when 'critical' then 1 when 'warning' then 2 else 3 end,
    a.created_at desc),'[]'::jsonb), count(*)::int
  into v_alerts,v_open_count
  from public.ops_alerts a
  where a.store_id=p_store_id and a.status in ('open','acknowledged');

  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_reports
  from (
    select r.id,r.report_type,r.period_start,r.period_end,r.summary,r.created_at,r.updated_at
    from public.automation_reports r
    where r.store_id=p_store_id
    order by r.created_at desc limit 20
  ) x;

  v_today := public.get_daily_report_payload(
    p_store_id,(now() at time zone coalesce(v_config->>'timezone','Asia/Amman'))::date
  );
  v_low_stock := public.n8n_low_stock_payload(p_store_id);
  v_delayed := public.n8n_delayed_orders_payload(p_store_id);
  v_delivery := public.n8n_delivery_health_payload(p_store_id);
  v_payments := public.n8n_payment_reconciliation_payload(p_store_id);

  return jsonb_build_object(
    'store_id',p_store_id,'generated_at',now(),'open_alert_count',coalesce(v_open_count,0),
    'config',coalesce(v_config,'{}'::jsonb),'alerts',coalesce(v_alerts,'[]'::jsonb),
    'reports',coalesce(v_reports,'[]'::jsonb),'today',coalesce(v_today,'{}'::jsonb),
    'low_stock',coalesce(v_low_stock,'{}'::jsonb),'delayed_orders',coalesce(v_delayed,'{}'::jsonb),
    'delivery',coalesce(v_delivery,'{}'::jsonb),'payments',coalesce(v_payments,'{}'::jsonb)
  );
end; $$;

create or replace function public.admin_update_ops_config(
  p_store_id uuid,
  p_low_stock_threshold integer,
  p_order_pending_alert_minutes integer,
  p_order_preparing_alert_minutes integer,
  p_delivery_gps_stale_seconds integer,
  p_delivery_late_grace_minutes integer,
  p_payment_pending_alert_minutes integer,
  p_product_report_days integer
) returns jsonb language plpgsql security definer set search_path='public','private','pg_temp'
as $$
begin
  if not private.is_store_admin(p_store_id) then raise exception 'FORBIDDEN'; end if;
  if p_low_stock_threshold < 0 or p_low_stock_threshold > 100000 then raise exception 'INVALID_LOW_STOCK_THRESHOLD'; end if;
  if p_order_pending_alert_minutes < 1 or p_order_pending_alert_minutes > 1440 then raise exception 'INVALID_PENDING_MINUTES'; end if;
  if p_order_preparing_alert_minutes < 1 or p_order_preparing_alert_minutes > 1440 then raise exception 'INVALID_PREPARING_MINUTES'; end if;
  if p_delivery_gps_stale_seconds < 30 or p_delivery_gps_stale_seconds > 3600 then raise exception 'INVALID_GPS_STALE_SECONDS'; end if;
  if p_delivery_late_grace_minutes < 0 or p_delivery_late_grace_minutes > 240 then raise exception 'INVALID_DELIVERY_GRACE'; end if;
  if p_payment_pending_alert_minutes < 1 or p_payment_pending_alert_minutes > 1440 then raise exception 'INVALID_PAYMENT_PENDING_MINUTES'; end if;
  if p_product_report_days < 1 or p_product_report_days > 365 then raise exception 'INVALID_PRODUCT_REPORT_DAYS'; end if;

  update public.store_automation_config set
    enabled=true,
    low_stock_threshold=p_low_stock_threshold,
    order_pending_alert_minutes=p_order_pending_alert_minutes,
    order_preparing_alert_minutes=p_order_preparing_alert_minutes,
    delivery_gps_stale_seconds=p_delivery_gps_stale_seconds,
    delivery_late_grace_minutes=p_delivery_late_grace_minutes,
    payment_pending_alert_minutes=p_payment_pending_alert_minutes,
    product_report_days=p_product_report_days,
    whatsapp_enabled=false,telegram_enabled=false,reengagement_enabled=false,updated_at=now()
  where store_id=p_store_id;

  return (select to_jsonb(c) from public.store_automation_config c where c.store_id=p_store_id);
end; $$;

create or replace function public.admin_set_ops_alert_status(p_alert_id bigint,p_status text)
returns jsonb language plpgsql security definer set search_path='public','private','pg_temp'
as $$
declare v_store_id uuid; v_result jsonb;
begin
  if p_status not in ('acknowledged','resolved') then raise exception 'INVALID_STATUS'; end if;
  select store_id into v_store_id from public.ops_alerts where id=p_alert_id;
  if v_store_id is null then raise exception 'ALERT_NOT_FOUND'; end if;
  if not private.is_store_admin(v_store_id) then raise exception 'FORBIDDEN'; end if;

  update public.ops_alerts set
    status=p_status,
    resolved_at=case when p_status='resolved' then now() else null end,
    updated_at=now()
  where id=p_alert_id
  returning to_jsonb(ops_alerts.*) into v_result;
  return v_result;
end; $$;

create or replace function public.admin_run_ops_check(p_store_id uuid,p_check text default 'all')
returns jsonb language plpgsql security definer set search_path='public','private','pg_temp'
as $$
declare v_result jsonb := '{}'::jsonb;
begin
  if not private.is_store_admin(p_store_id) then raise exception 'FORBIDDEN'; end if;

  if p_check in ('all','low_stock') then
    v_result := v_result || jsonb_build_object('low_stock',public.n8n_run_low_stock_monitor(p_store_id));
  end if;
  if p_check in ('all','delayed_orders') then
    v_result := v_result || jsonb_build_object('delayed_orders',public.n8n_run_delayed_orders_monitor(p_store_id));
  end if;
  if p_check in ('all','delivery') then
    v_result := v_result || jsonb_build_object('delivery',public.n8n_run_delivery_monitor(p_store_id));
  end if;
  if p_check in ('all','payments') then
    v_result := v_result || jsonb_build_object('payments',public.n8n_run_payment_reconciliation_monitor(p_store_id));
  end if;
  if p_check='daily_report' then
    v_result := v_result || jsonb_build_object('daily_report',public.n8n_run_daily_sales_report(p_store_id));
  end if;
  if p_check='product_report' then
    v_result := v_result || jsonb_build_object('product_report',public.n8n_run_product_intelligence_report(p_store_id));
  end if;
  if p_check='weekly_report' then
    v_result := v_result || jsonb_build_object('weekly_report',public.n8n_run_weekly_management_report(p_store_id));
  end if;

  if p_check not in ('all','low_stock','delayed_orders','delivery','payments','daily_report','product_report','weekly_report') then
    raise exception 'INVALID_CHECK';
  end if;

  return jsonb_build_object('ok',true,'check',p_check,'result',v_result,'ran_at',now());
end; $$;

revoke all on function public.admin_get_ops_dashboard(uuid) from public,anon;
revoke all on function public.admin_update_ops_config(uuid,integer,integer,integer,integer,integer,integer,integer) from public,anon;
revoke all on function public.admin_set_ops_alert_status(bigint,text) from public,anon;
revoke all on function public.admin_run_ops_check(uuid,text) from public,anon;

grant execute on function public.admin_get_ops_dashboard(uuid) to authenticated;
grant execute on function public.admin_update_ops_config(uuid,integer,integer,integer,integer,integer,integer,integer) to authenticated;
grant execute on function public.admin_set_ops_alert_status(bigint,text) to authenticated;
grant execute on function public.admin_run_ops_check(uuid,text) to authenticated;

do $$ declare r record; begin
  for r in select jobid from cron.job where jobname in (
    'altayebat-ops-low-stock','altayebat-ops-delayed-orders','altayebat-ops-delivery',
    'altayebat-ops-payments','altayebat-ops-daily-report','altayebat-ops-product-report',
    'altayebat-ops-weekly-report','altayebat-ops-event-logger'
  ) loop perform cron.unschedule(r.jobid); end loop;
end $$;

select cron.schedule('altayebat-ops-event-logger','* * * * *','select private.run_ops_event_logger();');
select cron.schedule('altayebat-ops-delivery','*/2 * * * *','select private.run_ops_delivery();');
select cron.schedule('altayebat-ops-delayed-orders','*/5 * * * *','select private.run_ops_delayed_orders();');
select cron.schedule('altayebat-ops-payments','*/10 * * * *','select private.run_ops_payments();');
select cron.schedule('altayebat-ops-low-stock','*/30 * * * *','select private.run_ops_low_stock();');
select cron.schedule('altayebat-ops-product-report','15 4 * * *','select private.run_ops_product_report();');
select cron.schedule('altayebat-ops-daily-report','35 20 * * *','select private.run_ops_daily_report();');
select cron.schedule('altayebat-ops-weekly-report','45 20 * * 6','select private.run_ops_weekly_report();');
