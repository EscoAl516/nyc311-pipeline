-- Builds analytics.response_by_quartile_type: one row per complaint type and
-- quartile of ZIPs (quartile 1 = highest % people of color), with the median
-- days to close and the share of complaints not closed within 30 days.
-- Safe to rerun: the table is dropped and rebuilt every time.

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.response_by_quartile_type;

CREATE TABLE analytics.response_by_quartile_type as

-- Step 1: one row per complaint, with its quartile and two true/false labels.
-- Complaints in ZIPs that are not ranked drop out at the join.
with flagged as (
	select
		rc.complaint_type,
		zd.quartile,
		rc.days_to_close,
		-- old_enough: filed at least 30 days before the newest complaint in the table.
		-- The table's own latest date is used instead of today's date, so the result
		-- does not depend on when the load last ran.
		rc.created_date <= (select max(created_date) from analytics.requests_clean) - interval '30 days' as old_enough,
		-- slow: still open, or took more than 30 days to close.
		(rc.closed_date is null or rc.days_to_close > 30) as slow
	from
		analytics.requests_clean rc
	join
		analytics.zip_demographics zd on zd.zcta = rc.incident_zip
),
-- Step 2: one row per complaint type and quartile. The median uses closed
-- complaints only (open ones have no days_to_close).
grouped as(
select
	complaint_type,
	quartile,
	COUNT(*) as complaint_count,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_to_close) AS median_days_to_close,
	COUNT(*) FILTER (WHERE old_enough) AS eligible_count,
	COUNT(*) FILTER (WHERE old_enough AND slow) AS slow_count,
	COUNT(*) filter (where days_to_close = 0) as instant_count
from
	flagged
group by
	complaint_type,
	quartile
),
-- Step 3: the complaint types with enough data to compare.
-- Decision: a type is kept only if all four quartiles have at least 500 complaints.
-- With fewer, one or two complaints swing the numbers. This keeps 78 of 185 types
-- and about 97% of complaints.
keep_types as (
	select
	    complaint_type
	from
		grouped
	where
		complaint_count >= 500
	group by
		complaint_type
	having
		count(*) = 4
)
select
	complaint_type,
	quartile,
	complaint_count,
	instant_count,
	median_days_to_close,
	-- Of the complaints old enough to judge, the percent that were slow. Recent
	-- complaints are left out because they have not had their 30 days yet.
	ROUND((slow_count * 100.00)/nullif(eligible_count,0),1) as pct_not_closed_in_30_days,
	-- Decision: complaints closed at the moment they were filed are flagged, not removed.
	-- A few types have many of them (Real Time Enforcement about 40%, Water System about 25%),
	-- which can make a quartile look faster than it is.
	ROUND((instant_count * 100.00)/nullif(complaint_count,0),1) as pct_closed_instantly
from
	grouped
where
	complaint_type in (select complaint_type from keep_types);
