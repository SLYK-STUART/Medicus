-- Step 6: queue_entries + core queue RPCs + Realtime
-- FIX: check_in is a single transactional RPC (queue row + appointment status).

-- ---------------------------------------------------------------------------
-- queue_entries (flat replacement for nested Firestore path)
-- ---------------------------------------------------------------------------
CREATE TABLE queue_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hospital_id uuid NOT NULL REFERENCES hospitals (id) ON DELETE CASCADE,
  date date NOT NULL,
  department_id uuid NOT NULL REFERENCES departments (id) ON DELETE RESTRICT,
  appointment_id uuid NOT NULL REFERENCES appointments (id) ON DELETE CASCADE,
  patient_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  patient_name text NOT NULL DEFAULT 'Unknown',
  patient_phone_number text,
  doctor_id uuid REFERENCES doctors (id) ON DELETE SET NULL,
  token_number integer NOT NULL CHECK (token_number > 0),
  checked_in_at timestamptz NOT NULL DEFAULT now(),
  consultation_started_at timestamptz,
  consultation_completed_at timestamptz,
  warned_at timestamptz,
  grace_deadline timestamptz,
  grace_minutes integer,
  priority queue_priority NOT NULL DEFAULT 'normal',
  priority_rank integer GENERATED ALWAYS AS (
    CASE priority
      WHEN 'critical' THEN 0
      WHEN 'urgent' THEN 1
      ELSE 2
    END
  ) STORED,
  status queue_status NOT NULL DEFAULT 'waiting',
  last_notified_threshold notification_threshold NOT NULL DEFAULT 'none',
  patients_ahead integer,
  called_at timestamptz,
  skipped_at timestamptz,
  paused_at timestamptz,
  total_paused_ms bigint NOT NULL DEFAULT 0 CHECK (total_paused_ms >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX queue_entries_live_idx
  ON queue_entries (hospital_id, date, department_id, status, priority_rank, checked_in_at);

CREATE INDEX queue_entries_patient_status_idx
  ON queue_entries (hospital_id, date, department_id, patient_id, status);

CREATE INDEX queue_entries_doctor_status_idx
  ON queue_entries (hospital_id, date, department_id, doctor_id, status);

CREATE INDEX queue_entries_skipped_idx
  ON queue_entries (hospital_id, date, department_id)
  WHERE status = 'skipped';

ALTER TABLE queue_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY queue_entries_select_patient_staff_super
  ON queue_entries FOR SELECT
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR patient_id = auth.uid()
    OR public.is_staff_of(hospital_id)
  );

-- Client inserts denied — use check_in RPC (transactional).
-- Client deletes denied except super_admin.

CREATE POLICY queue_entries_delete_super_admin
  ON queue_entries FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

CREATE POLICY queue_entries_update_doctor
  ON queue_entries FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'super_admin'
    OR (public.current_role() = 'doctor' AND hospital_id = public.current_hospital_id())
  )
  WITH CHECK (
    public.current_role() = 'super_admin'
    OR (public.current_role() = 'doctor' AND hospital_id = public.current_hospital_id())
  );

CREATE POLICY queue_entries_update_receptionist
  ON queue_entries FOR UPDATE
  TO authenticated
  USING (
    public.current_role() = 'receptionist'
    AND hospital_id = public.current_hospital_id()
  )
  WITH CHECK (
    public.current_role() = 'receptionist'
    AND hospital_id = public.current_hospital_id()
  );

