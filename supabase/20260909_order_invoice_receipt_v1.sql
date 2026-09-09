-- Production migration applied by ChatGPT on 2026-09-09.
-- Internal electronic order receipt + future Bonanza/JoFotara invoice linking.

create sequence if not exists public.order_receipt_seq;

create table if not exists public.order_invoices (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  document_number text not null unique,
  document_kind text not null default 'order_receipt'
    check (document_kind in ('order_receipt','tax_invoice')),
  source text not null default 'internal_receipt'
    check (source in ('internal_receipt','bonanza','jofotara')),
  status text not null default 'draft'
    check (status in ('draft','final','linked','void')),
  official boolean not null default false,
  currency text not null default 'JOD',
  issued_at timestamptz,
  subtotal numeric(12,3) not null default 0,
  delivery_fee numeric(12,3) not null default 0,
  discount numeric(12,3) not null default 0,
  tax numeric(12,3),
  total numeric(12,3) not null default 0,
  payment_method text,
  payment_status text,
  customer_name text,
  customer_phone text,
  store_name text,
  store_phone text,
  store_address text,
  address_snapshot jsonb not null default '{}'::jsonb,
  items_snapshot jsonb not null default '[]'::jsonb,
  external_invoice_id text,
  external_invoice_url text,
  external_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists order_invoices_store_created_idx
  on public.order_invoices(store_id,created_at desc);
create index if not exists order_invoices_customer_created_idx
  on public.order_invoices(customer_id,created_at desc);
create index if not exists order_invoices_external_id_idx
  on public.order_invoices(external_invoice_id)
  where external_invoice_id is not null;

alter table public.order_invoices enable row level security;
revoke all on public.order_invoices from anon,authenticated;
grant select,insert,update on public.order_invoices to service_role;
grant usage,select on sequence public.order_receipt_seq to service_role;

create table if not exists public.invoice_share_tokens (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.order_invoices(id) on delete cascade,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists invoice_share_tokens_invoice_idx
  on public.invoice_share_tokens(invoice_id,expires_at desc);

alter table public.invoice_share_tokens enable row level security;
revoke all on public.invoice_share_tokens from anon,authenticated;
grant select,insert,update,delete on public.invoice_share_tokens to service_role;

create or replace function private.order_invoice_json(p_invoice_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=''
as $$
  select jsonb_build_object(
    'id',i.id,
    'order_id',i.order_id,
    'store_id',i.store_id,
    'customer_id',i.customer_id,
    'document_number',i.document_number,
    'document_kind',i.document_kind,
    'source',i.source,
    'status',i.status,
    'official',i.official,
    'currency',i.currency,
    'issued_at',i.issued_at,
    'subtotal',i.subtotal,
    'delivery_fee',i.delivery_fee,
    'discount',i.discount,
    'tax',i.tax,
    'total',i.total,
    'payment_method',i.payment_method,
    'payment_status',i.payment_status,
    'customer_name',i.customer_name,
    'customer_phone',i.customer_phone,
    'store_name',i.store_name,
    'store_phone',i.store_phone,
    'store_address',i.store_address,
    'address',i.address_snapshot,
    'items',i.items_snapshot,
    'external_invoice_id',i.external_invoice_id,
    'external_invoice_url',i.external_invoice_url,
    'created_at',i.created_at,
    'updated_at',i.updated_at
  )
  from public.order_invoices i
  where i.id=p_invoice_id;
$$;

create or replace function private.ensure_order_invoice(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order public.orders%rowtype;
  v_store public.stores%rowtype;
  v_customer public.customers%rowtype;
  v_invoice public.order_invoices%rowtype;
  v_items jsonb;
  v_number text;
begin
  select * into v_order from public.orders where id=p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  select * into v_store from public.stores where id=v_order.store_id;
  select * into v_customer from public.customers where id=v_order.customer_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',oi.id,
    'product_id',oi.product_id,
    'name',oi.product_name,
    'quantity',oi.quantity,
    'unit_price',oi.unit_price,
    'subtotal',oi.subtotal
  ) order by oi.product_name,oi.id),'[]'::jsonb)
  into v_items
  from public.order_items oi
  where oi.order_id=p_order_id;

  select * into v_invoice
  from public.order_invoices
  where order_id=p_order_id
  for update;

  if not found then
    v_number :=
      'ALT-RCP-' ||
      to_char(
        now() at time zone coalesce(v_store.timezone,'Asia/Amman'),
        'YYYYMMDD'
      ) ||
      '-' ||
      lpad(nextval('public.order_receipt_seq')::text,6,'0');

    insert into public.order_invoices(
      order_id,store_id,customer_id,document_number,document_kind,
      source,status,official,currency,issued_at,
      subtotal,delivery_fee,discount,tax,total,
      payment_method,payment_status,
      customer_name,customer_phone,
      store_name,store_phone,store_address,
      address_snapshot,items_snapshot
    ) values(
      v_order.id,v_order.store_id,v_order.customer_id,v_number,
      'order_receipt','internal_receipt',
      case when v_order.status='delivered' then 'final' else 'draft' end,
      false,
      coalesce(v_store.currency,'JOD'),
      case
        when v_order.status='delivered'
          then coalesce(v_order.updated_at,now())
        else null
      end,
      coalesce(v_order.subtotal,0),
      coalesce(v_order.delivery_fee,0),
      coalesce(v_order.discount,0),
      null,
      coalesce(v_order.total,0),
      v_order.payment_method,
      v_order.payment_status,
      v_customer.name,
      v_customer.phone,
      v_store.name,
      v_store.phone,
      v_store.address,
      coalesce(v_order.address_snapshot,'{}'::jsonb),
      v_items
    )
    returning * into v_invoice;
  elsif v_invoice.source='internal_receipt' and v_invoice.official=false then
    update public.order_invoices
    set
      status=case when v_order.status='delivered' then 'final' else status end,
      issued_at=case
        when v_order.status='delivered'
          then coalesce(issued_at,v_order.updated_at,now())
        else issued_at
      end,
      currency=coalesce(v_store.currency,currency),
      subtotal=coalesce(v_order.subtotal,0),
      delivery_fee=coalesce(v_order.delivery_fee,0),
      discount=coalesce(v_order.discount,0),
      total=coalesce(v_order.total,0),
      payment_method=v_order.payment_method,
      payment_status=v_order.payment_status,
      customer_name=coalesce(v_customer.name,customer_name),
      customer_phone=coalesce(v_customer.phone,customer_phone),
      store_name=coalesce(v_store.name,store_name),
      store_phone=coalesce(v_store.phone,store_phone),
      store_address=coalesce(v_store.address,store_address),
      address_snapshot=coalesce(v_order.address_snapshot,address_snapshot),
      items_snapshot=v_items,
      updated_at=now()
    where id=v_invoice.id
    returning * into v_invoice;
  end if;

  return v_invoice.id;
end;
$$;

create or replace function public.get_order_invoice(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order record;
  v_invoice_id uuid;
begin
  select id,customer_id
  into v_order
  from public.orders
  where id=p_order_id;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  if auth.uid() is null or auth.uid()<>v_order.customer_id then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  v_invoice_id:=private.ensure_order_invoice(p_order_id);
  return private.order_invoice_json(v_invoice_id);
end;
$$;

create or replace function public.admin_get_order_invoice(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order record;
  v_invoice_id uuid;
begin
  select id,store_id
  into v_order
  from public.orders
  where id=p_order_id;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  if not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  v_invoice_id:=private.ensure_order_invoice(p_order_id);
  return private.order_invoice_json(v_invoice_id);
end;
$$;

create or replace function public.admin_list_order_invoice_rows(
  p_store_id uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if not private.is_store_admin(p_store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  return (
    select coalesce(
      jsonb_agg(to_jsonb(x) order by x.created_at desc),
      '[]'::jsonb
    )
    from (
      select
        o.id order_id,
        o.status order_status,
        o.total,
        o.payment_method,
        o.payment_status,
        o.created_at,
        c.name customer_name,
        c.phone customer_phone,
        i.document_number,
        i.status invoice_status,
        i.source,
        i.official,
        i.external_invoice_id,
        i.issued_at
      from public.orders o
      left join public.customers c on c.id=o.customer_id
      left join public.order_invoices i on i.order_id=o.id
      where o.store_id=p_store_id
      order by o.created_at desc
      limit greatest(1,least(coalesce(p_limit,50),200))
    ) x
  );
end;
$$;

create or replace function public.admin_issue_invoice_share(
  p_order_id uuid,
  p_hours integer default 168
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order record;
  v_invoice_id uuid;
  v_token text;
begin
  select id,store_id
  into v_order
  from public.orders
  where id=p_order_id;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  if not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  v_invoice_id:=private.ensure_order_invoice(p_order_id);
  v_token:=encode(extensions.gen_random_bytes(32),'hex');

  insert into public.invoice_share_tokens(
    invoice_id,token_hash,expires_at,created_by
  ) values(
    v_invoice_id,
    extensions.digest(v_token,'sha256'),
    now()+make_interval(
      hours=>greatest(1,least(coalesce(p_hours,168),720))
    ),
    auth.uid()
  );

  return v_token;
end;
$$;

create or replace function public.get_shared_order_invoice(p_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_invoice_id uuid;
begin
  if p_token is null or length(trim(p_token))<32 then
    raise exception 'INVALID_TOKEN' using errcode='42501';
  end if;

  select t.invoice_id
  into v_invoice_id
  from public.invoice_share_tokens t
  where t.token_hash=extensions.digest(trim(p_token),'sha256')
    and t.revoked_at is null
    and t.expires_at>now()
  order by t.created_at desc
  limit 1;

  if v_invoice_id is null then
    raise exception 'INVALID_OR_EXPIRED_TOKEN' using errcode='42501';
  end if;

  return private.order_invoice_json(v_invoice_id);
end;
$$;

create or replace function public.admin_link_external_invoice(
  p_order_id uuid,
  p_source text,
  p_external_invoice_id text,
  p_external_invoice_url text default null,
  p_official boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_order record;
  v_invoice_id uuid;
  v_source text:=lower(trim(coalesce(p_source,'')));
begin
  select id,store_id
  into v_order
  from public.orders
  where id=p_order_id;

  if not found then
    raise exception 'ORDER_NOT_FOUND' using errcode='P0002';
  end if;

  if not private.is_store_admin(v_order.store_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if v_source not in ('bonanza','jofotara') then
    raise exception 'INVALID_SOURCE' using errcode='22023';
  end if;

  if nullif(trim(coalesce(p_external_invoice_id,'')),'') is null then
    raise exception 'EXTERNAL_INVOICE_ID_REQUIRED' using errcode='22023';
  end if;

  v_invoice_id:=private.ensure_order_invoice(p_order_id);

  update public.order_invoices
  set
    source=v_source,
    document_kind=case
      when p_official then 'tax_invoice'
      else document_kind
    end,
    status='linked',
    official=p_official,
    external_invoice_id=trim(p_external_invoice_id),
    external_invoice_url=nullif(
      trim(coalesce(p_external_invoice_url,'')),
      ''
    ),
    issued_at=coalesce(issued_at,now()),
    updated_at=now()
  where id=v_invoice_id;

  return private.order_invoice_json(v_invoice_id);
end;
$$;

create or replace function private.trg_finalize_order_invoice()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='delivered' and old.status is distinct from new.status then
    perform private.ensure_order_invoice(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_finalize_order_invoice on public.orders;

create trigger trg_finalize_order_invoice
after update of status on public.orders
for each row
when (
  new.status='delivered' and
  old.status is distinct from new.status
)
execute function private.trg_finalize_order_invoice();

revoke all on function public.get_order_invoice(uuid)
  from public,anon,authenticated;
revoke all on function public.admin_get_order_invoice(uuid)
  from public,anon,authenticated;
revoke all on function public.admin_list_order_invoice_rows(uuid,integer)
  from public,anon,authenticated;
revoke all on function public.admin_issue_invoice_share(uuid,integer)
  from public,anon,authenticated;
revoke all on function public.get_shared_order_invoice(text)
  from public,anon,authenticated;
revoke all on function public.admin_link_external_invoice(
  uuid,text,text,text,boolean
) from public,anon,authenticated;

grant execute on function public.get_order_invoice(uuid)
  to authenticated;
grant execute on function public.admin_get_order_invoice(uuid)
  to authenticated;
grant execute on function public.admin_list_order_invoice_rows(uuid,integer)
  to authenticated;
grant execute on function public.admin_issue_invoice_share(uuid,integer)
  to authenticated;
grant execute on function public.admin_link_external_invoice(
  uuid,text,text,text,boolean
) to authenticated;
grant execute on function public.get_shared_order_invoice(text)
  to anon,authenticated;
