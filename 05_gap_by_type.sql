-- Builds analytics.gap_by_type: one row per complaint type, comparing quartile 1
-- (highest % people of color) with quartile 4 (lowest). Reads the answer table
-- from 04_response_by_quartile.sql, so run that file first.
-- Safe to rerun: the table is dropped and rebuilt every time.

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.gap_by_type;

CREATE TABLE analytics.gap_by_type as

-- Step 1: pivot. The answer table has four rows per complaint type, one per
-- quartile. FILTER picks out quartile 1 and quartile 4 so they sit side by side
-- in one row. Each type has exactly one row per quartile, so MAX just returns it.
with aggregation as
(
	select
		rbqt.complaint_type,
		MAX(rbqt.median_days_to_close) filter (where rbqt.quartile = 1) as q1_median_days,
		MAX(rbqt.median_days_to_close) filter (where rbqt.quartile = 4) as q4_median_days,
		MAX(rbqt.pct_not_closed_in_30_days) filter (where rbqt.quartile = 1) as q1_pct_slow,
		MAX(rbqt.pct_not_closed_in_30_days) filter (where rbqt.quartile = 4) as q4_pct_slow
	from
		analytics.response_by_quartile_type rbqt
	group by
		rbqt.complaint_type
)

select
	complaint_type,
	q1_median_days,
	q4_median_days,
	-- Q1 median divided by Q4 median. Above 1 means quartile 1 waits longer.
	-- The cast is needed because ROUND with decimal places only accepts numeric.
	ROUND(q1_median_days::numeric / nullif(q4_median_days::numeric, 0),2) as median_ratio,
	q1_pct_slow,
	q4_pct_slow,
	-- Decision: the dashboard charts this gap, not the ratio. A ratio exaggerates
	-- types that close in minutes (Water System: 53 min vs 3.7 hours = 0.24x), and a
	-- difference in days is dominated by types with long waits (For Hire Vehicle:
	-- +83 days). Percentage points stay on one scale for every complaint type.
	-- Positive means quartile 1 had more complaints not closed within 30 days.
	(q1_pct_slow - q4_pct_slow) as pct_point_gap
from
	aggregation;
