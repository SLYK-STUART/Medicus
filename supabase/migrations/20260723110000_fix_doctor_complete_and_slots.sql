-- FIX: Doctor cannot complete consultation — update_doctor_avg_on_complete
-- UPDATEs doctors.avg / recent durations, but enforce_doctor_client_updates
-- still sees auth.uid() as the doctor and raises "not allowed to update doctors".
--
-- Also: get_available_slots returns capacity for crowd coloring; create_appointment
-- rejects past time slots for the booking day (Africa/Kampala local time).

-- ---------------------------------------------------------------------------
-- Bypass for trusted doctor-table updates
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_doctor_client_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role app_role;
BEGIN
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

CREATE OR REPLACE FUNCTION public.update_doctor_avg_on_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_raw_ms double precision;
  v_duration_min double precision;
  v_existing jsonb;
  v_updated jsonb;
  v_vals double precision[];
  v_sorted double precision[];
  v_n integer;
  v_median double precision;
BEGIN
  IF NEW.status IS DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;
  IF NEW.doctor_id IS NULL
    OR NEW.consultation_started_at IS NULL
    OR NEW.consultation_completed_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Rolling avg update must pass enforce_doctor_client_updates while the
  -- completing doctor is still the JWT subject.
  PERFORM set_config('app.bypass_doctor_enforce', 'true', true);

  v_raw_ms := EXTRACT(EPOCH FROM (NEW.consultation_completed_at - NEW.consultation_started_at)) * 1000
    - COALESCE(NEW.total_paused_ms, 0);
  v_duration_min := v_raw_ms / 60000.0;

  IF v_duration_min <= 0 OR v_duration_min > 240 THEN
    RETURN NEW;
  END IF;

  SELECT recent_consultation_durations INTO v_existing
  FROM doctors WHERE id = NEW.doctor_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  v_existing := COALESCE(v_existing, '[]'::jsonb);
  v_updated := v_existing || to_jsonb(ROUND(v_duration_min::numeric, 2));

  IF jsonb_array_length(v_updated) > 30 THEN
    v_updated := (
      SELECT jsonb_agg(value ORDER BY ord)
      FROM (
        SELECT value, ord
        FROM jsonb_array_elements(v_updated) WITH ORDINALITY AS t(value, ord)
        ORDER BY ord DESC
        LIMIT 30
      ) keep
    );
  END IF;

  SELECT array_agg((value::text)::double precision)
  INTO v_vals
  FROM jsonb_array_elements(v_updated) AS t(value);

  v_n := COALESCE(array_length(v_vals, 1), 0);
  IF v_n = 0 THEN
    v_median := 15;
  ELSE
    SELECT array_agg(x ORDER BY x) INTO v_sorted FROM unnest(v_vals) AS x;
    IF v_n % 2 = 1 THEN
      v_median := v_sorted[(v_n + 1) / 2];
    ELSE
      v_median := (v_sorted[v_n / 2] + v_sorted[v_n / 2 + 1]) / 2.0;
    END IF;
  END IF;

  UPDATE doctors
  SET recent_consultation_durations = v_updated,
      avg_consultation_minutes = GREATEST(1, ROUND(v_median)::integer)
  WHERE id = NEW.doctor_id;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- get_available_slots: include capacity for crowd-level coloring
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_available_slots(uuid, uuid, date);

CREATE OR REPLACE FUNCTION public.get_available_slots(
  p_hospital_id uuid,
  p_department_id uuid,
  p_date date
)
RETURNS TABLE (slot text, remaining integer, capacity integer)
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
    capacity := v_capacity;
    RETURN NEXT;

    v_cursor_minutes := v_cursor_minutes + v_duration;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.get_available_slots(uuid, uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_available_slots(uuid, uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- create_appointment: reject past dates / past slots (Africa/Kampala)
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
  v_local_now timestamp;
  v_slot_start time;
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

  -- Past date / past slot guard (clinic local time).
  v_local_now := timezone('Africa/Kampala', now());
  IF p_scheduled_date < v_local_now::date THEN
    RAISE EXCEPTION 'Cannot book a past date.' USING ERRCODE = '22023';
  END IF;
  IF p_scheduled_time_slot IS NOT NULL AND p_scheduled_date = v_local_now::date THEN
    BEGIN
      v_slot_start := split_part(p_scheduled_time_slot, '-', 1)::time;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'Invalid time slot format.' USING ERRCODE = '22023';
    END;
    IF v_slot_start <= v_local_now::time THEN
      RAISE EXCEPTION 'Cannot book a time slot that has already started.'
        USING ERRCODE = '22023';
    END IF;
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

  INSERT INTO token_counters (hospital_id, department_id, date, last_token, updated_at)
  VALUES (p_hospital_id, p_department_id, p_scheduled_date, 0, now())
  ON CONFLICT (hospital_id, department_id, date) DO NOTHING;

  PERFORM 1
  FROM token_counters
  WHERE hospital_id = p_hospital_id
    AND department_id = p_department_id
    AND date = p_scheduled_date
  FOR UPDATE;

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
