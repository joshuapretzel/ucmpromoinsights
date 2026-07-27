


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."app_can_see_promotion"("pid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select public.app_is_staff()
      or exists (
        select 1 from public.client_promotions cp
        where cp.client_id = auth.uid()
          and cp.promotion_id = pid
      );
$$;


ALTER FUNCTION "public"."app_can_see_promotion"("pid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_is_staff"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(public.app_role() in ('admin','manager','promoter'), false);
$$;


ALTER FUNCTION "public"."app_is_staff"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."app_role"() RETURNS "text"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select role from public.profiles where id = auth.uid();
$$;


ALTER FUNCTION "public"."app_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_profile_to_promoter"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  -- Only act when the profile is (or has become) a promoter with an email.
  if new.role = 'promoter' and new.email is not null then
    insert into promoters (email, name, active)
    values (new.email, coalesce(new.full_name, split_part(new.email, '@', 1)), true)
    on conflict (email) do update
      set name = coalesce(excluded.name, promoters.name);
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."sync_profile_to_promoter"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."client_promotions" (
    "client_id" "uuid" NOT NULL,
    "promotion_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."client_promotions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_question_answers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "question_id" "uuid" NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "customer_interaction_id" "uuid",
    "answer_json" "jsonb" NOT NULL,
    "recorded_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."custom_question_answers" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."custom_questions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "promotion_id" "uuid" NOT NULL,
    "label" "text" NOT NULL,
    "field_type" "text" NOT NULL,
    "choices" "jsonb",
    "client_visible" boolean DEFAULT true,
    "position" integer DEFAULT 0,
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "section" "text" DEFAULT 'contact'::"text",
    CONSTRAINT "custom_questions_field_type_check" CHECK (("field_type" = ANY (ARRAY['text'::"text", 'rating_1_5'::"text", 'boolean'::"text", 'multi_choice'::"text", 'number'::"text"]))),
    CONSTRAINT "custom_questions_section_check" CHECK (("section" = ANY (ARRAY['contact'::"text", 'shift'::"text"])))
);


ALTER TABLE "public"."custom_questions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."customer_interactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "gender" "text",
    "age_group" "text",
    "purchased" boolean DEFAULT false,
    "note" "text",
    "recorded_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "customer_interactions_gender_check" CHECK (("gender" = ANY (ARRAY['female'::"text", 'male'::"text", 'mixed'::"text"])))
);


ALTER TABLE "public"."customer_interactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."feedback_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "kind" "text" NOT NULL,
    "text" "text",
    "lost_revenue_eur" numeric(10,2),
    "recorded_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "feedback_notes_kind_check" CHECK (("kind" = ANY (ARRAY['non_purchase'::"text", 'observation'::"text", 'oos'::"text", 'quote'::"text", 'lost_revenue'::"text"])))
);


ALTER TABLE "public"."feedback_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."products" (
    "ean" "text" NOT NULL,
    "brand" "text" NOT NULL,
    "name" "text" NOT NULL,
    "category" "text",
    "price" numeric(10,2),
    "image_url" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "full_name" "text",
    "role" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['admin'::"text", 'manager'::"text", 'promoter'::"text", 'client'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promoter_assignments" (
    "promotion_id" "uuid" NOT NULL,
    "promoter_id" "uuid" NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."promoter_assignments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promoter_message_replies" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid" NOT NULL,
    "from_name" "text" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."promoter_message_replies" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promoter_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "promoter_id" "uuid" NOT NULL,
    "promotion_id" "uuid",
    "from_name" "text" NOT NULL,
    "body" "text" NOT NULL,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."promoter_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promoters" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "external_id" "text",
    "email" "text",
    "name" "text" NOT NULL,
    "phone" "text",
    "photo_url" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."promoters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promotion_products" (
    "promotion_id" "uuid" NOT NULL,
    "ean" "text" NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."promotion_products" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."promotions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "code" "text",
    "brand" "text" NOT NULL,
    "client" "text" NOT NULL,
    "location" "text",
    "note" "text",
    "start_date" "date",
    "end_date" "date",
    "status" "text" DEFAULT 'active'::"text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "target_revenue" numeric,
    "briefing_notes" "text",
    "enabled_modules" "jsonb"
);


ALTER TABLE "public"."promotions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sales" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "ean" "text" NOT NULL,
    "units" integer DEFAULT 1 NOT NULL,
    "unit_price" numeric(10,2),
    "recorded_at" timestamp with time zone DEFAULT "now"(),
    "off_list" boolean DEFAULT false,
    "notes" "text",
    "customer_interaction_id" "uuid",
    CONSTRAINT "sales_units_check" CHECK (("units" > 0))
);


