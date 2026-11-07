CREATE TABLE coaching_turns (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN ('chat','summary')),
  input text,
  payload_hash text NOT NULL,
  status text NOT NULL CHECK(status IN ('pending','completed','failed')),
  response jsonb,
  facts jsonb,
  model text,
  usage jsonb,
  source text NOT NULL DEFAULT 'ai',
  deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  UNIQUE(customer_id,request_id)
);
CREATE INDEX coaching_history ON coaching_turns(customer_id,created_at DESC,id DESC);
CREATE UNIQUE INDEX coaching_one_pending ON coaching_turns(customer_id) WHERE status='pending';