-- Receptionist may only escalate priority or rejoin skipped→waiting.
CREATE OR REPLACE FUNCTION public.enforce_queue_entry_client_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller_role app_role;
BEGIN
  -- Trusted server-side updates (resequence / notification trigger, RPCs).
  -- See 20260723100000_fix_receptionist_checkin_queue_enforce.sql.
  IF COALESCE(current_setting('app.bypass_queue_enforce', true), '') = 'true' THEN
    RETURN NEW;
  END IF;

  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  caller_role := public.current_role();

  IF caller_role IN ('super_admin', 'doctor') THEN
    RETURN NEW;
  END IF;

  IF caller_role = 'receptionist' THEN
    -- escalate: only priority may change (priority_rank is generated)
    IF NEW.status IS NOT DISTINCT FROM OLD.status
      AND NEW.appointment_id IS NOT DISTINCT FROM OLD.appointment_id
      AND NEW.patient_id IS NOT DISTINCT FROM OLD.patient_id
      AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
      AND NEW.token_number IS NOT DISTINCT FROM OLD.token_number
      AND NEW.checked_in_at IS NOT DISTINCT FROM OLD.checked_in_at
      AND NEW.consultation_started_at IS NOT DISTINCT FROM OLD.consultation_started_at
      AND NEW.consultation_completed_at IS NOT DISTINCT FROM OLD.consultation_completed_at
      AND NEW.warned_at IS NOT DISTINCT FROM OLD.warned_at
      AND NEW.grace_deadline IS NOT DISTINCT FROM OLD.grace_deadline
      AND NEW.grace_minutes IS NOT DISTINCT FROM OLD.grace_minutes
      AND NEW.last_notified_threshold IS NOT DISTINCT FROM OLD.last_notified_threshold
      AND NEW.patients_ahead IS NOT DISTINCT FROM OLD.patients_ahead
      AND NEW.called_at IS NOT DISTINCT FROM OLD.called_at
      AND NEW.skipped_at IS NOT DISTINCT FROM OLD.skipped_at
      AND NEW.paused_at IS NOT DISTINCT FROM OLD.paused_at
      AND NEW.total_paused_ms IS NOT DISTINCT FROM OLD.total_paused_ms
      AND NEW.hospital_id IS NOT DISTINCT FROM OLD.hospital_id
      AND NEW.date IS NOT DISTINCT FROM OLD.date
      AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
      AND NEW.patient_name IS NOT DISTINCT FROM OLD.patient_name
      AND NEW.patient_phone_number IS NOT DISTINCT FROM OLD.patient_phone_number
      AND NEW.priority IS DISTINCT FROM OLD.priority
    THEN
      RETURN NEW;
    END IF;

    -- rejoin: skipped → waiting, may touch checked_in_at + last_notified_threshold
    IF OLD.status = 'skipped'
      AND NEW.status = 'waiting'
      AND NEW.appointment_id IS NOT DISTINCT FROM OLD.appointment_id
      AND NEW.patient_id IS NOT DISTINCT FROM OLD.patient_id
      AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
      AND NEW.token_number IS NOT DISTINCT FROM OLD.token_number
      AND NEW.priority IS NOT DISTINCT FROM OLD.priority
      AND NEW.consultation_started_at IS NOT DISTINCT FROM OLD.consultation_started_at
      AND NEW.consultation_completed_at IS NOT DISTINCT FROM OLD.consultation_completed_at
      AND NEW.warned_at IS NOT DISTINCT FROM OLD.warned_at
      AND NEW.grace_deadline IS NOT DISTINCT FROM OLD.grace_deadline
      AND NEW.grace_minutes IS NOT DISTINCT FROM OLD.grace_minutes
      AND NEW.patients_ahead IS NOT DISTINCT FROM OLD.patients_ahead
      AND NEW.called_at IS NOT DISTINCT FROM OLD.called_at
      AND NEW.paused_at IS NOT DISTINCT FROM OLD.paused_at
      AND NEW.total_paused_ms IS NOT DISTINCT FROM OLD.total_paused_ms
      AND NEW.hospital_id IS NOT DISTINCT FROM OLD.hospital_id
      AND NEW.date IS NOT DISTINCT FROM OLD.date
      AND NEW.department_id IS NOT DISTINCT FROM OLD.department_id
    THEN
      RETURN NEW;
    END IF;

    RAISE EXCEPTION 'receptionist may only escalate priority or rejoin a skipped patient'
      USING ERRCODE = '42501';
  END IF;

  RAISE EXCEPTION 'not allowed to update queue_entries' USING ERRCODE = '42501';
END;
$$;

CREATE TRIGGER queue_entries_enforce_client_updates
  BEFORE UPDATE ON queue_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_queue_entry_client_updates();

