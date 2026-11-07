CREATE TABLE exercises (
  id text PRIMARY KEY,
  name text NOT NULL,
  muscle_group text NOT NULL,
  equipment jsonb NOT NULL,
  instructions jsonb NOT NULL,
  review_status text NOT NULL CHECK (review_status IN ('draft','approved','development_sample')),
  media_key text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE workout_plans (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  version integer NOT NULL CHECK (version > 0),
  title text NOT NULL,
  source text NOT NULL CHECK (source IN ('trainer','ai','development_fixture')),
  superseded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (customer_id,version),
  UNIQUE (id,customer_id)
);
CREATE UNIQUE INDEX workout_one_current_plan ON workout_plans(customer_id) WHERE superseded_at IS NULL;
CREATE TABLE workout_sessions (
  id uuid PRIMARY KEY,
  plan_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  scheduled_on date NOT NULL,
  title text NOT NULL,
  FOREIGN KEY (plan_id,customer_id) REFERENCES workout_plans(id,customer_id) ON DELETE CASCADE,
  UNIQUE (id,customer_id)
);
CREATE INDEX workout_sessions_customer_date ON workout_sessions(customer_id,scheduled_on);
CREATE TABLE workout_items (
  id uuid PRIMARY KEY,
  workout_id uuid NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
  exercise_id text NOT NULL REFERENCES exercises(id),
  exercise_snapshot jsonb NOT NULL,
  position integer NOT NULL CHECK (position >= 0),
  sets integer NOT NULL CHECK (sets BETWEEN 1 AND 12),
  repetitions integer NOT NULL CHECK (repetitions BETWEEN 1 AND 100),
  target_weight_kg numeric CHECK (target_weight_kg BETWEEN 0 AND 1000),
  rest_seconds integer NOT NULL CHECK (rest_seconds BETWEEN 0 AND 600),
  UNIQUE (workout_id,position)
);
CREATE TABLE workout_progress (
  workout_id uuid PRIMARY KEY,
  customer_id uuid NOT NULL,
  status text NOT NULL CHECK (status IN ('in_progress','completed','skipped')),
  exercise_logs jsonb NOT NULL,
  notes text NOT NULL DEFAULT '',
  revision integer NOT NULL CHECK (revision > 0),
  last_request_id uuid NOT NULL,
  last_payload_hash char(64) NOT NULL,
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (workout_id,customer_id) REFERENCES workout_sessions(id,customer_id) ON DELETE CASCADE
);
