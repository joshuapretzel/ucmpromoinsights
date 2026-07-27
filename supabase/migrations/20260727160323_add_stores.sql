-- Stores (physical counters/booths) that belong to a promotion, so that
-- contacts/sales/shifts can be attributed to a specific store rather than
-- just the promotion as a whole.
CREATE TABLE IF NOT EXISTS "public"."stores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "promotion_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."stores" OWNER TO "postgres";

ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."stores"
    ADD CONSTRAINT "stores_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;

ALTER TABLE "public"."stores" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_read_stores" ON "public"."stores" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("promotion_id"));

CREATE POLICY "rls_staff_stores" ON "public"."stores" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());

GRANT ALL ON TABLE "public"."stores" TO "anon";
GRANT ALL ON TABLE "public"."stores" TO "authenticated";
GRANT ALL ON TABLE "public"."stores" TO "service_role";

-- A promoter is assigned to a promotion at a specific store, and shifts
-- inherit that store when auto-created (see findOrCreateActiveShift).
ALTER TABLE "public"."promoter_assignments"
    ADD COLUMN IF NOT EXISTS "store_id" "uuid" REFERENCES "public"."stores"("id") ON DELETE SET NULL;

ALTER TABLE "public"."shifts"
    ADD COLUMN IF NOT EXISTS "store_id" "uuid" REFERENCES "public"."stores"("id") ON DELETE SET NULL;
