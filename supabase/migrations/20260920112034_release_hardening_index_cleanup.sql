drop index if exists public.idx_ai_basket_customer_created;

create index if not exists idx_account_deletion_requests_customer
  on public.account_deletion_requests(customer_id);
