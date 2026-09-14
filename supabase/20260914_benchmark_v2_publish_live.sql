-- Benchmark v2 live publish runner.
-- Production execution date: 2026-09-14.
-- The private publisher was installed in Supabase and publishes APPROVED_NEW only.
do $$
begin
  perform private.publish_benchmark_v2_candidates();
end;
$$;
