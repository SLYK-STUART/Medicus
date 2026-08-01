-- Step 9: sms_log, notification dispatch, queue triggers, referral/follow-up RPCs
-- Also replaces Firebase onConsultationCompleted + onQueueEntryWritten.

-- ---------------------------------------------------------------------------
-- sms_log (stub; Africa's Talking later)
-- ---------------------------------------------------------------------------
CREATE TABLE sms_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number text NOT NULL,
  message text NOT NULL,
  related_user_id uuid REFERENCES profiles (id) ON DELETE SET NULL,
  related_appointment_id uuid REFERENCES appointments (id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'sent',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sms_log_created_idx ON sms_log (created_at DESC);

ALTER TABLE sms_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY sms_log_select_super_or_hospital_admin
  ON sms_log FOR SELECT
  TO authenticated
  USING (public.current_role() IN ('super_admin', 'hospital_admin'));

-- no client writes

-- ---------------------------------------------------------------------------
-- dispatch_notification: in-app + sms_log stub (no FCM)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dispatch_notification(
  p_user_id uuid,
  p_type text,
  p_message text,
  p_hospital_id uuid DEFAULT NULL,
  p_appointment_id uuid DEFAULT NULL,
  p_queue_entry_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone text;
BEGIN
  INSERT INTO notifications (user_id, type, message, hospital_id, appointment_id, queue_entry_id, read)
  VALUES (p_user_id, p_type, p_message, p_hospital_id, p_appointment_id, p_queue_entry_id, false);

  SELECT phone_number INTO v_phone FROM profiles WHERE id = p_user_id;
  IF v_phone IS NOT NULL AND length(trim(v_phone)) > 0 THEN
    INSERT INTO sms_log (phone_number, message, related_user_id, related_appointment_id, status)
    VALUES (v_phone, p_message, p_user_id, p_appointment_id, 'sent');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.dispatch_notification(uuid, text, text, uuid, uuid, uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.relay_to_booker_if_no_phone(
  p_patient_id uuid,
  p_patient_name text,
  p_appointment_id uuid,
  p_hospital_id uuid,
  p_queue_entry_id uuid,
  p_event_label text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_phone text;
  v_booked_by uuid;
  v_msg text;
BEGIN
  SELECT phone_number INTO v_phone FROM profiles WHERE id = p_patient_id;
  IF v_phone IS NOT NULL AND length(trim(v_phone)) > 0 THEN
    RETURN;
  END IF;
  IF p_appointment_id IS NULL THEN
    RETURN;
  END IF;

  SELECT booked_by INTO v_booked_by FROM appointments WHERE id = p_appointment_id;
  IF v_booked_by IS NULL OR v_booked_by = p_patient_id THEN
    RETURN;
  END IF;

  v_msg := p_patient_name
    || ' (no phone on file) '
    || CASE
         WHEN p_event_label = 'called' THEN 'is being called now.'
         ELSE 'was skipped after the grace period expired.'
       END;

  PERFORM public.dispatch_notification(
    v_booked_by,
    'relay_' || p_event_label,
    v_msg,
    p_hospital_id,
    p_appointment_id,
    p_queue_entry_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.relay_to_booker_if_no_phone(uuid, text, uuid, uuid, uuid, text) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Doctor rolling median on consultation complete
-- ---------------------------------------------------------------------------
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

CREATE TRIGGER queue_entries_update_doctor_avg
  AFTER INSERT OR UPDATE OF status ON queue_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.update_doctor_avg_on_complete();

-- ---------------------------------------------------------------------------
-- Queue entry written: status notifications + resequence + thresholds
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.threshold_rank(t notification_threshold)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE t
    WHEN 'none' THEN 0
    WHEN 'five_ahead' THEN 1
    WHEN 'fifteen_min' THEN 2
    WHEN 'next' THEN 3
    ELSE 0
  END;
$$;

CREATE OR REPLACE FUNCTION public.process_queue_entry_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_is_create boolean := (TG_OP = 'INSERT');
  v_room text;
  v_msg text;
  v_avg integer;
  r RECORD;
  i integer := 0;
  v_est integer;
  v_new_threshold notification_threshold;
  v_bumped RECORD;
BEGIN
  -- Allow this trigger's resequence UPDATEs past enforce_queue_entry_client_updates
  -- while the signed-in caller is a receptionist (JWT still present).
  PERFORM set_config('app.bypass_queue_enforce', 'true', true);

  -- Skip re-entrancy from resequence-only updates.
  IF TG_OP = 'UPDATE'
    AND NEW.status IS NOT DISTINCT FROM OLD.status
    AND NEW.priority IS NOT DISTINCT FROM OLD.priority
    AND NEW.checked_in_at IS NOT DISTINCT FROM OLD.checked_in_at
    AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
  THEN
    RETURN NEW;
  END IF;

  -- Status notifications
  IF NEW.status = 'called' AND (v_is_create OR OLD.status IS DISTINCT FROM 'called') THEN
    IF NEW.doctor_id IS NOT NULL THEN
      SELECT room_number INTO v_room FROM doctors WHERE id = NEW.doctor_id;
    END IF;
    v_msg := 'You''re being called now — please proceed to the department.'
      || CASE WHEN v_room IS NOT NULL THEN ' Please proceed to Room ' || v_room || '.' ELSE '' END;
    PERFORM public.dispatch_notification(
      NEW.patient_id, 'called', v_msg, NEW.hospital_id, NEW.appointment_id, NEW.id
    );
    PERFORM public.relay_to_booker_if_no_phone(
      NEW.patient_id, NEW.patient_name, NEW.appointment_id, NEW.hospital_id, NEW.id, 'called'
    );
  END IF;

  IF NEW.status = 'paused' AND (v_is_create OR OLD.status IS DISTINCT FROM 'paused') THEN
    PERFORM public.dispatch_notification(
      NEW.patient_id,
      'paused',
      'Your consultation is paused. Please stay nearby — the doctor will resume shortly.',
      NEW.hospital_id,
      NEW.appointment_id,
      NEW.id
    );
  END IF;

  IF NEW.status = 'in_consultation'
    AND NOT v_is_create
    AND OLD.status = 'paused' THEN
    PERFORM public.dispatch_notification(
      NEW.patient_id,
      'resumed',
      'Your consultation has resumed. Please return to the consultation room.',
      NEW.hospital_id,
      NEW.appointment_id,
      NEW.id
    );
  END IF;

  IF NEW.status = 'completed' AND (v_is_create OR OLD.status IS DISTINCT FROM 'completed') THEN
    PERFORM public.dispatch_notification(
      NEW.patient_id,
      'completed',
      'Your consultation is complete. Thank you for visiting.',
      NEW.hospital_id,
      NEW.appointment_id,
      NEW.id
    );
  END IF;

  IF NEW.status = 'skipped' AND (v_is_create OR OLD.status IS DISTINCT FROM 'skipped') THEN
    PERFORM public.dispatch_notification(
      NEW.patient_id,
      'skipped',
      'You were not able to check in within the grace period and have been skipped. Please check in again with reception to rejoin the queue.',
      NEW.hospital_id,
      NEW.appointment_id,
      NEW.id
    );
    PERFORM public.relay_to_booker_if_no_phone(
      NEW.patient_id, NEW.patient_name, NEW.appointment_id, NEW.hospital_id, NEW.id, 'skipped'
    );
  END IF;

  -- Priority bump notifications
  IF (
    (v_is_create AND NEW.status = 'waiting' AND NEW.priority IN ('critical', 'urgent'))
    OR (
      NOT v_is_create
      AND NEW.status = 'waiting'
      AND NEW.priority IN ('critical', 'urgent')
      AND NEW.priority_rank < OLD.priority_rank
    )
  ) THEN
    FOR v_bumped IN
      SELECT id, patient_id, appointment_id
      FROM queue_entries
      WHERE hospital_id = NEW.hospital_id
        AND date = NEW.date
        AND department_id = NEW.department_id
        AND status = 'waiting'
        AND priority_rank > NEW.priority_rank
        AND id <> NEW.id
    LOOP
      PERFORM public.dispatch_notification(
        v_bumped.patient_id,
        'priority_bump',
        'Your wait time has been updated due to an emergency case being prioritized ahead of you.',
        NEW.hospital_id,
        v_bumped.appointment_id,
        v_bumped.id
      );
    END LOOP;
  END IF;

  -- Resequence waiting patients
  SELECT COALESCE(ROUND(AVG(avg_consultation_minutes))::integer, 15)
  INTO v_avg
  FROM doctors
  WHERE hospital_id = NEW.hospital_id
    AND department_id = NEW.department_id;

  FOR r IN
    SELECT id, patient_id, appointment_id, patients_ahead, last_notified_threshold
    FROM queue_entries
    WHERE hospital_id = NEW.hospital_id
      AND date = NEW.date
      AND department_id = NEW.department_id
      AND status = 'waiting'
    ORDER BY priority_rank, checked_in_at
  LOOP
    v_est := i * v_avg;
    IF i = 0 THEN
      v_new_threshold := 'next';
    ELSIF v_est <= 15 THEN
      v_new_threshold := 'fifteen_min';
    ELSIF i <= 5 THEN
      v_new_threshold := 'five_ahead';
    ELSE
      v_new_threshold := 'none';
    END IF;

    IF r.patients_ahead IS DISTINCT FROM i
      OR public.threshold_rank(v_new_threshold) > public.threshold_rank(r.last_notified_threshold) THEN
      UPDATE queue_entries SET
        patients_ahead = i,
        last_notified_threshold = CASE
          WHEN public.threshold_rank(v_new_threshold) > public.threshold_rank(r.last_notified_threshold)
            THEN v_new_threshold
          ELSE last_notified_threshold
        END
      WHERE id = r.id;

      IF public.threshold_rank(v_new_threshold) > public.threshold_rank(r.last_notified_threshold) THEN
        v_msg := CASE v_new_threshold
          WHEN 'five_ahead' THEN 'You have ' || i::text || ' patient(s) ahead of you in the queue.'
          WHEN 'fifteen_min' THEN 'Your estimated wait is about 15 minutes. Please make your way to the hospital if you haven''t already.'
          WHEN 'next' THEN 'You''re next in line. Please be ready.'
          ELSE NULL
        END;
        IF v_msg IS NOT NULL THEN
          PERFORM public.dispatch_notification(
            r.patient_id,
            'queue_' || v_new_threshold::text,
            v_msg,
            NEW.hospital_id,
            r.appointment_id,
            r.id
          );
        END IF;
      END IF;
    END IF;

    i := i + 1;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER queue_entries_process_change
  AFTER INSERT OR UPDATE ON queue_entries
  FOR EACH ROW
  EXECUTE FUNCTION public.process_queue_entry_change();

-- ---------------------------------------------------------------------------
-- Enhance warn_patient_delay to also notify (in-app + sms_log)
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
  v_message text;
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

  SELECT no_show_grace_minutes INTO v_grace FROM hospitals WHERE id = v_entry.hospital_id;
  v_grace := COALESCE(v_grace, 5);
  v_deadline := now() + make_interval(mins => v_grace);

  UPDATE queue_entries
  SET warned_at = now(),
      grace_deadline = v_deadline,
      grace_minutes = v_grace
  WHERE id = p_entry_id;

  v_message := 'You haven''t checked in for your consultation yet. If you don''t report within '
    || v_grace::text
    || ' minutes, you will be skipped and will need to check in again to rejoin the queue.';

  PERFORM public.dispatch_notification(
    v_entry.patient_id,
    'delay_warning',
    v_message,
    v_entry.hospital_id,
    v_entry.appointment_id,
    p_entry_id
  );

  grace_minutes := v_grace;
  grace_deadline_millis := (EXTRACT(EPOCH FROM v_deadline) * 1000)::bigint;
  RETURN NEXT;
END;
$$;

-- ---------------------------------------------------------------------------
-- RPC: create_referral (appointment + queue entry in one transaction)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_referral(
  p_origin_appointment_id uuid,
  p_target_department_id uuid
)
RETURNS TABLE (appointment_id uuid, token_number integer, visit_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_caller_hospital uuid;
  v_origin appointments%ROWTYPE;
  v_visit_id uuid;
  v_next_token integer;
  v_new_appt_id uuid;
  v_today date;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role, hospital_id INTO v_caller_role, v_caller_hospital
  FROM profiles WHERE id = v_caller_id;
  IF v_caller_role <> 'doctor' THEN
    RAISE EXCEPTION 'Only a doctor may refer a patient.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_origin FROM appointments WHERE id = p_origin_appointment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original appointment not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_origin.hospital_id IS DISTINCT FROM v_caller_hospital THEN
    RAISE EXCEPTION 'Cannot refer outside your own hospital.' USING ERRCODE = '42501';
  END IF;
  IF v_origin.department_id = p_target_department_id THEN
    RAISE EXCEPTION 'Target department must differ from the current one.' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM departments
    WHERE id = p_target_department_id AND hospital_id = v_origin.hospital_id
  ) THEN
    RAISE EXCEPTION 'Target department not found in this hospital.' USING ERRCODE = 'P0002';
  END IF;

  v_visit_id := v_origin.visit_id;
  IF v_visit_id IS NULL THEN
    INSERT INTO visits (patient_id, hospital_id, origin_appointment_id)
    VALUES (v_origin.patient_id, v_origin.hospital_id, p_origin_appointment_id)
    RETURNING id INTO v_visit_id;

    UPDATE appointments SET visit_id = v_visit_id WHERE id = p_origin_appointment_id;
  END IF;

  v_today := v_origin.scheduled_date;

  INSERT INTO token_counters (hospital_id, department_id, date, last_token, updated_at)
  VALUES (v_origin.hospital_id, p_target_department_id, v_today, 0, now())
  ON CONFLICT (hospital_id, department_id, date) DO NOTHING;

  PERFORM 1 FROM token_counters
  WHERE hospital_id = v_origin.hospital_id
    AND department_id = p_target_department_id
    AND date = v_today
  FOR UPDATE;

  UPDATE token_counters
  SET last_token = last_token + 1, updated_at = now()
  WHERE hospital_id = v_origin.hospital_id
    AND department_id = p_target_department_id
    AND date = v_today
  RETURNING last_token INTO v_next_token;

  INSERT INTO appointments (
    patient_id, patient_name, patient_phone_number,
    hospital_id, department_id, doctor_id,
    scheduled_date, scheduled_time_slot, token_number,
    status, visit_id, is_recurring, recurring_parent_id,
    booked_by, source
  ) VALUES (
    v_origin.patient_id, v_origin.patient_name, v_origin.patient_phone_number,
    v_origin.hospital_id, p_target_department_id, NULL,
    v_today, NULL, v_next_token,
    'checked_in', v_visit_id, false, NULL,
    v_caller_id, 'referral'
  )
  RETURNING id INTO v_new_appt_id;

  -- FIX (vs Firebase): queue entry created in the same transaction.
  INSERT INTO queue_entries (
    hospital_id, date, department_id, appointment_id,
    patient_id, patient_name, patient_phone_number,
    doctor_id, token_number, priority, status, last_notified_threshold
  ) VALUES (
    v_origin.hospital_id, v_today, p_target_department_id, v_new_appt_id,
    v_origin.patient_id, v_origin.patient_name, v_origin.patient_phone_number,
    NULL, v_next_token, 'normal', 'waiting', 'none'
  );

  appointment_id := v_new_appt_id;
  token_number := v_next_token;
  visit_id := v_visit_id;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_referral(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_referral(uuid, uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- RPC: create_follow_up
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_follow_up(
  p_origin_appointment_id uuid,
  p_days_from_now integer
)
RETURNS TABLE (appointment_id uuid, scheduled_date date, token_number integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid := auth.uid();
  v_caller_role app_role;
  v_origin appointments%ROWTYPE;
  v_scheduled date;
  v_next_token integer;
  v_new_id uuid;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Must be signed in.' USING ERRCODE = '42501';
  END IF;

  SELECT role INTO v_caller_role FROM profiles WHERE id = v_caller_id;
  IF v_caller_role <> 'doctor' THEN
    RAISE EXCEPTION 'Only a doctor may schedule a follow-up.' USING ERRCODE = '42501';
  END IF;

  IF p_days_from_now IS NULL OR p_days_from_now < 1 THEN
    RAISE EXCEPTION 'daysFromNow must be a positive integer.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_origin FROM appointments WHERE id = p_origin_appointment_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original appointment not found.' USING ERRCODE = 'P0002';
  END IF;

  IF v_origin.doctor_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'You may only schedule a follow-up for a patient you personally saw.'
      USING ERRCODE = '42501';
  END IF;

  v_scheduled := (CURRENT_DATE + p_days_from_now);

  INSERT INTO token_counters (hospital_id, department_id, date, last_token, updated_at)
  VALUES (v_origin.hospital_id, v_origin.department_id, v_scheduled, 0, now())
  ON CONFLICT (hospital_id, department_id, date) DO NOTHING;

  PERFORM 1 FROM token_counters
  WHERE hospital_id = v_origin.hospital_id
    AND department_id = v_origin.department_id
    AND date = v_scheduled
  FOR UPDATE;

  UPDATE token_counters
  SET last_token = last_token + 1, updated_at = now()
  WHERE hospital_id = v_origin.hospital_id
    AND department_id = v_origin.department_id
    AND date = v_scheduled
  RETURNING last_token INTO v_next_token;

  INSERT INTO appointments (
    patient_id, patient_name, patient_phone_number,
    hospital_id, department_id, doctor_id,
    scheduled_date, scheduled_time_slot, token_number,
    status, visit_id, is_recurring, recurring_parent_id,
    booked_by, source
  ) VALUES (
    v_origin.patient_id, v_origin.patient_name, v_origin.patient_phone_number,
    v_origin.hospital_id, v_origin.department_id, v_origin.doctor_id,
    v_scheduled, NULL, v_next_token,
    'booked', NULL, true, p_origin_appointment_id,
    v_caller_id, 'follow_up'
  )
  RETURNING id INTO v_new_id;

  appointment_id := v_new_id;
  scheduled_date := v_scheduled;
  token_number := v_next_token;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_follow_up(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_follow_up(uuid, integer) TO authenticated;
