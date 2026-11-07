ALTER TABLE coaching_slots ADD COLUMN environment text NOT NULL DEFAULT 'development' CHECK(environment IN ('development','production'));
