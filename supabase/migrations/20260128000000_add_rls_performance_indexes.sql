-- ============================================================================
-- AMA-492: Add Missing Indexes for RLS Performance
--
-- The program_workouts RLS policy joins through program_weeks:
--   USING (EXISTS (
--       SELECT 1 FROM program_weeks pw
--       JOIN training_programs tp ON tp.id = pw.program_id
--       WHERE pw.id = program_workouts.week_id  -- Lookup by pw.id
--       ...
--   ));
--
-- While program_weeks.id has an implicit index via PRIMARY KEY, adding an
-- explicit B-tree index can help the query planner optimize RLS subqueries.
-- Additionally, a composite index on (week_id, day_of_week) supports common
-- query patterns for fetching workouts.
-- ============================================================================

-- Index on program_weeks.id for RLS policy lookups
-- The primary key creates an index, but explicit indexes can improve
-- query planner decisions for EXISTS subqueries in RLS policies
CREATE INDEX IF NOT EXISTS idx_weeks_id ON program_weeks(id);

-- Composite index for common query pattern: fetch workouts by week and day
-- Supports queries like: SELECT * FROM program_workouts WHERE week_id = ? ORDER BY day_of_week
CREATE INDEX IF NOT EXISTS idx_workouts_week_day ON program_workouts(week_id, day_of_week);