ALTER TABLE "public"."sales" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shift_photos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "shift_id" "uuid" NOT NULL,
    "storage_path" "text" NOT NULL,
    "caption" "text",
    "kind" "text" DEFAULT 'booth'::"text",
    "taken_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."shift_photos" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."shifts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "promotion_id" "uuid" NOT NULL,
    "promoter_id" "uuid" NOT NULL,
    "shift_date" "date" NOT NULL,
    "start_time" timestamp with time zone,
    "end_time" timestamp with time zone,
    "status" "text" DEFAULT 'planned'::"text",
    "checklist_complete" boolean DEFAULT false,
    "briefing_read" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "contacts_total" integer,
    "contacts_female" integer,
    "contacts_male" integer,
    "contacts_mixed" integer,
    "age_main" "text",
    "samples_discovery_mini" integer,
    "samples_body_lotion" integer
);


ALTER TABLE "public"."shifts" OWNER TO "postgres";


ALTER TABLE ONLY "public"."client_promotions"
    ADD CONSTRAINT "client_promotions_pkey" PRIMARY KEY ("client_id", "promotion_id");



ALTER TABLE ONLY "public"."custom_question_answers"
    ADD CONSTRAINT "custom_question_answers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."custom_questions"
    ADD CONSTRAINT "custom_questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."customer_interactions"
    ADD CONSTRAINT "customer_interactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."feedback_notes"
    ADD CONSTRAINT "feedback_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."products"
    ADD CONSTRAINT "products_pkey" PRIMARY KEY ("ean");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promoter_assignments"
    ADD CONSTRAINT "promoter_assignments_pkey" PRIMARY KEY ("promotion_id", "promoter_id");



ALTER TABLE ONLY "public"."promoter_message_replies"
    ADD CONSTRAINT "promoter_message_replies_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promoter_messages"
    ADD CONSTRAINT "promoter_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promoters"
    ADD CONSTRAINT "promoters_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."promoters"
    ADD CONSTRAINT "promoters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."promotion_products"
    ADD CONSTRAINT "promotion_products_pkey" PRIMARY KEY ("promotion_id", "ean");



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_code_key" UNIQUE ("code");



ALTER TABLE ONLY "public"."promotions"
    ADD CONSTRAINT "promotions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shift_photos"
    ADD CONSTRAINT "shift_photos_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."shifts"
    ADD CONSTRAINT "shifts_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_client_promotions_client" ON "public"."client_promotions" USING "btree" ("client_id");



CREATE INDEX "idx_client_promotions_promotion" ON "public"."client_promotions" USING "btree" ("promotion_id");



CREATE INDEX "idx_cqa_interaction" ON "public"."custom_question_answers" USING "btree" ("customer_interaction_id");



CREATE INDEX "idx_cqa_question" ON "public"."custom_question_answers" USING "btree" ("question_id");



CREATE INDEX "idx_cqa_shift" ON "public"."custom_question_answers" USING "btree" ("shift_id");



CREATE INDEX "idx_custom_questions_promotion" ON "public"."custom_questions" USING "btree" ("promotion_id");



CREATE INDEX "idx_customer_interactions_shift" ON "public"."customer_interactions" USING "btree" ("shift_id");



CREATE INDEX "idx_feedback_kind" ON "public"."feedback_notes" USING "btree" ("kind");



CREATE INDEX "idx_feedback_shift" ON "public"."feedback_notes" USING "btree" ("shift_id");



CREATE INDEX "idx_photos_shift" ON "public"."shift_photos" USING "btree" ("shift_id");



