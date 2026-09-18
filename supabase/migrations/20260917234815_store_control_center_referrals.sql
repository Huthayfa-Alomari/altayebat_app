
create table if not exists public.store_public_settings (
  store_id uuid primary key references public.stores(id) on delete cascade,
  facebook_url text,
  instagram_url text,
  tiktok_url text,
  website_url text,
  google_maps_url text,
  facebook_enabled boolean not null default true,
  instagram_enabled boolean not null default true,
  whatsapp_number text,
  whatsapp_enabled boolean not null default true,
  whatsapp_default_message text not null default 'مرحباً أسواق الطيبات، أحتاج مساعدة بخصوص طلبي.',
  support_phone text,
  support_whatsapp_number text,
  support_hours_text text,
  privacy_policy_url text,
  terms_url text,
  play_store_url text,
  app_store_url text,
  store_status text not null default 'open'
    check (store_status in ('open','busy','temporarily_closed','maintenance')),
  status_message text,
  allow_scheduled_orders_when_closed boolean not null default false,
  announcement_enabled boolean not null default false,
  announcement_title text,
  announcement_body text,
  announcement_action_label text,
  announcement_action_url text,
  announcement_style text not null default 'info'
    check (announcement_style in ('info','sale','warning')),
  feature_ai boolean not null default true,
  feature_offers boolean not null default true,
  feature_loyalty boolean not null default true,
  feature_ads boolean not null default true,
  feature_call boolean not null default true,
  feature_whatsapp boolean not null default true,
  feature_reorder boolean not null default true,
  feature_referral boolean not null default true,
  maintenance_checkout boolean not null default false,
  maintenance_payments boolean not null default false,
  maintenance_delivery boolean not null default false,
  welcome_text text not null default 'كل احتياجات البيت بمكان واحد',
  share_message text not null default 'حمّل تطبيق أسواق الطيبات وتسوق بسهولة.',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.store_public_settings enable row level security;
revoke all on table public.store_public_settings from anon, authenticated;
grant select on table public.store_public_settings to anon;
grant select, insert, update, delete on table public.store_public_settings to authenticated;
grant all on table public.store_public_settings to service_role;

drop policy if exists "Public store settings read" on public.store_public_settings;
create policy "Public store settings read"
on public.store_public_settings for select
to anon, authenticated
using (true);

drop policy if exists "Store admins insert public settings" on public.store_public_settings;
create policy "Store admins insert public settings"
on public.store_public_settings for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists "Store admins update public settings" on public.store_public_settings;
create policy "Store admins update public settings"
on public.store_public_settings for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists "Store admins delete public settings" on public.store_public_settings;
create policy "Store admins delete public settings"
on public.store_public_settings for delete
to authenticated
using (private.is_store_admin(store_id));

insert into public.store_public_settings(store_id, whatsapp_number, support_phone)
select
  s.id,
  case
    when regexp_replace(coalesce(s.phone,''),'[^0-9]','','g') like '0%'
      then '962' || substring(regexp_replace(s.phone,'[^0-9]','','g') from 2)
    else nullif(regexp_replace(coalesce(s.phone,''),'[^0-9]','','g'),'')
  end,
  s.phone
from public.stores s
on conflict (store_id) do nothing;

create table if not exists public.referral_programs (
  store_id uuid primary key references public.stores(id) on delete cascade,
  is_enabled boolean not null default false,
  program_name text not null default 'ادعُ صديقك',
  min_first_order_total numeric(12,3) not null default 5 check (min_first_order_total >= 0),
  referrer_reward_count integer not null default 1 check (referrer_reward_count between 0 and 10),
  referred_reward_count integer not null default 1 check (referred_reward_count between 0 and 10),
  max_referrer_rewards_per_customer integer not null default 20 check (max_referrer_rewards_per_customer >= 0),
  reward_title text not null default 'مكافأة دعوة صديق',
  terms_text text not null default 'تُمنح المكافأة بعد تسليم أول طلب مؤهل للصديق.',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.referral_programs enable row level security;
revoke all on table public.referral_programs from anon, authenticated;
grant select, insert, update, delete on table public.referral_programs to authenticated;
grant all on table public.referral_programs to service_role;

drop policy if exists "Referral programs read" on public.referral_programs;
create policy "Referral programs read"
on public.referral_programs for select
to authenticated
using (true);

drop policy if exists "Store admins insert referral programs" on public.referral_programs;
create policy "Store admins insert referral programs"
on public.referral_programs for insert
to authenticated
with check (private.is_store_admin(store_id));

drop policy if exists "Store admins update referral programs" on public.referral_programs;
create policy "Store admins update referral programs"
on public.referral_programs for update
to authenticated
using (private.is_store_admin(store_id))
with check (private.is_store_admin(store_id));

drop policy if exists "Store admins delete referral programs" on public.referral_programs;
create policy "Store admins delete referral programs"
on public.referral_programs for delete
to authenticated
using (private.is_store_admin(store_id));

insert into public.referral_programs(store_id, min_first_order_total)
select id, greatest(coalesce(min_order, 5), 0)
from public.stores
on conflict (store_id) do nothing;

create table if not exists public.referral_codes (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  code text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint referral_codes_store_customer_unique unique(store_id, customer_id),
  constraint referral_codes_store_code_unique unique(store_id, code),
  constraint referral_codes_code_format check (code ~ '^[A-Z0-9]{6,12}$')
);

create index if not exists referral_codes_customer_idx
  on public.referral_codes(customer_id, store_id);

alter table public.referral_codes enable row level security;
revoke all on table public.referral_codes from anon, authenticated;
grant select on table public.referral_codes to authenticated;
grant all on table public.referral_codes to service_role;

drop policy if exists "Referral codes owner or admin read" on public.referral_codes;
create policy "Referral codes owner or admin read"
on public.referral_codes for select
to authenticated
using (customer_id = (select auth.uid()) or private.is_store_admin(store_id));

create table if not exists public.referrals (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  referral_code_id uuid not null references public.referral_codes(id) on delete restrict,
  referrer_customer_id uuid not null references public.customers(id) on delete cascade,
  referred_customer_id uuid not null references public.customers(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','rewarded','rejected')),
  qualified_order_id uuid references public.orders(id) on delete set null,
  referrer_reward_count integer not null default 0 check (referrer_reward_count >= 0),
  referred_reward_count integer not null default 0 check (referred_reward_count >= 0),
  created_at timestamptz not null default now(),
  qualified_at timestamptz,
  rewarded_at timestamptz,
  constraint referrals_referred_unique unique(store_id, referred_customer_id),
  constraint referrals_no_self check (referrer_customer_id <> referred_customer_id)
);

create index if not exists referrals_referrer_idx
  on public.referrals(store_id, referrer_customer_id, created_at desc);
create index if not exists referrals_status_idx
  on public.referrals(store_id, status, created_at desc);

alter table public.referrals enable row level security;
revoke all on table public.referrals from anon, authenticated;
grant select on table public.referrals to authenticated;
grant all on table public.referrals to service_role;

drop policy if exists "Referral participants or admin read" on public.referrals;
create policy "Referral participants or admin read"
on public.referrals for select
to authenticated
using (
  referrer_customer_id = (select auth.uid())
  or referred_customer_id = (select auth.uid())
  or private.is_store_admin(store_id)
);

create or replace function public.admin_update_store_profile(
  p_store_id uuid,
  p_name text,
  p_logo_url text,
  p_primary_color text,
  p_phone text,
  p_address text,
  p_delivery_fee numeric,
  p_min_order numeric,
  p_accepts_orders boolean,
  p_prep_time_min_minutes integer,
  p_prep_time_max_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.stores%rowtype;
  v_color text := upper(btrim(coalesce(p_primary_color,'#E31E24')));
begin
  if auth.uid() is null or not private.is_store_admin(p_store_id) then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;
  if coalesce(char_length(btrim(p_name)),0)=0 then
    raise exception 'INVALID_STORE_NAME' using errcode='22023';
  end if;
  if v_color !~ '^#[0-9A-F]{6}$' then
    raise exception 'INVALID_PRIMARY_COLOR' using errcode='22023';
  end if;
  if coalesce(p_delivery_fee,0) < 0 or coalesce(p_min_order,0) < 0 then
    raise exception 'INVALID_STORE_AMOUNTS' using errcode='22023';
  end if;
  if coalesce(p_prep_time_min_minutes,0) < 0
     or coalesce(p_prep_time_max_minutes,0) < coalesce(p_prep_time_min_minutes,0)
     or coalesce(p_prep_time_max_minutes,0) > 360 then
    raise exception 'INVALID_PREP_TIME' using errcode='22023';
  end if;

  update public.stores
  set name=btrim(p_name),
      logo_url=nullif(btrim(coalesce(p_logo_url,'')),''),
      primary_color=v_color,
      phone=nullif(btrim(coalesce(p_phone,'')),''),
      address=nullif(btrim(coalesce(p_address,'')),''),
      delivery_fee=coalesce(p_delivery_fee,0),
      min_order=coalesce(p_min_order,0),
      accepts_orders=coalesce(p_accepts_orders,true),
      prep_time_min_minutes=coalesce(p_prep_time_min_minutes,10),
      prep_time_max_minutes=coalesce(p_prep_time_max_minutes,30)
  where id=p_store_id
  returning * into v_row;

  if not found then raise exception 'STORE_NOT_FOUND'; end if;

  return jsonb_build_object(
    'id',v_row.id,'name',v_row.name,'logo_url',v_row.logo_url,
    'primary_color',v_row.primary_color,'phone',v_row.phone,'address',v_row.address,
    'delivery_fee',v_row.delivery_fee,'min_order',v_row.min_order,
    'accepts_orders',v_row.accepts_orders,
    'prep_time_min_minutes',v_row.prep_time_min_minutes,
    'prep_time_max_minutes',v_row.prep_time_max_minutes
  );
end;
$function$;

revoke all on function public.admin_update_store_profile(
  uuid,text,text,text,text,text,numeric,numeric,boolean,integer,integer
) from public, anon;
grant execute on function public.admin_update_store_profile(
  uuid,text,text,text,text,text,numeric,numeric,boolean,integer,integer
) to authenticated, service_role;

create or replace function public.get_my_referral_state(p_store_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_program public.referral_programs%rowtype;
  v_code public.referral_codes%rowtype;
  v_code_text text;
  v_total integer := 0;
  v_rewarded integer := 0;
  v_joined public.referrals%rowtype;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not exists(select 1 from public.customers c where c.id=v_uid) then
    raise exception 'PROFILE_REQUIRED' using errcode='42501';
  end if;
  if not exists(select 1 from public.stores s where s.id=p_store_id and s.is_active=true) then
    raise exception 'STORE_UNAVAILABLE' using errcode='22023';
  end if;

  select * into v_program from public.referral_programs where store_id=p_store_id;
  if not found then
    return jsonb_build_object('enabled',false);
  end if;

  select * into v_code
  from public.referral_codes
  where store_id=p_store_id and customer_id=v_uid
  limit 1;

  if not found then
    loop
      v_code_text := upper(substr(md5(v_uid::text || clock_timestamp()::text || random()::text),1,8));
      begin
        insert into public.referral_codes(store_id,customer_id,code)
        values(p_store_id,v_uid,v_code_text)
        returning * into v_code;
        exit;
      exception when unique_violation then
        null;
      end;
    end loop;
  end if;

  select count(*)::integer,
         count(*) filter(where status='rewarded')::integer
    into v_total,v_rewarded
  from public.referrals
  where store_id=p_store_id and referrer_customer_id=v_uid;

  select * into v_joined
  from public.referrals
  where store_id=p_store_id and referred_customer_id=v_uid
  limit 1;

  return jsonb_build_object(
    'enabled',v_program.is_enabled,
    'program_name',v_program.program_name,
    'code',v_code.code,
    'min_first_order_total',v_program.min_first_order_total,
    'referrer_reward_count',v_program.referrer_reward_count,
    'referred_reward_count',v_program.referred_reward_count,
    'reward_title',v_program.reward_title,
    'terms_text',v_program.terms_text,
    'invites_count',v_total,
    'rewarded_invites_count',v_rewarded,
    'joined_with_code',case when v_joined.id is null then null else
      jsonb_build_object('status',v_joined.status,'created_at',v_joined.created_at)
    end
  );
end;
$function$;

revoke all on function public.get_my_referral_state(uuid) from public, anon;
grant execute on function public.get_my_referral_state(uuid) to authenticated, service_role;

create or replace function public.apply_referral_code(p_store_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_program public.referral_programs%rowtype;
  v_code public.referral_codes%rowtype;
  v_ref public.referrals%rowtype;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not exists(select 1 from public.customers c where c.id=v_uid) then
    raise exception 'PROFILE_REQUIRED' using errcode='42501';
  end if;

  select * into v_program
  from public.referral_programs
  where store_id=p_store_id and is_enabled=true;
  if not found then raise exception 'REFERRAL_DISABLED' using errcode='22023'; end if;

  if exists(
    select 1 from public.orders o
    where o.store_id=p_store_id and o.customer_id=v_uid and o.status='delivered'
  ) then
    raise exception 'REFERRAL_NEW_CUSTOMERS_ONLY' using errcode='22023';
  end if;

  if exists(
    select 1 from public.referrals r
    where r.store_id=p_store_id and r.referred_customer_id=v_uid
  ) then
    raise exception 'REFERRAL_ALREADY_APPLIED' using errcode='22023';
  end if;

  select * into v_code
  from public.referral_codes
  where store_id=p_store_id
    and code=upper(btrim(coalesce(p_code,'')))
    and is_active=true
  limit 1;

  if not found then raise exception 'INVALID_REFERRAL_CODE' using errcode='22023'; end if;
  if v_code.customer_id=v_uid then raise exception 'SELF_REFERRAL_NOT_ALLOWED' using errcode='22023'; end if;

  insert into public.referrals(
    store_id,referral_code_id,referrer_customer_id,referred_customer_id
  ) values(
    p_store_id,v_code.id,v_code.customer_id,v_uid
  ) returning * into v_ref;

  return jsonb_build_object(
    'applied',true,
    'status',v_ref.status,
    'reward_title',v_program.reward_title,
    'min_first_order_total',v_program.min_first_order_total
  );
end;
$function$;

revoke all on function public.apply_referral_code(uuid,text) from public, anon;
grant execute on function public.apply_referral_code(uuid,text) to authenticated, service_role;

create or replace function private.trg_process_referral_reward()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ref public.referrals%rowtype;
  v_program public.referral_programs%rowtype;
  v_referrer_reward integer := 0;
  v_referred_reward integer := 0;
  v_rewarded_before integer := 0;
begin
  if new.status <> 'delivered'
     or old.status is not distinct from new.status
     or new.customer_id is null then
    return new;
  end if;

  select * into v_ref
  from public.referrals r
  where r.store_id=new.store_id
    and r.referred_customer_id=new.customer_id
    and r.status='pending'
  for update;

  if not found then return new; end if;

  select * into v_program
  from public.referral_programs p
  where p.store_id=new.store_id and p.is_enabled=true;

  if not found then return new; end if;
  if coalesce(new.subtotal,new.total,0) < v_program.min_first_order_total then return new; end if;

  select count(*)::integer into v_rewarded_before
  from public.referrals r
  where r.store_id=new.store_id
    and r.referrer_customer_id=v_ref.referrer_customer_id
    and r.status='rewarded';

  v_referrer_reward := case
    when v_program.max_referrer_rewards_per_customer=0 then v_program.referrer_reward_count
    when v_rewarded_before < v_program.max_referrer_rewards_per_customer then v_program.referrer_reward_count
    else 0
  end;
  v_referred_reward := v_program.referred_reward_count;

  if v_referrer_reward > 0 then
    insert into public.customer_loyalty_wallets(store_id,customer_id,rewards_available)
    values(new.store_id,v_ref.referrer_customer_id,v_referrer_reward)
    on conflict(store_id,customer_id) do update
    set rewards_available=public.customer_loyalty_wallets.rewards_available+excluded.rewards_available,
        updated_at=now();

    insert into public.loyalty_events(
      store_id,customer_id,order_id,event_type,delta_rewards,metadata
    ) values(
      new.store_id,v_ref.referrer_customer_id,new.id,'referral_referrer_reward',
      v_referrer_reward,
      jsonb_build_object('referred_customer_id',new.customer_id,'referral_id',v_ref.id)
    );
  end if;

  if v_referred_reward > 0 then
    insert into public.customer_loyalty_wallets(store_id,customer_id,rewards_available)
    values(new.store_id,new.customer_id,v_referred_reward)
    on conflict(store_id,customer_id) do update
    set rewards_available=public.customer_loyalty_wallets.rewards_available+excluded.rewards_available,
        updated_at=now();

    insert into public.loyalty_events(
      store_id,customer_id,order_id,event_type,delta_rewards,metadata
    ) values(
      new.store_id,new.customer_id,new.id,'referral_referred_reward',
      v_referred_reward,
      jsonb_build_object('referrer_customer_id',v_ref.referrer_customer_id,'referral_id',v_ref.id)
    );
  end if;

  update public.referrals
  set status='rewarded',
      qualified_order_id=new.id,
      referrer_reward_count=v_referrer_reward,
      referred_reward_count=v_referred_reward,
      qualified_at=now(),
      rewarded_at=now()
  where id=v_ref.id;

  if v_referrer_reward > 0 then
    insert into public.customer_notifications(
      store_id,customer_id,order_id,type,title,body,data
    ) values(
      new.store_id,v_ref.referrer_customer_id,new.id,'system',
      '🎁 مكافأة دعوة صديق',
      'تم تسليم أول طلب مؤهل لصديقك وأضيفت مكافأتك.',
      jsonb_build_object('kind','referral_reward','referral_id',v_ref.id)
    );
  end if;

  if v_referred_reward > 0 then
    insert into public.customer_notifications(
      store_id,customer_id,order_id,type,title,body,data
    ) values(
      new.store_id,new.customer_id,new.id,'system',
      '🎁 مكافأة ترحيبية',
      'تم تسليم طلبك المؤهل وأضيفت مكافأة الدعوة إلى حسابك.',
      jsonb_build_object('kind','referral_reward','referral_id',v_ref.id)
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_process_referral_reward on public.orders;
create trigger trg_process_referral_reward
after update of status on public.orders
for each row
when ((new.status='delivered') and (old.status is distinct from new.status))
execute function private.trg_process_referral_reward();

create unique index if not exists loyalty_events_referral_order_customer_type_uidx
on public.loyalty_events(order_id,customer_id,event_type)
where order_id is not null
  and event_type in ('referral_referrer_reward','referral_referred_reward');

alter table public.orders
  add column if not exists scheduled_for timestamptz;

create index if not exists orders_store_scheduled_idx
  on public.orders(store_id, scheduled_for)
  where scheduled_for is not null and status not in ('delivered','cancelled');

create or replace function public.get_store_open_state(
  p_store_id uuid,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_store record;
  v_public record;
  v_local timestamp;
  v_dow integer;
  v_time time;
  v_hours record;
  v_open boolean;
begin
  select s.id,s.name,s.is_active,s.accepts_orders,s.timezone,
         s.prep_time_min_minutes,s.prep_time_max_minutes
    into v_store
  from public.stores s
  where s.id=p_store_id;

  if not found then return jsonb_build_object('open',false,'reason','STORE_NOT_FOUND'); end if;

  select ps.store_status,ps.status_message,ps.allow_scheduled_orders_when_closed,
         ps.maintenance_checkout,ps.maintenance_delivery
    into v_public
  from public.store_public_settings ps
  where ps.store_id=p_store_id;

  if not coalesce(v_store.is_active,false) then
    return jsonb_build_object('open',false,'reason','STORE_INACTIVE');
  end if;
  if not coalesce(v_store.accepts_orders,false) then
    return jsonb_build_object(
      'open',false,'reason','ORDERS_PAUSED',
      'store_status',coalesce(v_public.store_status,'temporarily_closed'),
      'status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',coalesce(v_public.allow_scheduled_orders_when_closed,false)
    );
  end if;
  if coalesce(v_public.maintenance_checkout,false) then
    return jsonb_build_object(
      'open',false,'reason','CHECKOUT_MAINTENANCE',
      'store_status','maintenance','status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',false
    );
  end if;
  if coalesce(v_public.maintenance_delivery,false) then
    return jsonb_build_object(
      'open',false,'reason','DELIVERY_MAINTENANCE',
      'store_status','maintenance','status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',false
    );
  end if;
  if coalesce(v_public.store_status,'open') in ('temporarily_closed','maintenance') then
    return jsonb_build_object(
      'open',false,'reason',upper(coalesce(v_public.store_status,'temporarily_closed')),
      'store_status',coalesce(v_public.store_status,'temporarily_closed'),
      'status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',
        case when coalesce(v_public.store_status,'open')='maintenance' then false
             else coalesce(v_public.allow_scheduled_orders_when_closed,false) end
    );
  end if;

  v_local := p_at at time zone coalesce(nullif(v_store.timezone,''),'Asia/Amman');
  v_dow := extract(dow from v_local)::integer;
  v_time := v_local::time;

  select * into v_hours
  from public.store_hours h
  where h.store_id=p_store_id and h.day_of_week=v_dow;

  if not found then
    return jsonb_build_object(
      'open',true,'reason','NO_HOURS_CONFIGURED','timezone',v_store.timezone,
      'store_status',coalesce(v_public.store_status,'open'),
      'status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',coalesce(v_public.allow_scheduled_orders_when_closed,false),
      'prep_time_min_minutes',v_store.prep_time_min_minutes,
      'prep_time_max_minutes',v_store.prep_time_max_minutes
    );
  end if;

  if v_hours.is_closed then
    return jsonb_build_object(
      'open',false,'reason','CLOSED_TODAY','timezone',v_store.timezone,
      'store_status',coalesce(v_public.store_status,'open'),
      'status_message',v_public.status_message,
      'allow_scheduled_orders_when_closed',coalesce(v_public.allow_scheduled_orders_when_closed,false)
    );
  end if;

  if v_hours.closes_next_day then
    v_open := (v_time >= v_hours.open_time or v_time < v_hours.close_time);
  else
    v_open := (v_time >= v_hours.open_time and v_time < v_hours.close_time);
  end if;

  return jsonb_build_object(
    'open',v_open,
    'reason',case when v_open then 'OPEN' else 'OUTSIDE_HOURS' end,
    'timezone',v_store.timezone,
    'store_status',coalesce(v_public.store_status,'open'),
    'status_message',v_public.status_message,
    'allow_scheduled_orders_when_closed',coalesce(v_public.allow_scheduled_orders_when_closed,false),
    'open_time',v_hours.open_time,
    'close_time',v_hours.close_time,
    'closes_next_day',v_hours.closes_next_day,
    'prep_time_min_minutes',v_store.prep_time_min_minutes,
    'prep_time_max_minutes',v_store.prep_time_max_minutes
  );
end;
$function$;

create or replace function private.create_order_checkout_v3_atomic(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me',
  p_scheduled_for timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_order uuid;
  v_item record;
  v_product record;
  v_address record;
  v_subtotal numeric(12,3) := 0;
  v_payment text := lower(btrim(coalesce(p_payment_method,'cash')));
  v_payment_status text;
  v_sub_policy text := lower(btrim(coalesce(p_substitute_policy,'call_me')));
  v_service jsonb;
  v_open_state jsonb;
  v_delivery numeric(12,3) := 0;
  v_min_order numeric(12,3) := 0;
  v_zone_id uuid;
  v_eta_min integer;
  v_eta_max integer;
  v_address_snapshot jsonb;
  v_min_qty integer;
  v_qty_step integer;
  v_allow_schedule boolean := false;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if p_address_id is null then raise exception 'ADDRESS_REQUIRED' using errcode='22023'; end if;
  if v_payment not in ('cash','card','cliq') then raise exception 'INVALID_PAYMENT_METHOD' using errcode='22023'; end if;
  if v_sub_policy not in ('call_me','best_match','remove_item') then raise exception 'INVALID_SUBSTITUTE_POLICY' using errcode='22023'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'EMPTY_CART' using errcode='22023'; end if;
  if jsonb_array_length(p_items)>100 then raise exception 'TOO_MANY_ITEMS' using errcode='22023'; end if;
  if not exists(select 1 from public.customers c where c.id=v_user) then raise exception 'CUSTOMER_PROFILE_REQUIRED' using errcode='42501'; end if;

  select a.* into v_address
  from public.addresses a
  where a.id=p_address_id and a.customer_id=v_user;
  if not found then raise exception 'INVALID_ADDRESS' using errcode='42501'; end if;

  v_open_state := public.get_store_open_state(p_store_id,now());

  if p_scheduled_for is null then
    if coalesce((v_open_state->>'open')::boolean,false)=false then
      raise exception 'STORE_CLOSED:%',coalesce(v_open_state->>'reason','UNKNOWN');
    end if;
  else
    v_allow_schedule := coalesce((v_open_state->>'allow_scheduled_orders_when_closed')::boolean,false);
    if not v_allow_schedule then
      raise exception 'SCHEDULED_ORDERS_DISABLED' using errcode='22023';
    end if;
    if p_scheduled_for < now() + interval '30 minutes'
       or p_scheduled_for > now() + interval '7 days' then
      raise exception 'INVALID_SCHEDULE_TIME' using errcode='22023';
    end if;
    v_open_state := public.get_store_open_state(p_store_id,p_scheduled_for);
    if coalesce((v_open_state->>'open')::boolean,false)=false then
      raise exception 'SCHEDULE_OUTSIDE_STORE_HOURS' using errcode='22023';
    end if;
  end if;

  v_service := public.get_delivery_serviceability(p_store_id,p_address_id,null,null,null,null);
  if coalesce((v_service->>'serviceable')::boolean,false)=false then
    raise exception 'OUTSIDE_DELIVERY_ZONE';
  end if;

  v_delivery := coalesce((v_service->>'delivery_fee')::numeric,0);
  v_min_order := coalesce((v_service->>'min_order')::numeric,0);
  v_zone_id := nullif(v_service->>'zone_id','')::uuid;
  v_eta_min := nullif(v_service->>'eta_min_minutes','')::integer;
  v_eta_max := nullif(v_service->>'eta_max_minutes','')::integer;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<=0 then
      raise exception 'INVALID_ITEM' using errcode='22023';
    end if;

    select p.id,p.name,p.price,p.stock_qty,p.is_available,p.min_qty,p.qty_step
      into v_product
    from public.products p
    where p.id=v_item.product_id and p.store_id=p_store_id
    for update;

    if not found or not coalesce(v_product.is_available,false) then
      raise exception 'PRODUCT_UNAVAILABLE:%',v_item.product_id;
    end if;

    v_min_qty := greatest(coalesce(v_product.min_qty,1),1);
    v_qty_step := greatest(coalesce(v_product.qty_step,1),1);

    if v_item.quantity < v_min_qty then
      raise exception 'MIN_QTY:%:%',v_product.name,v_min_qty using errcode='22023';
    end if;
    if mod(v_item.quantity-v_min_qty,v_qty_step)<>0 then
      raise exception 'INVALID_QTY_STEP:%:%',v_product.name,v_qty_step using errcode='22023';
    end if;
    if coalesce(v_product.stock_qty,0)<v_item.quantity then
      raise exception 'INSUFFICIENT_STOCK:%',v_product.name;
    end if;
    if v_product.price is null or v_product.price<=0 then
      raise exception 'INVALID_PRICE:%',v_product.name;
    end if;

    v_subtotal := v_subtotal + (v_product.price*v_item.quantity);
  end loop;

  if v_subtotal<v_min_order then raise exception 'MIN_ORDER:%',v_min_order; end if;
  v_payment_status := case when v_payment='cash' then 'unpaid' else 'pending' end;

  v_address_snapshot := jsonb_build_object(
    'id',v_address.id,'label',v_address.label,'address_text',v_address.address_text,
    'city',v_address.city,'area',v_address.area,'street',v_address.street,
    'building',v_address.building,'floor',v_address.floor,'notes',v_address.notes,
    'lat',v_address.lat,'lng',v_address.lng
  );

  insert into public.orders(
    store_id,customer_id,address_id,status,payment_method,payment_status,
    subtotal,delivery_fee,discount,total,customer_note,substitute_policy,
    delivery_zone_id,delivery_eta_min_minutes,delivery_eta_max_minutes,
    fulfillment_method,address_snapshot,scheduled_for
  ) values(
    p_store_id,v_user,p_address_id,'pending',v_payment,v_payment_status,
    v_subtotal,v_delivery,0,v_subtotal+v_delivery,nullif(btrim(p_customer_note),''),v_sub_policy,
    v_zone_id,v_eta_min,v_eta_max,'delivery',v_address_snapshot,p_scheduled_for
  ) returning id into v_order;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity
    from jsonb_to_recordset(p_items) x(product_id uuid,quantity integer)
    group by x.product_id
    order by x.product_id
  loop
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal)
    select v_order,p.id,p.name,v_item.quantity,p.price,p.price*v_item.quantity
    from public.products p where p.id=v_item.product_id and p.store_id=p_store_id;

    update public.products
    set stock_qty=stock_qty-v_item.quantity,
        is_available=case
          when stock_qty-v_item.quantity < greatest(coalesce(min_qty,1),1) then false
          else is_available
        end,
        updated_at=now()
    where id=v_item.product_id and store_id=p_store_id and stock_qty>=v_item.quantity;
    if not found then raise exception 'STOCK_CHANGED:%',v_item.product_id; end if;
  end loop;

  insert into public.order_status_history(order_id,status,changed_by)
  values(v_order,'pending',v_user);

  return v_order;
end;
$function$;

create or replace function public.create_order_checkout_v3(
  p_store_id uuid,
  p_items jsonb,
  p_address_id uuid,
  p_payment_method text default 'cash',
  p_customer_note text default null,
  p_substitute_policy text default 'call_me',
  p_scheduled_for timestamptz default null
)
returns uuid
language sql
security definer
set search_path = ''
as $function$
  select private.create_order_checkout_v3_atomic(
    p_store_id,p_items,p_address_id,p_payment_method,p_customer_note,p_substitute_policy,p_scheduled_for
  );
$function$;

revoke all on function public.create_order_checkout_v3(
  uuid,jsonb,uuid,text,text,text,timestamptz
) from public, anon;
grant execute on function public.create_order_checkout_v3(
  uuid,jsonb,uuid,text,text,text,timestamptz
) to authenticated, service_role;

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
