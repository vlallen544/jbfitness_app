CREATE TABLE staff_review_state (
  kind text NOT NULL CHECK(kind IN ('planning','coaching')),
  source_id uuid NOT NULL,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status text NOT NULL CHECK(status IN ('open','resolved')),
  revision integer NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(kind,source_id)
);
CREATE TABLE staff_review_events (
  id uuid PRIMARY KEY,
  kind text NOT NULL CHECK(kind IN ('planning','coaching')),
  source_id uuid NOT NULL,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  request_id uuid NOT NULL,
  payload_hash text NOT NULL,
  decision text NOT NULL CHECK(decision IN ('follow_up','resolved','publish_plan')),
  feedback text,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(actor_id,request_id)
);
CREATE INDEX staff_feedback_customer ON staff_review_events(customer_id,created_at DESC);
CREATE TABLE staff_audit (
  id uuid PRIMARY KEY,
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  customer_id uuid REFERENCES users(id) ON DELETE CASCADE,
  action text NOT NULL,
  metadata jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
