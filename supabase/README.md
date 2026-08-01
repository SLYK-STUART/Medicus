# Supabase migration notes
#
# Project region: Frankfurt (eu-central-1)
#
# Step 1 — apply foundation migration
# ------------------------------------
# Option A (Dashboard):
#   1. Create a project in Frankfurt (eu-central-1).
#   2. Open SQL Editor.
#   3. Paste and run supabase/migrations/20260722120000_foundation.sql
#
# Option B (CLI, once linked):
#   npx supabase link --project-ref <ref>
#   npx supabase db push
#
# Super admin seed (Dashboard, after Step 1 SQL succeeds)
# ------------------------------------------------------
# 1. Authentication > Users > Add user (email + password).
# 2. Copy the user's UUID.
# 3. SQL Editor:
#
#    INSERT INTO public.profiles (id, email, display_name, role, hospital_id)
#    VALUES (
#      '<auth-user-uuid>',
#      'super@example.com',
#      'Super Admin',
#      'super_admin',
#      NULL
#    );
#
# Step 9 — notifications dispatcher, walk-in, referral/follow-up, sms_log
# ----------------------------------------------------------------------
# 1. Run supabase/migrations/20260722190000_step9_notifications_walkin_referrals.sql
# 2. Deploy Edge Function:
#      npx supabase functions deploy create-walk-in-patient
#    (also keep create-staff-account deployed from Step 4)
#
# Fix — receptionist check-in (after Step 9)
# ----------------------------------------
# Run supabase/migrations/20260723100000_fix_receptionist_checkin_queue_enforce.sql
# if check-in fails with "receptionist may only escalate priority or rejoin".
#
# Fix — doctor complete + booking slots
# -------------------------------------
# Run supabase/migrations/20260723110000_fix_doctor_complete_and_slots.sql
# if ending a consultation fails with "not allowed to update doctors".
# Also adds slot capacity to get_available_slots and rejects past slots on book.
#
# Pause / resume patient notifications
# ------------------------------------
# Run supabase/migrations/20260723120000_pause_resume_notifications.sql
# so patients get notified (and live queue UI updates) when a session is paused.
#
# Step 8 — notifications + remaining Realtime streams
# ----------------------------------------------------
# Run supabase/migrations/20260722180000_notifications.sql in SQL Editor.
#
# Optional smoke-test insert (as yourself, replace UUIDs):
#   INSERT INTO notifications (user_id, type, message)
#   VALUES ('<your-auth-uid>', 'info', 'Hello from Supabase');

# Step 6 — queue_entries + core queue RPCs
# ----------------------------------------
# Run supabase/migrations/20260722170000_queue_entries.sql in SQL Editor.
# Includes Realtime on queue_entries (streams wired in the Flutter repo).

# Step 5 — appointments schema + RPCs
# ------------------------------------
# Run supabase/migrations/20260722160000_appointments.sql in SQL Editor.
# No Edge Function deploy needed for this step (Postgres RPCs only).

# Step 4 — doctors table + create-staff-account Edge Function
# -----------------------------------------------------------
# 1. Run supabase/migrations/20260722150000_doctors.sql in SQL Editor.
# 2. Deploy the Edge Function (from repo root, with CLI logged in):
#
#    npx supabase login
#    npx supabase link --project-ref <YOUR_PROJECT_REF>
#    npx supabase functions deploy create-staff-account
#
# Project ref is the subdomain of SUPABASE_URL
# (https://<ref>.supabase.co).

# Step 3 — hospitals + departments Realtime
# -----------------------------------------
# Run supabase/migrations/20260722140000_hospitals_departments_realtime.sql
# in the SQL Editor (after Step 1 + Step 2 migrations).

# Step 2 — profiles Realtime (required for live profile stream)
# ------------------------------------------------------------
# Run supabase/migrations/20260722130000_profiles_realtime.sql in SQL Editor.
#
# Auth settings (recommended for local/dev testing):
#   Authentication > Providers > Email:
#   - turn OFF "Confirm email" so signup returns a session immediately.
#
# Flutter env
# -----------
# Copy .env.example → .env and set SUPABASE_URL + SUPABASE_ANON_KEY.
# Keep SUPABASE_SERVICE_ROLE_KEY out of the mobile app.