CREATE INDEX "idx_products_brand" ON "public"."products" USING "btree" ("brand");



CREATE INDEX "idx_products_category" ON "public"."products" USING "btree" ("category");



CREATE INDEX "idx_promoter_message_replies_msg" ON "public"."promoter_message_replies" USING "btree" ("message_id", "created_at");



CREATE INDEX "idx_promoter_messages_promoter" ON "public"."promoter_messages" USING "btree" ("promoter_id", "created_at" DESC);



CREATE INDEX "idx_promoter_messages_promotion" ON "public"."promoter_messages" USING "btree" ("promotion_id", "created_at" DESC);



CREATE INDEX "idx_promoters_active" ON "public"."promoters" USING "btree" ("active");



CREATE INDEX "idx_promotions_status" ON "public"."promotions" USING "btree" ("status");



CREATE INDEX "idx_sales_ean" ON "public"."sales" USING "btree" ("ean");



CREATE INDEX "idx_sales_interaction" ON "public"."sales" USING "btree" ("customer_interaction_id");



CREATE INDEX "idx_sales_recorded_at" ON "public"."sales" USING "btree" ("recorded_at");



CREATE INDEX "idx_sales_shift" ON "public"."sales" USING "btree" ("shift_id");



CREATE INDEX "idx_shifts_date" ON "public"."shifts" USING "btree" ("shift_date");



CREATE INDEX "idx_shifts_promoter" ON "public"."shifts" USING "btree" ("promoter_id");



CREATE INDEX "idx_shifts_promotion" ON "public"."shifts" USING "btree" ("promotion_id");



CREATE INDEX "idx_shifts_status" ON "public"."shifts" USING "btree" ("status");



CREATE OR REPLACE TRIGGER "trg_custom_questions_updated" BEFORE UPDATE ON "public"."custom_questions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_products_updated" BEFORE UPDATE ON "public"."products" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_promoters_updated" BEFORE UPDATE ON "public"."promoters" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_promotions_updated" BEFORE UPDATE ON "public"."promotions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_shifts_updated" BEFORE UPDATE ON "public"."shifts" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



CREATE OR REPLACE TRIGGER "trg_sync_profile_to_promoter" AFTER INSERT OR UPDATE OF "role", "email", "full_name" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_to_promoter"();



ALTER TABLE ONLY "public"."client_promotions"
    ADD CONSTRAINT "client_promotions_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."client_promotions"
    ADD CONSTRAINT "client_promotions_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_question_answers"
    ADD CONSTRAINT "custom_question_answers_question_id_fkey" FOREIGN KEY ("question_id") REFERENCES "public"."custom_questions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_question_answers"
    ADD CONSTRAINT "custom_question_answers_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shifts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."custom_questions"
    ADD CONSTRAINT "custom_questions_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."customer_interactions"
    ADD CONSTRAINT "customer_interactions_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shifts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."feedback_notes"
    ADD CONSTRAINT "feedback_notes_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shifts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promoter_assignments"
    ADD CONSTRAINT "promoter_assignments_promoter_id_fkey" FOREIGN KEY ("promoter_id") REFERENCES "public"."promoters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promoter_assignments"
    ADD CONSTRAINT "promoter_assignments_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promoter_message_replies"
    ADD CONSTRAINT "promoter_message_replies_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."promoter_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promoter_messages"
    ADD CONSTRAINT "promoter_messages_promoter_id_fkey" FOREIGN KEY ("promoter_id") REFERENCES "public"."promoters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promoter_messages"
    ADD CONSTRAINT "promoter_messages_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."promotion_products"
    ADD CONSTRAINT "promotion_products_ean_fkey" FOREIGN KEY ("ean") REFERENCES "public"."products"("ean") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."promotion_products"
    ADD CONSTRAINT "promotion_products_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_customer_interaction_id_fkey" FOREIGN KEY ("customer_interaction_id") REFERENCES "public"."customer_interactions"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."sales"
    ADD CONSTRAINT "sales_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shifts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shift_photos"
    ADD CONSTRAINT "shift_photos_shift_id_fkey" FOREIGN KEY ("shift_id") REFERENCES "public"."shifts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."shifts"
    ADD CONSTRAINT "shifts_promoter_id_fkey" FOREIGN KEY ("promoter_id") REFERENCES "public"."promoters"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."shifts"
    ADD CONSTRAINT "shifts_promotion_id_fkey" FOREIGN KEY ("promotion_id") REFERENCES "public"."promotions"("id") ON DELETE CASCADE;



