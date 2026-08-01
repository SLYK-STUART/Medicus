-- Notify patient when consultation is paused / resumed (fixes silent pause
-- and pairs with the patient live-queue paused UI).

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
  PERFORM set_config('app.bypass_queue_enforce', 'true', true);

  IF TG_OP = 'UPDATE'
    AND NEW.status IS NOT DISTINCT FROM OLD.status
    AND NEW.priority IS NOT DISTINCT FROM OLD.priority
    AND NEW.checked_in_at IS NOT DISTINCT FROM OLD.checked_in_at
    AND NEW.doctor_id IS NOT DISTINCT FROM OLD.doctor_id
  THEN
    RETURN NEW;
  END IF;

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
