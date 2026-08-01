-- Step 1: Schema foundation
-- Region target: Frankfurt (eu-central-1)
-- Tables: hospitals, departments, profiles
-- RLS: deny-by-default, then explicit policies

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- Enums (all domain enums upfront to avoid later ALTER TYPE churn)
-- ---------------------------------------------------------------------------
CREATE TYPE app_role AS ENUM (
  'super_admin',
  'hospital_admin',
  'receptionist',
  'doctor',
  'patient'
);

CREATE TYPE appointment_status AS ENUM (
  'booked',
  'checked_in',
  'completed',
  'skipped'
);

CREATE TYPE queue_status AS ENUM (
  'waiting',
  'called',
  'in_consultation',
  'paused',
  'skipped',
  'completed'
);

CREATE TYPE queue_priority AS ENUM (
  'critical',
  'urgent',
  'normal'
);

CREATE TYPE skip_policy AS ENUM (
  'end_of_queue',
  'after_current'
);

CREATE TYPE notification_threshold AS ENUM (
  'none',
  'five_ahead',
  'fifteen_min',
  'next'
);

-- ---------------------------------------------------------------------------
-- hospitals
-- ---------------------------------------------------------------------------
CREATE TABLE hospitals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  address text NOT NULL,
  contact_info text,
  skip_policy skip_policy NOT NULL DEFAULT 'end_of_queue',
  no_show_grace_minutes integer NOT NULL DEFAULT 5
    CHECK (no_show_grace_minutes > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX hospitals_name_idx ON hospitals (name);

-- ---------------------------------------------------------------------------
-- departments
-- ---------------------------------------------------------------------------
CREATE TABLE departments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  name text NOT NULL,
  open_time time NOT NULL DEFAULT '08:00',
  close_time time NOT NULL DEFAULT '17:00',
  slot_duration_minutes integer NOT NULL DEFAULT 30
    CHECK (slot_duration_minutes > 0),
  slot_capacity integer NOT NULL DEFAULT 5
    CHECK (slot_capacity > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT departments_open_before_close CHECK (open_time < close_time)
);

CREATE INDEX departments_hospital_id_idx ON departments (hospital_id);

-- ---------------------------------------------------------------------------
-- profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  email text,
  display_name text,
  phone_number text,
  role app_role NOT NULL,
  hospital_id uuid REFERENCES hospitals (id) ON DELETE SET NULL,
  fcm_token text, -- kept for a future push re-add; unused while FCM is dropped
  has_no_login_credentials boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES profiles (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT profiles_patient_hospital_null CHECK (
    role <> 'patient' OR hospital_id IS NULL
  ),
  CONSTRAINT profiles_super_admin_hospital_null CHECK (
    role <> 'super_admin' OR hospital_id IS NULL
  ),
  CONSTRAINT profiles_staff_requires_hospital CHECK (
    role NOT IN ('hospital_admin', 'receptionist', 'doctor')
    OR hospital_id IS NOT NULL
  )
);

CREATE INDEX profiles_hospital_id_idx ON profiles (hospital_id);
CREATE INDEX profiles_role_idx ON profiles (role);

-- ---------------------------------------------------------------------------
-- RLS helper: current caller's profile row
-- SECURITY DEFINER + fixed search_path avoids RLS recursion when policies
-- query profiles while evaluating profiles policies.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_profile()
RETURNS public.profiles
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT * FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_profile() TO authenticated;

CREATE OR REPLACE FUNCTION public.current_role()
RETURNS app_role
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_role() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_role() TO authenticated;

CREATE OR REPLACE FUNCTION public.current_hospital_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT hospital_id FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.current_hospital_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.current_hospital_id() TO authenticated;

CREATE OR REPLACE FUNCTION public.is_staff_of(target_hospital_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.hospital_id = target_hospital_id
      AND p.role IN ('hospital_admin', 'receptionist', 'doctor')
  );
$$;

REVOKE ALL ON FUNCTION public.is_staff_of(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_staff_of(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RLS: enable + policies
-- ---------------------------------------------------------------------------
ALTER TABLE hospitals ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- hospitals ---------------------------------------------------------------
CREATE POLICY hospitals_select_authenticated
  ON hospitals FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY hospitals_insert_super_admin
  ON hospitals FOR INSERT
  TO authenticated
  WITH CHECK (public.current_role() = 'super_admin');

CREATE POLICY hospitals_update_super_or_own_admin
  ON hospitals FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND id = public.current_hospital_id()
    )
  )
  WITH CHECK (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND id = public.current_hospital_id()
    )
  );

CREATE POLICY hospitals_delete_super_admin
  ON hospitals FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

-- departments -------------------------------------------------------------
CREATE POLICY departments_select_authenticated
  ON departments FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY departments_insert_super_or_hospital_admin
  ON departments FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND hospital_id = public.current_hospital_id()
    )
  );

CREATE POLICY departments_update_super_or_hospital_admin
  ON departments FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND hospital_id = public.current_hospital_id()
    )
  )
  WITH CHECK (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND hospital_id = public.current_hospital_id()
    )
  );

CREATE POLICY departments_delete_super_or_hospital_admin
  ON departments FOR DELETE
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR (
      public.current_role() = 'hospital_admin'
      AND hospital_id = public.current_hospital_id()
    )
  );

-- profiles ----------------------------------------------------------------
-- SELECT: self, super_admin, or staff of the same hospital
CREATE POLICY profiles_select_self_super_or_staff
  ON profiles FOR SELECT
  TO authenticated
  USING (
    id = auth.uid()
    OR public.current_role() = 'super_admin'
    OR (
      hospital_id IS NOT NULL
      AND public.is_staff_of(hospital_id)
    )
  );

-- INSERT: patient self-signup only (staff/hospital_admin via service role Edge Function)
CREATE POLICY profiles_insert_patient_self
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (
    id = auth.uid()
    AND role = 'patient'
    AND hospital_id IS NULL
  );

-- Super admin may insert any profile (used rarely; staff creation prefers service role)
CREATE POLICY profiles_insert_super_admin
  ON profiles FOR INSERT
  TO authenticated
  WITH CHECK (public.current_role() = 'super_admin');

-- UPDATE: self or super_admin
CREATE POLICY profiles_update_self_or_super
  ON profiles FOR UPDATE
  TO authenticated
  USING (
    id = auth.uid()
    OR public.current_role() = 'super_admin'
  )
  WITH CHECK (
    id = auth.uid()
    OR public.current_role() = 'super_admin'
  );

-- DELETE: super_admin only
CREATE POLICY profiles_delete_super_admin
  ON profiles FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

-- ---------------------------------------------------------------------------
-- Super admin bootstrap notes (run manually in Dashboard SQL editor AFTER
-- creating the auth user via Authentication > Users > Add user):
--
--   INSERT INTO public.profiles (id, email, display_name, role, hospital_id)
--   VALUES (
--     '<auth-user-uuid-from-dashboard>',
--     'super@example.com',
--     'Super Admin',
--     'super_admin',
--     NULL
--   );
-- ---------------------------------------------------------------------------
