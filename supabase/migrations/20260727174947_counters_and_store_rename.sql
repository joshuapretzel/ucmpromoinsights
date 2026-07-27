-- The promoter app drops per-customer logging in favour of two tap counters,
-- so students spend less time on their phone:
--   "Angesprochen"  -> shifts.contacts_total (column already existed)
--   "Gewinnspiel"   -> shifts.raffle_entries (new)
--
-- Both are plain running totals on the promoter's daily report row, which is
-- already tied to a store via shifts.store_id / store_shift_id — so the numbers
-- roll up per store without any further plumbing.
ALTER TABLE "public"."shifts"
    ADD COLUMN IF NOT EXISTS "raffle_entries" integer;
