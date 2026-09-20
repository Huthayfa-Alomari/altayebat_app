create or replace function public.n8n_run_daily_sales_report(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_tz text;
  v_date date;
  v_start timestamptz;
  v_end timestamptz;
  v_payload jsonb;
  v_report_id bigint;
begin
  select coalesce(timezone,'Asia/Amman') into v_tz from public.store_automation_config where store_id=p_store_id;
  v_tz := coalesce(v_tz,'Asia/Amman');
  v_date := (now() at time zone v_tz)::date;
  v_start := v_date::timestamp at time zone v_tz;
  v_end := (v_date + 1)::timestamp at time zone v_tz;

  v_payload := public.get_daily_report_payload(p_store_id,v_date);
  v_report_id := public.n8n_save_report(p_store_id,'daily_sales',v_start,v_end,v_payload);

  return jsonb_build_object('ok',true,'report_id',v_report_id,'report_type','daily_sales','payload',v_payload);
end;
$$;

create or replace function public.n8n_run_low_stock_monitor(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_payload jsonb; v_item jsonb; v_count integer:=0; v_id bigint;
begin
  v_payload := public.n8n_low_stock_payload(p_store_id);

  update public.ops_alerts set status='resolved',resolved_at=now(),updated_at=now()
  where store_id=p_store_id and alert_type='low_stock' and status<>'resolved';

  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb)) loop
    v_id := public.n8n_upsert_ops_alert(
      p_store_id,
      'low_stock',
      case when coalesce((v_item->>'stock_qty')::integer,0)<=0 then 'critical' else 'warning' end,
      case when coalesce((v_item->>'stock_qty')::integer,0)<=0 then 'نفد من المخزون' else 'مخزون منخفض' end,
      format('%s — الكمية %s، حد التنبيه %s',v_item->>'name',coalesce(v_item->>'stock_qty','0'),coalesce(v_item->>'threshold','5')),
      'product',v_item->>'product_id','low-stock:'||(v_item->>'product_id'),v_item
    );
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'alerts_opened',v_count,'payload',v_payload);
end;
$$;

create or replace function public.n8n_run_delayed_orders_monitor(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_payload jsonb; v_item jsonb; v_count integer:=0; v_minutes numeric;
begin
  v_payload := public.n8n_delayed_orders_payload(p_store_id);

  update public.ops_alerts set status='resolved',resolved_at=now(),updated_at=now()
  where store_id=p_store_id and alert_type='order_delayed' and status<>'resolved';

  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb)) loop
    v_minutes := coalesce((v_item->>'minutes_in_status')::numeric,0);
    perform public.n8n_upsert_ops_alert(
      p_store_id,'order_delayed',case when v_minutes>=60 then 'critical' else 'warning' end,
      'طلب متأخر',
      format('الطلب #%s ما زال %s منذ %s دقيقة',upper(left(v_item->>'order_id',8)),v_item->>'status',round(v_minutes,0)),
      'order',v_item->>'order_id','order-delay:'||(v_item->>'order_id')||':'||(v_item->>'status'),v_item
    );
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'alerts_opened',v_count,'payload',v_payload);
end;
$$;

create or replace function public.n8n_run_delivery_monitor(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_payload jsonb; v_item jsonb; v_count integer:=0; v_stale boolean; v_late boolean; v_missing boolean;
begin
  v_payload := public.n8n_delivery_health_payload(p_store_id);

  update public.ops_alerts set status='resolved',resolved_at=now(),updated_at=now()
  where store_id=p_store_id and alert_type in ('delivery_gps_stale','delivery_late') and status<>'resolved';

  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb)) loop
    v_stale := coalesce((v_item->>'stale_gps')::boolean,false);
    v_late := coalesce((v_item->>'late_delivery')::boolean,false);
    v_missing := coalesce((v_item->>'missing_gps')::boolean,false);

    if v_stale then
      perform public.n8n_upsert_ops_alert(
        p_store_id,'delivery_gps_stale',case when v_missing then 'critical' else 'warning' end,
        case when v_missing then 'لا يوجد GPS للمندوب' else 'تحديث GPS متوقف' end,
        format('الطلب #%s — المندوب %s',upper(left(v_item->>'order_id',8)),coalesce(v_item->>'driver_name','غير محدد')),
        'order',v_item->>'order_id','delivery-gps:'||(v_item->>'order_id'),v_item
      );
      v_count:=v_count+1;
    end if;

    if v_late then
      perform public.n8n_upsert_ops_alert(
        p_store_id,'delivery_late','critical','توصيل متأخر',
        format('الطلب #%s في التوصيل منذ %s دقيقة',upper(left(v_item->>'order_id',8)),coalesce(v_item->>'delivery_minutes','0')),
        'order',v_item->>'order_id','delivery-late:'||(v_item->>'order_id'),v_item
      );
      v_count:=v_count+1;
    end if;
  end loop;

  return jsonb_build_object('ok',true,'alerts_opened',v_count,'payload',v_payload);
