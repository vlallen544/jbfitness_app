CREATE TABLE nutrition_foods (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  nutrients jsonb NOT NULL CHECK (jsonb_typeof(nutrients)='object'),
  source jsonb NOT NULL CHECK (jsonb_typeof(source)='object'),
  create_request_id uuid,
  create_payload_hash text,
  usda_id integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id, create_request_id),
  UNIQUE(customer_id, usda_id)
);
CREATE INDEX nutrition_foods_owner ON nutrition_foods(customer_id);
CREATE TABLE nutrition_entries (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  food_id uuid REFERENCES nutrition_foods(id) ON DELETE SET NULL,
  day date NOT NULL,
  meal text NOT NULL CHECK (meal IN ('breakfast','lunch','dinner','snack')),
  grams numeric(9,2) NOT NULL CHECK (grams>0 AND grams<=10000),
  food_snapshot jsonb NOT NULL,
  revision integer NOT NULL DEFAULT 1,
  create_request_id uuid NOT NULL,
  create_payload_hash text NOT NULL,
  last_request_id uuid,
  last_payload_hash text,
  deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id, create_request_id)
);
CREATE INDEX nutrition_entries_day ON nutrition_entries(customer_id,day);
CREATE TABLE nutrition_targets (
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  effective_from date NOT NULL,
  nutrients jsonb NOT NULL,
  revision integer NOT NULL,
  last_request_id uuid NOT NULL,
  last_payload_hash text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(customer_id,effective_from)
);
