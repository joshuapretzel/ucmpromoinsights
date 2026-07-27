-- Scheduled shifts. Previously a "shift" only came into existence as a side
-- effect of a promoter opening the app (findOrCreateActiveShift), so there was
-- no way for ops to plan who works where and when.
--
-- New shape:  promotion -> stores -> store_shifts -> assigned promoters
--
-- The existing `shifts` table keeps its meaning of "one promoter's report for
-- one day" and gains a link to the scheduled shift it belongs to. Because a
-- scheduled shift can hold several promoters, the schedule and the report have
-- to stay separate tables: every reporting child row (sales,
-- customer_interactions, feedback_notes, custom_question_answers,
-- shift_photos) hangs off shifts.id and takes its attribution from
-- shifts.promoter_id.

CREATE TABLE IF NOT EXISTS "public"."store_shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "store_id" "uuid" NOT NULL,
    "shift_date" "date" NOT NULL,
    "start_time" time without time zone,
    "end_time" time without time zone,
    "slots" integer DEFAULT 1,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."store_shifts" OWNER TO "postgres";

ALTER TABLE ONLY "public"."store_shifts"
    ADD CONSTRAINT "store_shifts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."store_shifts"
    ADD CONSTRAINT "store_shifts_store_id_fkey" FOREIGN KEY ("store_id") REFERENCES "public"."stores"("id") ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS "store_shifts_store_date_idx" ON "public"."store_shifts" ("store_id", "shift_date");

