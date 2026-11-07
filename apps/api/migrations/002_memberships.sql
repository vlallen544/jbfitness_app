CREATE TABLE membership_receipts (
  id uuid PRIMARY KEY,
  payment_reference text NOT NULL UNIQUE,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id text NOT NULL CHECK (plan_id IN ('normal','premium','premium-plus')),
  amount_paise integer NOT NULL CHECK (amount_paise > 0),
  currency text NOT NULL CHECK (currency = 'INR'),
  environment text NOT NULL CHECK (environment IN ('development','sandbox','production')),
  payload_hash char(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE membership_events (
  event_id text PRIMARY KEY,
  receipt_id uuid NOT NULL REFERENCES membership_receipts(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE memberships (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  receipt_id uuid NOT NULL UNIQUE REFERENCES membership_receipts(id) ON DELETE CASCADE,
  plan_snapshot jsonb NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  video_sessions_total integer NOT NULL CHECK (video_sessions_total >= 0),
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  UNIQUE (id, customer_id)
);
CREATE INDEX memberships_customer_period ON memberships(customer_id, ends_at);
CREATE TABLE membership_session_ledger (
  id uuid PRIMARY KEY,
  membership_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  session_reference text NOT NULL,
  completed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (membership_id,customer_id) REFERENCES memberships(id,customer_id) ON DELETE CASCADE,
  UNIQUE (customer_id,session_reference)
);
CREATE INDEX membership_ledger_period ON membership_session_ledger(membership_id);
