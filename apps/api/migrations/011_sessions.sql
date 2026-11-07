CREATE TABLE session_policy (
  id boolean PRIMARY KEY DEFAULT true CHECK(id),
  policy jsonb,
  revision integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO session_policy(id) VALUES(true);
CREATE TABLE coaching_slots (
  id uuid PRIMARY KEY,
  trainer_id uuid REFERENCES users(id) ON DELETE SET NULL,
  trainer_name text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
  status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','withdrawn')),
  revision integer NOT NULL DEFAULT 1,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX coaching_slots_time ON coaching_slots(trainer_id,starts_at,ends_at);
CREATE TABLE coaching_bookings (
  id uuid PRIMARY KEY,
  slot_id uuid REFERENCES coaching_slots(id) ON DELETE SET NULL,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trainer_id uuid REFERENCES users(id) ON DELETE SET NULL,
  trainer_name text NOT NULL,
  membership_id uuid NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),
  policy jsonb NOT NULL,
  status text NOT NULL DEFAULT 'booked' CHECK(status IN ('booked','cancelled','completed','no_show')),
  consumed boolean NOT NULL DEFAULT false,
  revision integer NOT NULL DEFAULT 1,
  cancellation_reason text,
  attendance_note text,
  outcome_recorded_by uuid REFERENCES users(id) ON DELETE SET NULL,
  outcome_recorded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(membership_id,customer_id) REFERENCES memberships(id,customer_id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX coaching_slot_one_booking ON coaching_bookings(slot_id) WHERE status='booked';
CREATE INDEX coaching_booking_period ON coaching_bookings(membership_id,status);
CREATE INDEX coaching_booking_customer ON coaching_bookings(customer_id,starts_at);
ALTER TABLE membership_session_ledger ADD COLUMN reason text NOT NULL DEFAULT 'completed' CHECK(reason IN ('completed','late_cancellation','no_show'));
ALTER TABLE membership_session_ledger ADD COLUMN booking_id uuid REFERENCES coaching_bookings(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX membership_ledger_booking ON membership_session_ledger(booking_id) WHERE booking_id IS NOT NULL;
CREATE TABLE session_operations (
  actor_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  kind text NOT NULL,
  payload_hash text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(actor_id,request_id)
);