-- Which promoters work a given scheduled shift. Many promoters per shift.
CREATE TABLE IF NOT EXISTS "public"."shift_assignments" (
    "store_shift_id" "uuid" NOT NULL,
    "promoter_id" "uuid" NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."shift_assignments" OWNER TO "postgres";

ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_pkey" PRIMARY KEY ("store_shift_id", "promoter_id");

ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_store_shift_id_fkey" FOREIGN KEY ("store_shift_id") REFERENCES "public"."store_shifts"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."shift_assignments"
    ADD CONSTRAINT "shift_assignments_promoter_id_fkey" FOREIGN KEY ("promoter_id") REFERENCES "public"."promoters"("id") ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS "shift_assignments_promoter_idx" ON "public"."shift_assignments" ("promoter_id");

-- Link a promoter's daily report back to the shift it was worked under.
ALTER TABLE "public"."shifts"
    ADD COLUMN IF NOT EXISTS "store_shift_id" "uuid" REFERENCES "public"."store_shifts"("id") ON DELETE SET NULL;

-- A promoter gets at most one report row per promotion per day. Without this,
-- the SELECT-then-INSERT in the app raced and produced duplicate rows (two were
-- created 9ms apart on a single login).
--
-- Existing data has to be de-duplicated before the index can be built. On
-- production this affects 31 groups, 3 of which hold real reported data
-- (163 sales rows and 241 customer interactions between them).
--
-- So merge rather than delete: point every child row at the oldest shift in its
-- group, which leaves the duplicates childless and safe to remove without
-- losing a single recorded number.
--
-- Note the denormalised counters (contacts_total, raffle_entries, age_main…) on
-- the discarded rows are deliberately NOT summed into the survivor — they are
-- snapshots, and adding them together could double-count a total that was
-- entered twice. The underlying child rows are what get preserved.
WITH ranked AS (
    SELECT "id",
           first_value("id") OVER (
             PARTITION BY "promoter_id", "promotion_id", "shift_date"
             ORDER BY "created_at", "id"
           ) AS keep_id
    FROM "public"."shifts"
)
UPDATE "public"."sales" c SET "shift_id" = r.keep_id
FROM ranked r WHERE c."shift_id" = r."id" AND r."id" <> r.keep_id;

WITH ranked AS (
    SELECT "id",
           first_value("id") OVER (
             PARTITION BY "promoter_id", "promotion_id", "shift_date"
             ORDER BY "created_at", "id"
           ) AS keep_id
    FROM "public"."shifts"
)
UPDATE "public"."customer_interactions" c SET "shift_id" = r.keep_id
FROM ranked r WHERE c."shift_id" = r."id" AND r."id" <> r.keep_id;

WITH ranked AS (
    SELECT "id",
           first_value("id") OVER (
             PARTITION BY "promoter_id", "promotion_id", "shift_date"
             ORDER BY "created_at", "id"
           ) AS keep_id
    FROM "public"."shifts"
)
UPDATE "public"."feedback_notes" c SET "shift_id" = r.keep_id
FROM ranked r WHERE c."shift_id" = r."id" AND r."id" <> r.keep_id;

WITH ranked AS (
    SELECT "id",
           first_value("id") OVER (
             PARTITION BY "promoter_id", "promotion_id", "shift_date"
             ORDER BY "created_at", "id"
           ) AS keep_id
    FROM "public"."shifts"
)
UPDATE "public"."custom_question_answers" c SET "shift_id" = r.keep_id
FROM ranked r WHERE c."shift_id" = r."id" AND r."id" <> r.keep_id;

WITH ranked AS (
    SELECT "id",
           first_value("id") OVER (
             PARTITION BY "promoter_id", "promotion_id", "shift_date"
             ORDER BY "created_at", "id"
           ) AS keep_id
    FROM "public"."shifts"
)
UPDATE "public"."shift_photos" c SET "shift_id" = r.keep_id
FROM ranked r WHERE c."shift_id" = r."id" AND r."id" <> r.keep_id;

-- Now every duplicate is childless. The NOT EXISTS guards stay as a safety net:
-- if anything unexpected still hangs off a duplicate, the index build fails
-- loudly instead of quietly discarding it.
DELETE FROM "public"."shifts" s
WHERE EXISTS (
        SELECT 1 FROM "public"."shifts" keep
        WHERE keep."promoter_id" = s."promoter_id"
          AND keep."promotion_id" = s."promotion_id"
          AND keep."shift_date" = s."shift_date"
          AND (keep."created_at" < s."created_at"
               OR (keep."created_at" = s."created_at" AND keep."id" < s."id"))
      )
  AND NOT EXISTS (SELECT 1 FROM "public"."sales" x WHERE x."shift_id" = s."id")
  AND NOT EXISTS (SELECT 1 FROM "public"."customer_interactions" x WHERE x."shift_id" = s."id")
  AND NOT EXISTS (SELECT 1 FROM "public"."feedback_notes" x WHERE x."shift_id" = s."id")
  AND NOT EXISTS (SELECT 1 FROM "public"."custom_question_answers" x WHERE x."shift_id" = s."id")
  AND NOT EXISTS (SELECT 1 FROM "public"."shift_photos" x WHERE x."shift_id" = s."id");

CREATE UNIQUE INDEX IF NOT EXISTS "shifts_promoter_day_uniq" ON "public"."shifts" ("promoter_id", "promotion_id", "shift_date");

-- RLS: both new tables reach their promotion indirectly via stores, so the
-- read policies need a subquery rather than a direct app_can_see_promotion call.
ALTER TABLE "public"."store_shifts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_read_store_shifts" ON "public"."store_shifts" FOR SELECT TO "authenticated"
    USING (EXISTS (
        SELECT 1 FROM "public"."stores" s
        WHERE s."id" = "store_shifts"."store_id"
          AND "public"."app_can_see_promotion"(s."promotion_id")
    ));

CREATE POLICY "rls_staff_store_shifts" ON "public"."store_shifts" TO "authenticated"
    USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());

ALTER TABLE "public"."shift_assignments" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_read_shift_assignments" ON "public"."shift_assignments" FOR SELECT TO "authenticated"
    USING (EXISTS (
        SELECT 1 FROM "public"."store_shifts" ss
        JOIN "public"."stores" s ON s."id" = ss."store_id"
        WHERE ss."id" = "shift_assignments"."store_shift_id"
          AND "public"."app_can_see_promotion"(s."promotion_id")
    ));

CREATE POLICY "rls_staff_shift_assignments" ON "public"."shift_assignments" TO "authenticated"
    USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());

GRANT ALL ON TABLE "public"."store_shifts" TO "anon";
GRANT ALL ON TABLE "public"."store_shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."store_shifts" TO "service_role";

GRANT ALL ON TABLE "public"."shift_assignments" TO "anon";
GRANT ALL ON TABLE "public"."shift_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_assignments" TO "service_role";
