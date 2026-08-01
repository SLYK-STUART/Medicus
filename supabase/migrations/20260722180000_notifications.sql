-- Step 8: notifications table + Realtime
-- (hospitals/departments/doctors/appointments/profiles/queue_entries already in publication)

CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles (id) ON DELETE CASCADE,
  type text NOT NULL,
  message text NOT NULL,
  hospital_id uuid REFERENCES hospitals (id) ON DELETE SET NULL,
  appointment_id uuid REFERENCES appointments (id) ON DELETE SET NULL,
  queue_entry_id uuid REFERENCES queue_entries (id) ON DELETE SET NULL,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_user_created_idx
  ON notifications (user_id, created_at DESC);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Own notifications only (super_admin may read all for support)
CREATE POLICY notifications_select_own_or_super
  ON notifications FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.current_role() = 'super_admin'
  );

-- Inserts are server-side only (queue notification dispatcher in Step 9).
-- No INSERT policy for authenticated.

CREATE POLICY notifications_update_own_read
  ON notifications FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Only allow flipping `read` (and nothing else) for the owner.
CREATE OR REPLACE FUNCTION public.enforce_notification_client_updates()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.user_id IS DISTINCT FROM OLD.user_id
    OR NEW.type IS DISTINCT FROM OLD.type
    OR NEW.message IS DISTINCT FROM OLD.message
    OR NEW.hospital_id IS DISTINCT FROM OLD.hospital_id
    OR NEW.appointment_id IS DISTINCT FROM OLD.appointment_id
    OR NEW.queue_entry_id IS DISTINCT FROM OLD.queue_entry_id
    OR NEW.created_at IS DISTINCT FROM OLD.created_at
  THEN
    RAISE EXCEPTION 'clients may only update notifications.read'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER notifications_enforce_client_updates
  BEFORE UPDATE ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_notification_client_updates();

CREATE POLICY notifications_delete_super_admin
  ON notifications FOR DELETE
  TO authenticated
  USING (public.current_role() = 'super_admin');

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
