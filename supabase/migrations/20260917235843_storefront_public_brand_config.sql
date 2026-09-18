
create or replace function public.get_storefront_public_config(p_store_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when s.id is null or not coalesce(s.is_active,false) then null
    else jsonb_build_object(
      'store_id', s.id,
      'store_name', s.name,
      'logo_url', s.logo_url,
      'primary_color', s.primary_color,
      'phone', s.phone,
      'address', s.address,
      'currency', s.currency,
      'delivery_fee', s.delivery_fee,
      'min_order', s.min_order,
      'accepts_orders', s.accepts_orders,
      'prep_time_min_minutes', s.prep_time_min_minutes,
      'prep_time_max_minutes', s.prep_time_max_minutes
    ) || coalesce(to_jsonb(ps) - 'store_id' - 'updated_by', '{}'::jsonb)
  end
  from public.stores s
  left join public.store_public_settings ps on ps.store_id=s.id
  where s.id=p_store_id
  limit 1;
$function$;

revoke all on function public.get_storefront_public_config(uuid) from public;
grant execute on function public.get_storefront_public_config(uuid) to anon, authenticated, service_role;

create or replace function public.admin_store_engagement_summary(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_social jsonb;
  v_referrals jsonb;
begin
  if auth.uid() is null or not private.is_store_admin(p_store_id) then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;

  select jsonb_build_object(
    'facebook_clicks', count(*) filter (where event_name='social_click' and entity_id='facebook'),
    'instagram_clicks', count(*) filter (where event_name='social_click' and entity_id='instagram'),
    'whatsapp_clicks', count(*) filter (where event_name='social_click' and entity_id='whatsapp'),
    'tiktok_clicks', count(*) filter (where event_name='social_click' and entity_id='tiktok'),
    'maps_clicks', count(*) filter (where event_name='social_click' and entity_id='google_maps'),
    'website_clicks', count(*) filter (where event_name='social_click' and entity_id='website'),
    'support_clicks', count(*) filter (where event_name='support_click'),
    'app_shares', count(*) filter (where event_name='app_share'),
    'referral_shares', count(*) filter (where event_name='referral_share')
  ) into v_social
  from public.app_events
  where store_id=p_store_id;

  select jsonb_build_object(
    'total',count(*),
    'pending',count(*) filter(where status='pending'),
    'rewarded',count(*) filter(where status='rewarded'),
    'rejected',count(*) filter(where status='rejected')
  ) into v_referrals
  from public.referrals
  where store_id=p_store_id;

  return jsonb_build_object(
    'social',coalesce(v_social,'{}'::jsonb),
    'referrals',coalesce(v_referrals,'{}'::jsonb)
  );
end;
$function$;

revoke all on function public.admin_store_engagement_summary(uuid) from public, anon;
grant execute on function public.admin_store_engagement_summary(uuid) to authenticated, service_role;