ALTER PUBLICATION supabase_realtime ADD TABLE public.queue_entries;

-- ---------------------------------------------------------------------------
-- RPC: check_in (transactional queue + appointment)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_in(
  p_appointment_id uuid,
  p_hospital_id uuid,
  p_department_id uuid,
  p_date date,
  p_priority queue_priority DEFAULT 'normal',
  p_doctor_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_caller_hospital_id uuid;
  v_appt appointments%ROWTYPE;
  v_entry_id uuid;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role, hospital_id INTO v_caller_role, v_caller_hospital_id
  FROM profiles WHERE id = v_caller_id;

  IF v_caller_role NOT IN ('receptionist', 'doctor', 'super_admin') THEN
    RAISE EXCEPTION 'Only receptionist or doctor may check in patients.' USING ERRCODE = '42501';
  END IF;

  IF v_caller_role <> 'super_admin'
    AND v_caller_hospital_id IS DISTINCT FROM p_hospital_id THEN
    RAISE EXCEPTION 'Cannot check in outside your hospital.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Appointment not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_appt.hospital_id IS DISTINCT FROM p_hospital_id
    OR v_appt.department_id IS DISTINCT FROM p_department_id
    OR v_appt.scheduled_date IS DISTINCT FROM p_date THEN
    RAISE EXCEPTION 'Appointment does not match hospital/department/date.'
      USING ERRCODE = '22023';
  END IF;

  IF v_appt.status <> 'booked' THEN
    RAISE EXCEPTION 'Appointment is not in booked status.' USING ERRCODE = '55000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM queue_entries
    WHERE appointment_id = p_appointment_id
      AND status IN ('waiting', 'called', 'in_consultation', 'paused')
  ) THEN
    RAISE EXCEPTION 'Patient is already in the queue for this appointment.'
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO queue_entries (
    hospital_id,
    date,
    department_id,
    appointment_id,
    patient_id,
    patient_name,
    patient_phone_number,
    doctor_id,
    token_number,
    priority,
    status,
    last_notified_threshold,
    checked_in_at
  ) VALUES (
    p_hospital_id,
    p_date,
    p_department_id,
    p_appointment_id,
    v_appt.patient_id,
    v_appt.patient_name,
    v_appt.patient_phone_number,
    COALESCE(p_doctor_id, v_appt.doctor_id),
    v_appt.token_number,
    p_priority,
    'waiting',
    'none',
    now()
  )
  RETURNING id INTO v_entry_id;

  UPDATE appointments
  SET status = 'checked_in',
      checked_in_at = now()
  WHERE id = p_appointment_id;

  RETURN v_entry_id;
END;
$$;

