
alter table public.loyalty_events
  drop constraint if exists loyalty_events_event_type_check;

alter table public.loyalty_events
  add constraint loyalty_events_event_type_check
  check (
    event_type = any (
      array[
        'basket_earned'::text,
        'reward_unlocked'::text,
        'reward_redeemed'::text,
        'reward_restored'::text,
        'adjustment'::text,
        'referral_referrer_reward'::text,
        'referral_referred_reward'::text
      ]
    )
  );
