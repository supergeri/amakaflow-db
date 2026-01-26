-- ============================================================================
-- AMA-492: Fix RLS Policies (Recovery Migration)
--
-- The previous migration (20260128000000) failed because service role policies
-- already existed. This migration completes the policy setup idempotently.
-- ============================================================================

-- Drop all existing policies to ensure clean state
DROP POLICY IF EXISTS "Users can view weeks of own programs" ON program_weeks;
DROP POLICY IF EXISTS "Users can create weeks for own programs" ON program_weeks;
DROP POLICY IF EXISTS "Users can update weeks of own programs" ON program_weeks;
DROP POLICY IF EXISTS "Users can delete weeks of own programs" ON program_weeks;
DROP POLICY IF EXISTS "Service role full access on program weeks" ON program_weeks;

DROP POLICY IF EXISTS "Users can view workouts of own programs" ON program_workouts;
DROP POLICY IF EXISTS "Users can create workouts for own programs" ON program_workouts;
DROP POLICY IF EXISTS "Users can update workouts of own programs" ON program_workouts;
DROP POLICY IF EXISTS "Users can delete workouts of own programs" ON program_workouts;
DROP POLICY IF EXISTS "Service role full access on program workouts" ON program_workouts;

-- Drop new policies if they exist (in case partial run)
DROP POLICY IF EXISTS "Users can view own program weeks" ON program_weeks;
DROP POLICY IF EXISTS "Users can create own program weeks" ON program_weeks;
DROP POLICY IF EXISTS "Users can update own program weeks" ON program_weeks;
DROP POLICY IF EXISTS "Users can delete own program weeks" ON program_weeks;

DROP POLICY IF EXISTS "Users can view own program workouts" ON program_workouts;
DROP POLICY IF EXISTS "Users can create own program workouts" ON program_workouts;
DROP POLICY IF EXISTS "Users can update own program workouts" ON program_workouts;
DROP POLICY IF EXISTS "Users can delete own program workouts" ON program_workouts;

-- ============================================================================
-- Create RLS policies
--
-- SELECT/UPDATE/DELETE: Use direct user_id check (fast, no joins)
-- INSERT: Keep join-based check (trigger runs after RLS, so can't rely on it)
-- ============================================================================

-- program_weeks policies
CREATE POLICY "Users can view own program weeks"
    ON program_weeks FOR SELECT
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can create own program weeks"
    ON program_weeks FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM training_programs tp
        WHERE tp.id = program_weeks.program_id
        AND tp.user_id = current_setting('request.jwt.claims', true)::json->>'sub'
    ));

CREATE POLICY "Users can update own program weeks"
    ON program_weeks FOR UPDATE
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can delete own program weeks"
    ON program_weeks FOR DELETE
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- program_workouts policies
CREATE POLICY "Users can view own program workouts"
    ON program_workouts FOR SELECT
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can create own program workouts"
    ON program_workouts FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM program_weeks pw
        JOIN training_programs tp ON tp.id = pw.program_id
        WHERE pw.id = program_workouts.week_id
        AND tp.user_id = current_setting('request.jwt.claims', true)::json->>'sub'
    ));

CREATE POLICY "Users can update own program workouts"
    ON program_workouts FOR UPDATE
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

CREATE POLICY "Users can delete own program workouts"
    ON program_workouts FOR DELETE
    USING (user_id = current_setting('request.jwt.claims', true)::json->>'sub');

-- ============================================================================
-- Service role access
-- ============================================================================

CREATE POLICY "Service role full access on program weeks"
    ON program_weeks FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

CREATE POLICY "Service role full access on program workouts"
    ON program_workouts FOR ALL
    USING (current_setting('request.jwt.claims', true)::json->>'role' = 'service_role');

-- ============================================================================
-- Triggers (idempotent - CREATE OR REPLACE)
-- ============================================================================

-- Trigger for program_weeks: copy user_id from parent training_programs
CREATE OR REPLACE FUNCTION set_program_weeks_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        SELECT user_id INTO NEW.user_id
        FROM training_programs
        WHERE id = NEW.program_id;

        IF NEW.user_id IS NULL THEN
            RAISE EXCEPTION 'Cannot set user_id: training_programs with id % not found', NEW.program_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_program_weeks_user_id ON program_weeks;
CREATE TRIGGER trigger_set_program_weeks_user_id
    BEFORE INSERT ON program_weeks
    FOR EACH ROW EXECUTE FUNCTION set_program_weeks_user_id();

-- Trigger for program_workouts: copy user_id from parent program_weeks
CREATE OR REPLACE FUNCTION set_program_workouts_user_id()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        SELECT user_id INTO NEW.user_id
        FROM program_weeks
        WHERE id = NEW.week_id;

        IF NEW.user_id IS NULL THEN
            RAISE EXCEPTION 'Cannot set user_id: program_weeks with id % not found', NEW.week_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_set_program_workouts_user_id ON program_workouts;
CREATE TRIGGER trigger_set_program_workouts_user_id
    BEFORE INSERT ON program_workouts
    FOR EACH ROW EXECUTE FUNCTION set_program_workouts_user_id();

-- Prevent user_id modification (data integrity)
CREATE OR REPLACE FUNCTION prevent_user_id_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_id IS DISTINCT FROM NEW.user_id THEN
        RAISE EXCEPTION 'Cannot modify user_id on %', TG_TABLE_NAME;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS prevent_program_weeks_user_id_change ON program_weeks;
CREATE TRIGGER prevent_program_weeks_user_id_change
    BEFORE UPDATE ON program_weeks
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_modification();

DROP TRIGGER IF EXISTS prevent_program_workouts_user_id_change ON program_workouts;
CREATE TRIGGER prevent_program_workouts_user_id_change
    BEFORE UPDATE ON program_workouts
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_modification();