REVOKE ALL ON FUNCTION public.check_in(uuid, uuid, uuid, date, queue_priority, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_in(uuid, uuid, uuid, date, queue_priority, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: call_next_patient
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_next_patient(
  p_hospital_id uuid,
  p_date date
)
RETURNS TABLE (entry_id uuid, token_number integer, patient_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_department_id uuid;
  v_active queue_entries%ROWTYPE;
  v_target queue_entries%ROWTYPE;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role <> 'doctor' THEN
    RAISE EXCEPTION 'Only a doctor may call the next patient.' USING ERRCODE = '42501';
  END IF;

  SELECT department_id INTO v_department_id FROM doctors WHERE id = v_caller_id;
  IF v_department_id IS NULL THEN
    RAISE EXCEPTION 'No doctor profile found for this account.' USING ERRCODE = '55000';
  END IF;

  -- Auto-skip overdue "called" patient for this doctor (grace backstop).
  SELECT * INTO v_active
  FROM queue_entries
  WHERE hospital_id = p_hospital_id
    AND date = p_date
    AND department_id = v_department_id
    AND doctor_id = v_caller_id
    AND status IN ('called', 'in_consultation')
  LIMIT 1
  FOR UPDATE;

  IF FOUND THEN
    IF v_active.status = 'called'
      AND v_active.grace_deadline IS NOT NULL
      AND v_active.grace_deadline < now() THEN
      UPDATE queue_entries
      SET status = 'skipped',
          doctor_id = NULL,
          skipped_at = now()
      WHERE id = v_active.id;

      UPDATE appointments
      SET status = 'skipped'
      WHERE id = v_active.appointment_id;
    ELSE
      RAISE EXCEPTION 'You already have an active patient. Complete the current consultation before calling the next one.'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  -- Prefer a waiting entry already assigned to this doctor.
  SELECT * INTO v_target
  FROM queue_entries
  WHERE hospital_id = p_hospital_id
    AND date = p_date
    AND department_id = v_department_id
    AND doctor_id = v_caller_id
    AND status = 'waiting'
  ORDER BY priority_rank, checked_in_at
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    SELECT * INTO v_target
    FROM queue_entries
    WHERE hospital_id = p_hospital_id
      AND date = p_date
      AND department_id = v_department_id
      AND doctor_id IS NULL
      AND status = 'waiting'
    ORDER BY priority_rank, checked_in_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No patients waiting.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE queue_entries
  SET doctor_id = v_caller_id,
      status = 'called',
      called_at = now(),
      warned_at = NULL,
      grace_deadline = NULL,
      grace_minutes = NULL
  WHERE id = v_target.id;

  UPDATE appointments
  SET doctor_id = v_caller_id
  WHERE id = v_target.appointment_id;

  entry_id := v_target.id;
  token_number := v_target.token_number;
  patient_id := v_target.patient_id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.call_next_patient(uuid, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.call_next_patient(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: update_queue_status (doctor status machine + appointment sync)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_queue_status(
  p_entry_id uuid,
  p_new_status queue_status
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_entry queue_entries%ROWTYPE;
  v_allowed boolean := false;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('doctor', 'super_admin') THEN
    RAISE EXCEPTION 'Only a doctor may change queue status this way.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry FROM queue_entries WHERE id = p_entry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  IF v_caller_role = 'doctor' AND v_entry.hospital_id IS DISTINCT FROM public.current_hospital_id() THEN
    RAISE EXCEPTION 'Cannot update queue outside your hospital.' USING ERRCODE = '42501';
  END IF;

  v_allowed := CASE v_entry.status
    WHEN 'waiting' THEN p_new_status IN ('called', 'skipped')
    WHEN 'called' THEN p_new_status IN ('in_consultation', 'skipped')
    WHEN 'in_consultation' THEN p_new_status IN ('completed', 'paused')
    WHEN 'paused' THEN p_new_status = 'in_consultation'
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Cannot move from "%" to "%"', v_entry.status, p_new_status
      USING ERRCODE = '22023';
  END IF;

  UPDATE queue_entries SET
    status = p_new_status,
    consultation_started_at = CASE
      WHEN p_new_status = 'in_consultation' THEN COALESCE(consultation_started_at, now())
      ELSE consultation_started_at
    END,
    consultation_completed_at = CASE
      WHEN p_new_status = 'completed' THEN now()
      ELSE consultation_completed_at
    END,
    warned_at = CASE WHEN p_new_status = 'in_consultation' THEN NULL ELSE warned_at END,
    grace_deadline = CASE WHEN p_new_status = 'in_consultation' THEN NULL ELSE grace_deadline END,
    grace_minutes = CASE WHEN p_new_status = 'in_consultation' THEN NULL ELSE grace_minutes END,
    paused_at = CASE WHEN p_new_status = 'paused' THEN now() ELSE paused_at END
  WHERE id = p_entry_id;

  IF p_new_status = 'completed' THEN
    UPDATE appointments SET status = 'completed' WHERE id = v_entry.appointment_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_queue_status(uuid, queue_status) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_queue_status(uuid, queue_status) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: mark_queue_skipped
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_queue_skipped(p_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_entry queue_entries%ROWTYPE;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('doctor', 'super_admin') THEN
    RAISE EXCEPTION 'Only a doctor may mark skipped.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry FROM queue_entries WHERE id = p_entry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE queue_entries
  SET status = 'skipped',
      doctor_id = NULL,
      skipped_at = now()
  WHERE id = p_entry_id;

  UPDATE appointments SET status = 'skipped' WHERE id = v_entry.appointment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_queue_skipped(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_queue_skipped(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: resume_consultation (atomic pause duration accumulate)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resume_consultation(p_entry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_entry queue_entries%ROWTYPE;
  v_elapsed bigint;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry FROM queue_entries WHERE id = p_entry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  IF v_entry.status <> 'paused' THEN
    RAISE EXCEPTION 'Entry is not paused.' USING ERRCODE = '55000';
  END IF;

  v_elapsed := CASE
    WHEN v_entry.paused_at IS NULL THEN 0
    ELSE GREATEST(0, (EXTRACT(EPOCH FROM (now() - v_entry.paused_at)) * 1000)::bigint)
  END;

  UPDATE queue_entries
  SET status = 'in_consultation',
      paused_at = NULL,
      total_paused_ms = total_paused_ms + v_elapsed
  WHERE id = p_entry_id;
END;
$$;

REVOKE ALL ON FUNCTION public.resume_consultation(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resume_consultation(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: rejoin_patient
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rejoin_patient(
  p_entry_id uuid,
  p_skip_policy skip_policy
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_entry queue_entries%ROWTYPE;
  v_new_checked_in timestamptz;
  v_earliest timestamptz;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role NOT IN ('receptionist', 'super_admin') THEN
    RAISE EXCEPTION 'Only a receptionist may rejoin a skipped patient.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry FROM queue_entries WHERE id = p_entry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry no longer exists.' USING ERRCODE = 'P0002';
  END IF;

  IF v_entry.status <> 'skipped' THEN
    RAISE EXCEPTION 'Only skipped patients can rejoin.' USING ERRCODE = '55000';
  END IF;

  IF p_skip_policy = 'after_current' THEN
    SELECT MIN(checked_in_at) INTO v_earliest
    FROM queue_entries
    WHERE hospital_id = v_entry.hospital_id
      AND date = v_entry.date
      AND department_id = v_entry.department_id
      AND status = 'waiting';

    v_new_checked_in := COALESCE(v_earliest - interval '1 second', now());
  ELSE
    v_new_checked_in := now();
  END IF;

  UPDATE queue_entries
  SET status = 'waiting',
      checked_in_at = v_new_checked_in,
      last_notified_threshold = 'none',
      skipped_at = NULL
  WHERE id = p_entry_id;

  UPDATE appointments SET status = 'checked_in' WHERE id = v_entry.appointment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rejoin_patient(uuid, skip_policy) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rejoin_patient(uuid, skip_policy) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: warn_patient_delay (queue fields only; notifications in Step 9)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.warn_patient_delay(p_entry_id uuid)
RETURNS TABLE (grace_minutes integer, grace_deadline_millis bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_entry queue_entries%ROWTYPE;
  v_grace integer;
  v_deadline timestamptz;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role <> 'doctor' THEN
    RAISE EXCEPTION 'Only a doctor may issue a delay warning.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_entry FROM queue_entries WHERE id = p_entry_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Queue entry not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_entry.doctor_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'This patient is not assigned to you.' USING ERRCODE = '42501';
  END IF;

  IF v_entry.status <> 'called' THEN
    RAISE EXCEPTION 'Can only warn a patient who has been called and hasn''t arrived yet.'
      USING ERRCODE = '55000';
  END IF;

  SELECT no_show_grace_minutes INTO v_grace
  FROM hospitals WHERE id = v_entry.hospital_id;
  v_grace := COALESCE(v_grace, 5);
  v_deadline := now() + make_interval(mins => v_grace);

  UPDATE queue_entries
  SET warned_at = now(),
      grace_deadline = v_deadline,
      grace_minutes = v_grace
  WHERE id = p_entry_id;

  grace_minutes := v_grace;
  grace_deadline_millis := (EXTRACT(EPOCH FROM v_deadline) * 1000)::bigint;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.warn_patient_delay(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.warn_patient_delay(uuid) TO authenticated;
