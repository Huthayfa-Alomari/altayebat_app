create index if not exists idx_addresses_customer_id on public.addresses(customer_id);
create index if not exists idx_call_requests_assigned_staff_id on public.call_requests(assigned_staff_id);
create index if not exists idx_call_requests_customer_id on public.call_requests(customer_id);
create index if not exists idx_call_requests_order_id on public.call_requests(order_id);
create index if not exists idx_driver_locations_driver_id on public.driver_locations(driver_id);
create index if not exists idx_drivers_store_id on public.drivers(store_id);
create index if not exists idx_order_items_product_id on public.order_items(product_id);
create index if not exists idx_order_status_history_changed_by on public.order_status_history(changed_by);
create index if not exists idx_orders_address_id on public.orders(address_id);
create index if not exists idx_orders_driver_id on public.orders(driver_id);
create index if not exists idx_products_category_id on public.products(category_id);

drop policy if exists "Customers view own order history" on public.order_status_history;
drop policy if exists "Store admins view store order history" on public.order_status_history;
drop policy if exists altayebat_order_status_history_select on public.order_status_history;
create policy altayebat_order_status_history_select
on public.order_status_history for select
to authenticated
using (
  private.owns_order(order_id)
  or private.admin_can_access_order(order_id)
);
