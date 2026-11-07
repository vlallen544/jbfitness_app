CREATE TABLE meal_estimates (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  input_hash text NOT NULL,
  input_kind text NOT NULL CHECK(input_kind IN ('text','photo','photo_text')),
  status text NOT NULL CHECK(status IN ('pending','succeeded','failed')),
  draft jsonb,
  model text NOT NULL,
  usage jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '24 hours',
  UNIQUE(customer_id,request_id)
);
CREATE INDEX meal_estimate_usage ON meal_estimates(customer_id,created_at);
CREATE TABLE meal_estimate_saves (
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  estimate_id uuid NOT NULL REFERENCES meal_estimates(id) ON DELETE CASCADE,
  payload_hash text NOT NULL,
  entry_ids jsonb NOT NULL,
  PRIMARY KEY(customer_id,request_id)
);
