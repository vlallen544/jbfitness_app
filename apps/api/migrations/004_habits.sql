CREATE TABLE habits (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 60),
  target_days integer NOT NULL CHECK (target_days BETWEEN 1 AND 31),
  create_request_id uuid NOT NULL,
  starts_on date NOT NULL,
  archived_on date CHECK (archived_on >= starts_on),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id, create_request_id)
);
CREATE INDEX habits_customer ON habits(customer_id);
CREATE TABLE habit_entries (
  habit_id uuid NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  day date NOT NULL,
  completed boolean NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(habit_id, day)
);
