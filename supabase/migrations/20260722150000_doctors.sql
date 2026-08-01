-- Step 4: doctors table + RLS + Realtime
-- Required so create-staff-account can insert doctor rows and the app can list them.

CREATE TABLE doctors (
  id uuid PRIMARY KEY REFERENCES profiles (id) ON DELETE CASCADE,
  display_name text,
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES departments (id) ON DELETE RESTRICT,
  room_number text,
  avg_consultation_minutes integer NOT NULL DEFAULT 15
    CHECK (avg_consultation_minutes > 0),
  recent_consultation_durations jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX doctors_hospital_id_idx ON doctors (hospital_id);
CREATE INDEX doctors_hospital_department_idx ON doctors (hospital_id, department_id);

ALTER TABLE doctors ENABLE ROW LEVEL SECURITY;

CREATE POLICY doctors_select_authenticated
  ON doctors FOR SELECT
  TO authenticated
  USING (true);

-- Client inserts denied — staff creation uses service role in Edge Function.
-- No INSERT policy for authenticated.

CREATE POLICY doctors_update_super_admin
  ON doctors FOR UPDATE
  TO authenticated
  USING (public.current_role() = 'super_admin')
  WITH CHECK (public.current_role() = 'super_admin');

CREATE POLICY doctors_update_hospital_admin
  ON doctors FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'hospital_admin'
    AND hospital_id = public.current_hospital_id()
  )
  WITH CHECK (
    public.current_role() = 'hospital_admin'
    AND hospital_id = public.current_hospital_id()
  );

CREATE POLICY doctors_delete_super_admin
  ON doctors FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

-- hospital_admin may only change department_id / room_number (mirrors Firestore rules).
-- Service-role / trigger backends (auth.uid() IS NULL) are unrestricted.
CREATE OR REPLACE FUNCTION public.enforce_doctor_client_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role app_role;
BEGIN
  -- Trusted server-side updates (rolling avg on consultation complete).
  IF COALESCE(current_setting('app.bypass_doctor_enforce', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  caller_role := public.current_role();

  IF caller_role = 'super_admin' THEN
    RETURN NEW;
  END IF;

  IF caller_role = 'hospital_admin' THEN
    IF NEW.id IS DISTINCT FROM OLD.id
      OR NEW.display_name IS DISTINCT FROM OLD.display_name
      OR NEW.hospital_id IS DISTINCT FROM OLD.hospital_id
      OR NEW.avg_consultation_minutes IS DISTINCT FROM OLD.avg_consultation_minutes
      OR NEW.recent_consultation_durations IS DISTINCT FROM OLD.recent_consultation_durations
      OR NEW.created_at IS DISTINCT FROM OLD.created_at
    THEN
      RAISE EXCEPTION 'hospital_admin may only update department_id and room_number'
        USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'not allowed to update doctors'
    USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER doctors_enforce_client_updates
  BEFORE UPDATE ON doctors
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_doctor_client_updates();

ALTER PUBLICATION supabase_realtime ADD TABLE public.doctors;
