-- Builds analytics.requests_clean: one row per 311 complaint filed in 2026,
-- with real data types and a days_to_close column. Safe to rerun: the table
-- is dropped and rebuilt from raw every time.

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.requests_clean;

CREATE TABLE analytics.requests_clean as

select
	unique_key,
	created_date::timestamp,
	-- Decision: a complaint is closed if it has a closed date; status is not used.
	-- The two disagree on few rows: 9,121 have an open status with a closed date,
	-- and 9 have a closed status with no closed date.
	closed_date::timestamp,
	agency,
	complaint_type,
	status,
	location_type,
	borough,
	incident_zip,
	-- Days with decimals (86400 seconds in a day). NULL while the complaint is open.
	EXTRACT(EPOCH from (closed_date::timestamp - created_date::timestamp)) / 86400 as days_to_close
from
	raw.service_requests
where
	created_date::DATE >= '2026-01-01'and
	-- Decision: complaints with no usable ZIP are removed, because they can't be
	-- placed in a neighborhood. About 27,700 rows have a NULL ZIP; subway is only
	-- 28% of them (the rest are highways, streets, bridges, and others).
	incident_zip is not null and
	incident_zip not in ('No','N/A') and
	-- Open complaints are kept. Complaints closed before they were created (879 rows)
	-- or closed in the future (1 row) are removed as bad data. Complaints closed at
	-- the same moment they were created are kept (57,725 rows).
	unique_key != '67996481' and -- Known bad record: filed 2026-02-14, closed date typed as 2026-12-14.
	(closed_date is null or
		(closed_date::timestamp >= created_date::timestamp and closed_date::timestamp <= now()));