ALTER TABLE "public"."client_promotions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "client_promotions_read_own" ON "public"."client_promotions" FOR SELECT TO "authenticated" USING (("client_id" = "auth"."uid"()));



CREATE POLICY "client_promotions_staff_all" ON "public"."client_promotions" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



ALTER TABLE "public"."custom_question_answers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."custom_questions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."customer_interactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."feedback_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pilot_all_auth_customer_interactions" ON "public"."customer_interactions" TO "authenticated" USING (true) WITH CHECK (true);



ALTER TABLE "public"."products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promoter_assignments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promoter_message_replies" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promoter_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promoters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promotion_products" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."promotions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "rls_read_custom_question_answers" ON "public"."custom_question_answers" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shifts" "s"
  WHERE (("s"."id" = "custom_question_answers"."shift_id") AND "public"."app_can_see_promotion"("s"."promotion_id")))));



CREATE POLICY "rls_read_custom_questions" ON "public"."custom_questions" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("promotion_id"));



CREATE POLICY "rls_read_feedback_notes" ON "public"."feedback_notes" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shifts" "s"
  WHERE (("s"."id" = "feedback_notes"."shift_id") AND "public"."app_can_see_promotion"("s"."promotion_id")))));



CREATE POLICY "rls_read_products" ON "public"."products" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "rls_read_promoter_assignments" ON "public"."promoter_assignments" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("promotion_id"));



CREATE POLICY "rls_read_promoters" ON "public"."promoters" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."promoter_assignments" "pa"
  WHERE (("pa"."promoter_id" = "promoters"."id") AND "public"."app_can_see_promotion"("pa"."promotion_id")))));



CREATE POLICY "rls_read_promotion_products" ON "public"."promotion_products" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("promotion_id"));



CREATE POLICY "rls_read_promotions" ON "public"."promotions" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("id"));



CREATE POLICY "rls_read_sales" ON "public"."sales" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shifts" "s"
  WHERE (("s"."id" = "sales"."shift_id") AND "public"."app_can_see_promotion"("s"."promotion_id")))));



CREATE POLICY "rls_read_shift_photos" ON "public"."shift_photos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."shifts" "s"
  WHERE (("s"."id" = "shift_photos"."shift_id") AND "public"."app_can_see_promotion"("s"."promotion_id")))));



CREATE POLICY "rls_read_shifts" ON "public"."shifts" FOR SELECT TO "authenticated" USING ("public"."app_can_see_promotion"("promotion_id"));



CREATE POLICY "rls_staff_custom_question_answers" ON "public"."custom_question_answers" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_custom_questions" ON "public"."custom_questions" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_feedback_notes" ON "public"."feedback_notes" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_products" ON "public"."products" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promoter_assignments" ON "public"."promoter_assignments" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promoter_message_replies" ON "public"."promoter_message_replies" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promoter_messages" ON "public"."promoter_messages" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promoters" ON "public"."promoters" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promotion_products" ON "public"."promotion_products" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_promotions" ON "public"."promotions" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_sales" ON "public"."sales" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_shift_photos" ON "public"."shift_photos" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



CREATE POLICY "rls_staff_shifts" ON "public"."shifts" TO "authenticated" USING ("public"."app_is_staff"()) WITH CHECK ("public"."app_is_staff"());



ALTER TABLE "public"."sales" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shift_photos" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."shifts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "staff read all profiles" ON "public"."profiles" FOR SELECT TO "authenticated" USING ("public"."app_is_staff"());



CREATE POLICY "users insert own profile" ON "public"."profiles" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "users read own profile" ON "public"."profiles" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "id"));