end;
$$;

create or replace function public.n8n_run_product_intelligence_report(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_days integer; v_payload jsonb; v_end timestamptz:=now(); v_start timestamptz; v_report_id bigint;
begin
  select coalesce(product_report_days,30) into v_days from public.store_automation_config where store_id=p_store_id;
  v_days:=coalesce(v_days,30);
  v_start:=v_end-make_interval(days=>v_days);
  v_payload:=public.n8n_product_intelligence_payload(p_store_id,v_days);
  v_report_id:=public.n8n_save_report(p_store_id,'product_intelligence',v_start,v_end,v_payload);
  return jsonb_build_object('ok',true,'report_id',v_report_id,'report_type','product_intelligence','payload',v_payload);
end;
$$;

create or replace function public.n8n_run_payment_reconciliation_monitor(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_payload jsonb; v_item jsonb; v_count integer:=0; v_reason text;
begin
  v_payload:=public.n8n_payment_reconciliation_payload(p_store_id);

  update public.ops_alerts set status='resolved',resolved_at=now(),updated_at=now()
  where store_id=p_store_id and alert_type='payment_review' and status<>'resolved';

  for v_item in select value from jsonb_array_elements(coalesce(v_payload->'items','[]'::jsonb)) loop
    v_reason:=v_item->>'reason';
    perform public.n8n_upsert_ops_alert(
      p_store_id,'payment_review',case when v_reason='PAID_WITHOUT_REFERENCE' then 'critical' else 'warning' end,
      'دفعة تحتاج مراجعة',
      format('الطلب #%s — %s — %s',upper(left(v_item->>'order_id',8)),coalesce(v_item->>'payment_method',''),coalesce(v_reason,'')),
      'order',v_item->>'order_id','payment-review:'||(v_item->>'order_id'),v_item
    );
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'alerts_opened',v_count,'payload',v_payload);
end;
$$;

create or replace function public.n8n_run_operational_event_logger(p_store_id uuid,p_limit integer default 50)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare r public.automation_events%rowtype; v_count integer:=0; v_log_id bigint;
begin
  for r in
    select * from public.claim_automation_events_by_type(
      array['order.created','order.status_changed','order.delayed','report.daily_due','product.stock_low','call.escalated'],
      greatest(1,least(coalesce(p_limit,50),100)),
      'n8n-operational-logger'
    )
  loop
    if r.store_id<>p_store_id then
      perform public.complete_automation_event(r.id,false,'Wrong store claimed',300);
      continue;
    end if;

    v_log_id:=public.log_automation_delivery(
      r.id,'internal',true,null,null,
      jsonb_build_object('workflow','operational_event_logger','event_type',r.event_type,'aggregate_type',r.aggregate_type,'aggregate_id',r.aggregate_id,'payload',r.payload)
    );
    perform public.complete_automation_event(r.id,true,null,null);
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'events_processed',v_count);
end;
$$;

create or replace function public.n8n_run_weekly_management_report(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_payload jsonb; v_start timestamptz; v_end timestamptz; v_report_id bigint;
begin
  v_payload:=public.n8n_weekly_management_payload(p_store_id);
  v_start:=(v_payload->>'period_start')::timestamptz;
  v_end:=(v_payload->>'period_end')::timestamptz;
  v_report_id:=public.n8n_save_report(p_store_id,'weekly_management',v_start,v_end,v_payload);
  return jsonb_build_object('ok',true,'report_id',v_report_id,'report_type','weekly_management','payload',v_payload);
end;
$$;

revoke all on function public.n8n_run_daily_sales_report(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_low_stock_monitor(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_delayed_orders_monitor(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_delivery_monitor(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_product_intelligence_report(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_payment_reconciliation_monitor(uuid) from public,anon,authenticated;
revoke all on function public.n8n_run_operational_event_logger(uuid,integer) from public,anon,authenticated;
revoke all on function public.n8n_run_weekly_management_report(uuid) from public,anon,authenticated;

grant execute on function public.n8n_run_daily_sales_report(uuid) to service_role;
grant execute on function public.n8n_run_low_stock_monitor(uuid) to service_role;
grant execute on function public.n8n_run_delayed_orders_monitor(uuid) to service_role;
grant execute on function public.n8n_run_delivery_monitor(uuid) to service_role;
grant execute on function public.n8n_run_product_intelligence_report(uuid) to service_role;
grant execute on function public.n8n_run_payment_reconciliation_monitor(uuid) to service_role;
grant execute on function public.n8n_run_operational_event_logger(uuid,integer) to service_role;
grant execute on function public.n8n_run_weekly_management_report(uuid) to service_role;
