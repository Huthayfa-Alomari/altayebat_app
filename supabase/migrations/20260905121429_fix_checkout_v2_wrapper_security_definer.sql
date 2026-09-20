create or replace function public.create_order_checkout_v2(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash'::text,
  p_customer_note text default null::text,
  p_substitute_policy text default 'call_me'::text
)
returns uuid
language sql
security definer
set search_path to ''
as $function$
  select private.create_order_checkout_v2_atomic(
    p_store_id,
    p_items,
    p_address_id,
    p_payment_method,
    p_customer_note,
    p_substitute_policy
  );
$function$;

revoke all on function public.create_order_checkout_v2(uuid,jsonb,uuid,text,text,text) from public;
revoke all on function public.create_order_checkout_v2(uuid,jsonb,uuid,text,text,text) from anon;
grant execute on function public.create_order_checkout_v2(uuid,jsonb,uuid,text,text,text) to authenticated;