CREATE POLICY "users update own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "id")) WITH CHECK ((("auth"."uid"() = "id") AND (NOT ("role" IS DISTINCT FROM ( SELECT "profiles_1"."role"
   FROM "public"."profiles" "profiles_1"
  WHERE ("profiles_1"."id" = "auth"."uid"()))))));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."app_can_see_promotion"("pid" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."app_can_see_promotion"("pid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_can_see_promotion"("pid" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."app_is_staff"() TO "anon";
GRANT ALL ON FUNCTION "public"."app_is_staff"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_is_staff"() TO "service_role";



GRANT ALL ON FUNCTION "public"."app_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."app_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."app_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_profile_to_promoter"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_profile_to_promoter"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_profile_to_promoter"() TO "service_role";


















GRANT ALL ON TABLE "public"."client_promotions" TO "anon";
GRANT ALL ON TABLE "public"."client_promotions" TO "authenticated";
GRANT ALL ON TABLE "public"."client_promotions" TO "service_role";



GRANT ALL ON TABLE "public"."custom_question_answers" TO "anon";
GRANT ALL ON TABLE "public"."custom_question_answers" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_question_answers" TO "service_role";



GRANT ALL ON TABLE "public"."custom_questions" TO "anon";
GRANT ALL ON TABLE "public"."custom_questions" TO "authenticated";
GRANT ALL ON TABLE "public"."custom_questions" TO "service_role";



GRANT ALL ON TABLE "public"."customer_interactions" TO "anon";
GRANT ALL ON TABLE "public"."customer_interactions" TO "authenticated";
GRANT ALL ON TABLE "public"."customer_interactions" TO "service_role";



GRANT ALL ON TABLE "public"."feedback_notes" TO "anon";
GRANT ALL ON TABLE "public"."feedback_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."feedback_notes" TO "service_role";



GRANT ALL ON TABLE "public"."products" TO "anon";
GRANT ALL ON TABLE "public"."products" TO "authenticated";
GRANT ALL ON TABLE "public"."products" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."promoter_assignments" TO "anon";
GRANT ALL ON TABLE "public"."promoter_assignments" TO "authenticated";
GRANT ALL ON TABLE "public"."promoter_assignments" TO "service_role";



GRANT ALL ON TABLE "public"."promoter_message_replies" TO "anon";
GRANT ALL ON TABLE "public"."promoter_message_replies" TO "authenticated";
GRANT ALL ON TABLE "public"."promoter_message_replies" TO "service_role";



GRANT ALL ON TABLE "public"."promoter_messages" TO "anon";
GRANT ALL ON TABLE "public"."promoter_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."promoter_messages" TO "service_role";



GRANT ALL ON TABLE "public"."promoters" TO "anon";
GRANT ALL ON TABLE "public"."promoters" TO "authenticated";
GRANT ALL ON TABLE "public"."promoters" TO "service_role";



GRANT ALL ON TABLE "public"."promotion_products" TO "anon";
GRANT ALL ON TABLE "public"."promotion_products" TO "authenticated";
GRANT ALL ON TABLE "public"."promotion_products" TO "service_role";



GRANT ALL ON TABLE "public"."promotions" TO "anon";
GRANT ALL ON TABLE "public"."promotions" TO "authenticated";
GRANT ALL ON TABLE "public"."promotions" TO "service_role";



GRANT ALL ON TABLE "public"."sales" TO "anon";
GRANT ALL ON TABLE "public"."sales" TO "authenticated";
GRANT ALL ON TABLE "public"."sales" TO "service_role";



GRANT ALL ON TABLE "public"."shift_photos" TO "anon";
GRANT ALL ON TABLE "public"."shift_photos" TO "authenticated";
GRANT ALL ON TABLE "public"."shift_photos" TO "service_role";



GRANT ALL ON TABLE "public"."shifts" TO "anon";
GRANT ALL ON TABLE "public"."shifts" TO "authenticated";
GRANT ALL ON TABLE "public"."shifts" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


  create policy "auth_read_photos"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using ((bucket_id = ANY (ARRAY['photos'::text, 'reports'::text])));



  create policy "auth_write_photos"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check ((bucket_id = ANY (ARRAY['photos'::text, 'reports'::text])));



