CREATE TABLE ai_planning_runs (
  id uuid PRIMARY KEY,
  customer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  status text NOT NULL CHECK(status IN ('queued','running','published','review_needed','failed')),
  stage text NOT NULL,
  context jsonb NOT NULL,
  context_hash text NOT NULL,
  base_plan_id uuid,
  routine_review jsonb,
  draft jsonb,
  trace jsonb NOT NULL DEFAULT '[]',
  message text NOT NULL,
  plan_id uuid REFERENCES workout_plans(id) ON DELETE SET NULL,
  plan_version integer,
  claim_token uuid,
  lease_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(customer_id,request_id)
);
CREATE UNIQUE INDEX ai_planning_one_pending ON ai_planning_runs(customer_id) WHERE status IN ('queued','running');
CREATE INDEX ai_planning_queue ON ai_planning_runs(created_at) WHERE status='queued';
