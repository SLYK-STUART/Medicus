-- Step 5: appointments + token_counters + visits + RPCs + Realtime
-- Region: Frankfurt (eu-central-1)

-- ---------------------------------------------------------------------------
-- visits (created here so appointments.visit_id can reference it later;
-- rows are written by referral RPC in a later step)
-- ---------------------------------------------------------------------------
CREATE TABLE visits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  origin_appointment_id uuid, -- FK added after appointments exists
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX visits_patient_id_idx ON visits (patient_id);
CREATE INDEX visits_hospital_id_idx ON visits (hospital_id);

-- ---------------------------------------------------------------------------
-- token_counters (server/RPC only)
-- ---------------------------------------------------------------------------
CREATE TABLE token_counters (
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES departments (id) ON DELETE CASCADE,
  date date NOT NULL,
  last_token integer NOT NULL DEFAULT 0 CHECK (last_token >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (hospital_id, department_id, date)
);

-- ---------------------------------------------------------------------------
-- appointments
-- ---------------------------------------------------------------------------
CREATE TABLE appointments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  patient_name text NOT NULL,
  patient_phone_number text,
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  department_id uuid NOT NULL REFERENCES departments (id) ON DELETE RESTRICT,
  doctor_id uuid REFERENCES doctors (id) ON DELETE SET NULL,
  scheduled_date date NOT NULL,
  scheduled_time_slot text,
  token_number integer NOT NULL CHECK (token_number > 0),
  status appointment_status NOT NULL DEFAULT 'booked',
  visit_id uuid REFERENCES visits (id) ON DELETE SET NULL,
  is_recurring boolean NOT NULL DEFAULT false,
  recurring_parent_id uuid REFERENCES appointments (id) ON DELETE SET NULL,
  booked_by uuid NOT NULL REFERENCES profiles (id) ON DELETE RESTRICT,
  source text NOT NULL DEFAULT 'patient_booking',
  checked_in_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX appointments_patient_date_idx
  ON appointments (patient_id, scheduled_date DESC);
CREATE INDEX appointments_hospital_date_idx
  ON appointments (hospital_id, scheduled_date);
CREATE INDEX appointments_hospital_dept_date_idx
  ON appointments (hospital_id, department_id, scheduled_date);
CREATE INDEX appointments_doctor_hospital_idx
  ON appointments (doctor_id, hospital_id);
CREATE INDEX appointments_booked_by_hospital_idx
  ON appointments (booked_by, hospital_id);
CREATE INDEX appointments_slot_capacity_idx
  ON appointments (hospital_id, department_id, scheduled_date, scheduled_time_slot, status);

ALTER TABLE visits
  ADD CONSTRAINT visits_origin_appointment_id_fkey
  FOREIGN KEY (origin_appointment_id) REFERENCES appointments (id) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
ALTER TABLE visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE token_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;

-- visits: read for patient/staff/super; writes via RPC/service role only
CREATE POLICY visits_select_own_staff_or_super
  ON visits FOR SELECT
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR patient_id = auth.uid()
    OR public.is_staff_of(hospital_id)
  );

-- token_counters: no client policies (RPC SECURITY DEFINER only)

-- appointments SELECT
CREATE POLICY appointments_select_patient_staff_super
  ON appointments FOR SELECT
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR patient_id = auth.uid()
    OR public.is_staff_of(hospital_id)
  );

-- appointments INSERT denied for clients (create_appointment RPC only)

CREATE POLICY appointments_update_staff_or_super
  ON appointments FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR public.is_staff_of(hospital_id)
  )
  WITH CHECK (
    public.current_role() = 'super_admin'
    OR public.is_staff_of(hospital_id)
  );

CREATE POLICY appointments_delete_super_admin
  ON appointments FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

ALTER PUBLICATION supabase_realtime ADD TABLE public.appointments;

