-- FIX: Receptionist check-in fails after Step 9 queue triggersequencing.
--
-- check_in INSERTs a waiting row, then process_queue_entry_change UPDATEs
-- patients_ahead / last_notified_threshold. enforce_queue_entry_client_updates
-- still sees auth.uid() as the receptionist (JWT claims persist inside
-- SECURITY DEFINER), and rejects those columns — so check-in aborts with
-- "receptionist may only escalate priority or rejoin a skipped patient".
--
-- Same failure path hits escalate-priority and rejoin (resequence side effects).

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
