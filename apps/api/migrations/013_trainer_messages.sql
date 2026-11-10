CREATE TABLE trainer_messages (
  sequence bigserial PRIMARY KEY,
  id uuid NOT NULL UNIQUE,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trainer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id IN (customer_id, trainer_id)),
  UNIQUE (sender_id, request_id)
);
CREATE INDEX trainer_messages_thread ON trainer_messages(customer_id, trainer_id, sequence DESC);
CREATE INDEX trainer_messages_rate ON trainer_messages(sender_id, created_at);
ALTER TABLE trainer_messages ENABLE ROW LEVEL SECURITY;
