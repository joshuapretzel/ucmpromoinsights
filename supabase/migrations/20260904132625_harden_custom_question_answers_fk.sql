-- DB-level backstop against the confirmed data-loss vector: deleting a custom
-- question used to cascade-delete every answer ever given to it (30 answers
-- were lost this way in production). The app now soft-deletes questions
-- (custom_questions.active = false) instead of hard-deleting, but this changes
-- the foreign key so that even an out-of-band hard DELETE (e.g. straight from
-- the Supabase dashboard) is BLOCKED while answers still exist, rather than
-- silently taking the answers with it.
ALTER TABLE "public"."custom_question_answers"
    DROP CONSTRAINT "custom_question_answers_question_id_fkey";

ALTER TABLE "public"."custom_question_answers"
    ADD CONSTRAINT "custom_question_answers_question_id_fkey"
    FOREIGN KEY ("question_id")
    REFERENCES "public"."custom_questions"("id")
    ON DELETE RESTRICT;
