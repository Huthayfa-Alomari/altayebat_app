alter table public.orders add column if not exists payment_reference text;
alter table public.stores add column if not exists cliq_alias text;
alter table public.stores add column if not exists cliq_recipient_name text;
create index if not exists idx_orders_payment_reference on public.orders(payment_reference) where payment_reference is not null;
