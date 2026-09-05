alter function public.create_order_checkout_v2(
  uuid,
  jsonb,
  uuid,
  text,
  text,
  text
) security definer;

revoke all on function public.create_order_checkout_v2(
  uuid,
  jsonb,
  uuid,
  text,
  text,
  text
) from anon;

grant execute on function public.create_order_checkout_v2(
  uuid,
  jsonb,
  uuid,
  text,
  text,
  text
) to authenticated;
