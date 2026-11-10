CREATE TABLE store_order_requests (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  cart_revision integer NOT NULL CHECK (cart_revision >= 0),
  status text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','reviewed','closed')),
  line_items jsonb NOT NULL CHECK (jsonb_typeof(line_items) = 'array' AND jsonb_array_length(line_items) BETWEEN 1 AND 20),
  subtotal_paise bigint NOT NULL CHECK (subtotal_paise >= 1),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id, request_id)
);
CREATE INDEX store_order_requests_owner_queue ON store_order_requests(status, created_at DESC);
CREATE INDEX store_order_requests_customer_history ON store_order_requests(customer_id, created_at DESC);
CREATE TABLE store_order_events (
  id uuid PRIMARY KEY,
  order_id uuid NOT NULL REFERENCES store_order_requests(id) ON DELETE CASCADE,
  actor_id uuid REFERENCES users(id) ON DELETE SET NULL,
  request_id uuid NOT NULL,
  previous_status text NOT NULL,
  next_status text NOT NULL CHECK (next_status IN ('reviewed','closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(actor_id, request_id)
);
ALTER TABLE store_order_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE store_order_events ENABLE ROW LEVEL SECURITY;
