-- Enable Row-Level Security (RLS) on core tables
ALTER TABLE complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaint_events ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- COMPLAINTS RLS POLICIES
-- =========================================================================

-- Policy 1: Citizen complaints access
-- Allows citizens to SELECT their own submitted complaints
CREATE POLICY select_citizen_own_complaints ON complaints
    FOR SELECT
    TO authenticated
    USING (
        citizen_id = auth.uid()
    );

-- Allows citizens to INSERT their own complaints (verified via token sub claim)
CREATE POLICY insert_citizen_own_complaints ON complaints
    FOR INSERT
    TO authenticated
    WITH CHECK (
        citizen_id = auth.uid()
    );

-- Policy 2: Officer & Supervisor jurisdiction-restricted access
-- Allows staff to view only complaints routed to their designated ward/zone
CREATE POLICY select_staff_jurisdiction_complaints ON complaints
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()
              AND users.role IN ('officer', 'supervisor')
              AND users.jurisdiction_id = complaints.jurisdiction_id
        )
    );

-- Policy 3: Administrator bypass policy
-- Gives administrators unrestricted access to all complaints
CREATE POLICY select_admin_all_complaints ON complaints
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()
              AND users.role = 'admin'
        )
    );


-- =========================================================================
-- COMPLAINT EVENTS RLS POLICIES
-- =========================================================================

-- Policy 1: Citizen timeline access
-- Citizens can select history events for their own complaints
CREATE POLICY select_citizen_own_complaint_events ON complaint_events
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM complaints
            WHERE complaints.id = complaint_events.complaint_id
              AND complaints.citizen_id = auth.uid()
        )
    );

-- Policy 2: Staff timeline access
-- Officers & Supervisors can select history events for complaints in their jurisdiction
CREATE POLICY select_staff_jurisdiction_complaint_events ON complaint_events
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM complaints
            JOIN users ON users.id = auth.uid()
            WHERE complaints.id = complaint_events.complaint_id
              AND users.role IN ('officer', 'supervisor')
              AND users.jurisdiction_id = complaints.jurisdiction_id
        )
    );

-- Policy 3: Admin bypass policy
CREATE POLICY select_admin_all_complaint_events ON complaint_events
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()
              AND users.role = 'admin'
        )
    );
