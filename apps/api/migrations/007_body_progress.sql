CREATE TABLE body_progress (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day date NOT NULL,
  measurements jsonb NOT NULL,
  revision integer NOT NULL DEFAULT 1,
  deleted boolean NOT NULL DEFAULT false,
  create_request_id uuid NOT NULL,
  create_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id,create_request_id)
);
CREATE UNIQUE INDEX body_progress_day ON body_progress(customer_id,day) WHERE NOT deleted;
CREATE TABLE body_progress_changes (
  record_id uuid NOT NULL REFERENCES body_progress(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  payload_hash text NOT NULL,
  result_revision integer NOT NULL,
  PRIMARY KEY(record_id,request_id)
);
CREATE TABLE body_progress_photos (
  id uuid PRIMARY KEY,
  record_id uuid NOT NULL REFERENCES body_progress(id) ON DELETE CASCADE,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  angle text NOT NULL CHECK(angle IN ('front','side','back')),
  jpeg bytea,
  create_request_id uuid NOT NULL,
  create_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id,create_request_id)
);
CREATE UNIQUE INDEX body_progress_angle ON body_progress_photos(record_id,angle) WHERE jpeg IS NOT NULL;
