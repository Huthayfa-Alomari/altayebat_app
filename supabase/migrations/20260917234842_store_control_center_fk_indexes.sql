
    create index if not exists referral_programs_updated_by_idx
      on public.referral_programs(updated_by) where updated_by is not null;
    create index if not exists referrals_qualified_order_idx
      on public.referrals(qualified_order_id) where qualified_order_id is not null;
    create index if not exists referrals_referral_code_idx
      on public.referrals(referral_code_id);
    create index if not exists referrals_referred_customer_idx
      on public.referrals(referred_customer_id, store_id);
    create index if not exists referrals_referrer_customer_idx
      on public.referrals(referrer_customer_id, store_id);
    create index if not exists store_public_settings_updated_by_idx
      on public.store_public_settings(updated_by) where updated_by is not null;
  