-- ---------------------------------------------------------------------------
-- RPC: create_appointment
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_appointment(
  p_hospital_id uuid,
  p_department_id uuid,
  p_scheduled_date date,
  p_patient_id uuid DEFAULT NULL,
  p_doctor_id uuid DEFAULT NULL,
  p_scheduled_time_slot text DEFAULT NULL
)
RETURNS TABLE (appointment_id uuid, token_number integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_caller_hospital_id uuid;
  v_patient_id uuid;
  v_patient_name text;
  v_patient_phone text;
  v_source text;
  v_dept_hospital_id uuid;
  v_capacity integer;
  v_slot_count integer;
  v_next_token integer;
  v_appointment_id uuid;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role, hospital_id INTO v_caller_role, v_caller_hospital_id
  FROM profiles WHERE id = v_caller_id;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'Caller profile not found.' USING ERRCODE = '42501';
  END IF;

  IF p_hospital_id IS NULL OR p_department_id IS NULL OR p_scheduled_date IS NULL THEN
    RAISE EXCEPTION 'hospitalId, departmentId, and scheduledDate are required.'
      USING ERRCODE = '22023';
  END IF;

  IF v_caller_role = 'patient' THEN
    v_patient_id := v_caller_id;
    v_source := 'patient_booking';
  ELSIF v_caller_role = 'receptionist' THEN
    IF v_caller_hospital_id IS DISTINCT FROM p_hospital_id THEN
      RAISE EXCEPTION 'Cannot book outside your own hospital.' USING ERRCODE = '42501';
    END IF;
    IF p_patient_id IS NULL THEN
      RAISE EXCEPTION 'patientId is required when a receptionist books on a patient''s behalf.'
        USING ERRCODE = '22023';
    END IF;
    v_patient_id := p_patient_id;
    v_source := 'receptionist_booking';
  ELSE
    RAISE EXCEPTION 'Only a patient or a receptionist may create an appointment.'
      USING ERRCODE = '42501';
  END IF;

  -- FIX (vs Firebase): ensure department belongs to the hospital being booked.
  SELECT hospital_id, slot_capacity
  INTO v_dept_hospital_id, v_capacity
  FROM departments
  WHERE id = p_department_id;

  IF v_dept_hospital_id IS NULL THEN
    RAISE EXCEPTION 'Department not found.' USING ERRCODE = 'P0002';
  END IF;
  IF v_dept_hospital_id IS DISTINCT FROM p_hospital_id THEN
    RAISE EXCEPTION 'departmentId must belong to hospitalId.' USING ERRCODE = '22023';
  END IF;

  SELECT
    COALESCE(display_name, 'Unknown'),
    phone_number
  INTO v_patient_name, v_patient_phone
  FROM profiles
  WHERE id = v_patient_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Patient profile not found.' USING ERRCODE = 'P0002';
  END IF;

  -- Serialize bookings for this hospital/dept/day (counter row lock).
  -- FIX (vs Firebase): capacity check + token increment + insert run under
  -- one locked critical section so concurrent bookings can't overfill a slot.
  INSERT INTO token_counters (hospital_id, department_id, date, last_token, updated_at)
  VALUES (p_hospital_id, p_department_id, p_scheduled_date, 0, now())
  ON CONFLICT (hospital_id, department_id, date) DO NOTHING;

  PERFORM 1
  FROM token_counters
  WHERE hospital_id = p_hospital_id
    AND department_id = p_department_id
    AND date = p_scheduled_date
  FOR UPDATE;

  -- Capacity check only when a slot was requested (walk-ins omit the slot).
  IF p_scheduled_time_slot IS NOT NULL THEN
    SELECT COUNT(*)::integer INTO v_slot_count
    FROM appointments
    WHERE hospital_id = p_hospital_id
      AND department_id = p_department_id
      AND scheduled_date = p_scheduled_date
      AND scheduled_time_slot = p_scheduled_time_slot
      AND status IN ('booked', 'checked_in');

    IF v_slot_count >= COALESCE(v_capacity, 5) THEN
      RAISE EXCEPTION 'This time slot is fully booked. Please choose another.'
        USING ERRCODE = '53100';
    END IF;
  END IF;

  UPDATE token_counters
  SET last_token = last_token + 1,
      updated_at = now()
  WHERE hospital_id = p_hospital_id
    AND department_id = p_department_id
    AND date = p_scheduled_date
  RETURNING last_token INTO v_next_token;

  INSERT INTO appointments (
    patient_id,
    patient_name,
    patient_phone_number,
    hospital_id,
    department_id,
    doctor_id,
    scheduled_date,
    scheduled_time_slot,
    token_number,
    status,
    visit_id,
    is_recurring,
    recurring_parent_id,
    booked_by,
    source
  ) VALUES (
    v_patient_id,
    v_patient_name,
    v_patient_phone,
    p_hospital_id,
    p_department_id,
    p_doctor_id,
    p_scheduled_date,
    p_scheduled_time_slot,
    v_next_token,
    'booked',
    NULL,
    false,
    NULL,
    v_caller_id,
    v_source
  )
  RETURNING id INTO v_appointment_id;

  appointment_id := v_appointment_id;
  token_number := v_next_token;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_appointment(uuid, uuid, date, uuid, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_appointment(uuid, uuid, date, uuid, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: get_available_slots
-- SECURITY DEFINER so patients can see remaining capacity without reading
-- other patients' appointment rows (blocked by RLS for patient role).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_available_slots(
  p_hospital_id uuid,
  p_department_id uuid,
  p_date date
)
RETURNS TABLE (slot text, remaining integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_open time;
  v_close time;
  v_duration integer;
  v_capacity integer;
  v_dept_hospital_id uuid;
  v_cursor_minutes integer;
  v_close_minutes integer;
  v_slot text;
  v_taken integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  IF p_hospital_id IS NULL OR p_department_id IS NULL OR p_date IS NULL THEN
    RAISE EXCEPTION 'hospitalId, departmentId, and date are required.'
      USING ERRCODE = '22023';
  END IF;

  SELECT open_time, close_time, slot_duration_minutes, slot_capacity, hospital_id
  INTO v_open, v_close, v_duration, v_capacity, v_dept_hospital_id
  FROM departments
  WHERE id = p_department_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Department not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_dept_hospital_id IS DISTINCT FROM p_hospital_id THEN
    RAISE EXCEPTION 'departmentId must belong to hospitalId.' USING ERRCODE = '22023';
  END IF;

  v_capacity := COALESCE(v_capacity, 5);
  v_duration := COALESCE(v_duration, 30);
  v_open := COALESCE(v_open, '08:00'::time);
  v_close := COALESCE(v_close, '17:00'::time);

  v_cursor_minutes := (EXTRACT(HOUR FROM v_open)::integer * 60) + EXTRACT(MINUTE FROM v_open)::integer;
  v_close_minutes := (EXTRACT(HOUR FROM v_close)::integer * 60) + EXTRACT(MINUTE FROM v_close)::integer;

  WHILE v_cursor_minutes + v_duration <= v_close_minutes LOOP
    v_slot := lpad(((v_cursor_minutes / 60)::integer)::text, 2, '0')
      || ':'
      || lpad(((v_cursor_minutes % 60)::integer)::text, 2, '0')
      || '-'
      || lpad((((v_cursor_minutes + v_duration) / 60)::integer)::text, 2, '0')
      || ':'
      || lpad((((v_cursor_minutes + v_duration) % 60)::integer)::text, 2, '0');

    SELECT COUNT(*)::integer INTO v_taken
    FROM appointments
    WHERE hospital_id = p_hospital_id
      AND department_id = p_department_id
      AND scheduled_date = p_date
      AND scheduled_time_slot = v_slot
      AND status IN ('booked', 'checked_in');

    slot := v_slot;
    remaining := v_capacity - v_taken;
    RETURN NEXT;

    v_cursor_minutes := v_cursor_minutes + v_duration;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.get_available_slots(uuid, uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_slots(uuid, uuid, date) TO authenticated;
