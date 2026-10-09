-- Builds analytics.zip_demographics: one row per NYC ZCTA with its
-- % people of color (pct_poc) and its quartile. Safe to rerun: the table
-- is dropped and rebuilt from raw every time.

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.zip_demographics;


CREATE TABLE analytics.zip_demographics as

with census as(
	select
		"zip code tabulation area" as zcta,
		"B03002_001E"::int as total_pop,
		"B03002_003E"::int as white_nh_pop,
		ROUND((1-("B03002_003E"::numeric/"B03002_001E"::int)) * 100,2) as pct_poc,
		acs_year
	from
		raw.census_b03002
	where
		-- Decision: ZCTAs under 1,000 residents are not ranked. The Census figures
		-- are survey estimates, so the percentage is too noisy for small populations.
		-- This also removes zero-population ZCTAs, which have no percentage to compute.
		"B03002_001E"::int >= 1000
),

nyc AS(
	select
		incident_zip as zip
	from
		raw.service_requests
	where
		incident_zip is not null AND
		created_date::DATE >= '2026-01-01'
	group by
		incident_zip
	having
		-- Decision: a ZIP needs at least 10 complaints in 2026 to count as NYC.
		-- Out-of-town ZIPs typed on a complaint topped out at 5; real ones start at 17.
		count(*) >= 10
)

select
	ny.zip as zcta,
	cs.total_pop,
	cs.white_nh_pop,
	cs.pct_poc,
	-- Quartile 1 = highest % people of color, quartile 4 = lowest.
	ntile(4) OVER(order by cs.pct_poc DESC) as quartile,
	cs.acs_year
from
	census as cs
join
	nyc as ny on ny.zip = cs.zcta;
