# NYC 311 Response Time Equity Pipeline

## Overview

Does New York City close 311 complaints as quickly in communities of color as it does elsewhere? This project builds a data pipeline that pulls NYC 311 service requests and U.S. Census demographic data, then compares how long complaints take to close across ZIP codes grouped by their share of residents of color.

It's designed for community organizers and city staff who want to see whether service response times differ between neighborhoods. The analysis measures a **disparity** in response times; it does not, on its own, prove discrimination or explain why a gap exists.

**Scope:** every 311 complaint filed on or after January 1, 2026, which is about 3 million so far. The backfill was checked against the source API on October 5, 2026 (3,025,670 complaints, an exact match).

## First Results

These are from the data as of October 11, 2026. They are a first look, not a final analysis.

ZIP codes are ranked by % people of color and split into four quartiles. Quartile 1 has the highest share and quartile 4 the lowest. Each complaint type is compared across the four.

**There is no across-the-board gap.** Of the 78 complaint types with enough data to compare, the median time to close is longer in quartile 1 than in quartile 4 for 40, and the same or shorter for 38.

**The differences cluster by kind of complaint.** Tree complaints take longer in quartile 1:

| Complaint type | Median days to close, Q1 | Q4 | % not closed in 30 days, Q1 | Q4 |
|---|---|---|---|---|
| Overgrown Tree/Branches | 11.0 | 4.8 | 85.5 | 62.5 |
| Illegal Tree Damage | 12.9 | 1.9 | 54.5 | 28.0 |
| Dead/Dying Tree | 14.8 | 11.0 | 63.1 | 48.8 |

Several housing-condition complaints close faster in quartile 1:

| Complaint type | Median days to close, Q1 | Q4 | % not closed in 30 days, Q1 | Q4 |
|---|---|---|---|---|
| WATER LEAK | 11.0 | 15.3 | 23.2 | 31.0 |
| DOOR/WINDOW | 12.8 | 16.2 | 26.9 | 33.5 |
| UNSANITARY CONDITION | 11.0 | 13.9 | 22.7 | 25.9 |

These numbers show where gaps exist, not why. Quartile 1 files about five times as many water leak complaints as quartile 4, and volume, staffing, and how each agency closes cases could all play a part.

## Data Sources

| Source | What it provides | Granularity | Refresh |
|---|---|---|---|
| [NYC 311 Service Requests](https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9) (NYC Open Data, dataset `erm2-nwe9`) | Every 311 complaint: type, created/closed dates, ZIP, location | One row per complaint | Daily |
| [U.S. Census ACS 5-Year Estimates](https://www.census.gov/data/developers/data-sets/acs-5year.html), 2024 release, table **B03002** (Hispanic or Latino Origin by Race) | Total population and non-Hispanic white population | One row per ZIP Code Tabulation Area (ZCTA) | Yearly |

**% people of color** per ZIP = (total population − non-Hispanic white population) ÷ total population.

## Pipeline Design

```
NYC 311 API
    │
    ▼  Extract (Python): paged API calls
raw.service_requests_staging      temporary, replaced on every run
    │
    ▼  Upsert (SQL): INSERT ... ON CONFLICT (unique_key) DO UPDATE
raw.service_requests              permanent, one row per complaint, never replaced
    │
    │      Census API (ACS 5-year, table B03002)
    │          │
    │          ▼  Extract and load (Python): one request, table replaced
    │      raw.census_b03002      one row per ZCTA, whole US
    │          │
    ▼          ▼
Transform (SQL)
    analytics.requests_clean          one row per complaint, cleaned
    analytics.zip_demographics        one row per NYC ZIP, with its quartile
    │
    ▼  join on ZIP, group by complaint type and quartile
analytics.response_by_quartile_type ──▶ Power BI dashboard (planned)
```

1. **Extract** (`extract.py`)
   - `extract_rows(where)` pages through the 311 API (SoQL) for any filter, using `$limit`/`$offset` ordered by `unique_key`. It fails loudly on a missing API token, a non-200 response, or a request that takes longer than the timeout.
   - `extract_last_7_days()` builds the daily filter and calls `extract_rows`. The filter is "filed in the last 7 days, **or** filed in 2026 and closed in the last 7 days" (see Key Decisions).

2. **Load** (`load.py`)
   - Writes the pull into `raw.service_requests_staging` with pandas, storing every column exactly as received. Nested JSON fields (e.g., `location`) are stored as JSON strings; missing values stay `NULL`.
   - Runs one upsert from staging into `raw.service_requests`: complaints with a new `unique_key` are inserted, and complaints already in the table are updated in place. The column lists in the SQL are generated from the data, not typed by hand.
   - The load is idempotent: running the same pull twice leaves the table unchanged.

3. **Backfill** (`backfill.py`)
   - A one-time load of history. It walks from January 1, 2026 to today one week at a time, calling the same extract and load functions for each week.
   - It is safe to stop and restart, because reloading a week only updates rows that are already there.

4. **Census** (`census.py`)
   - `extract_census()` makes one request to the Census API for every ZCTA in the country and asks for two numbers from table B03002: total population (`B03002_001E`) and non-Hispanic white population (`B03002_003E`). There is no paging; the whole response is about 33,000 rows.
   - The response is a list of lists with the column names in the first item, not a list of dictionaries like 311. The first item becomes the column names and the rest become the rows.
   - It fails loudly on a missing API key, a non-200 response, or a request that takes longer than the timeout.
   - `load_census()` writes the result to `raw.census_b03002`, replacing the table on every run. Values and column names are stored exactly as received, plus an `acs_year` column added by the pipeline.
   - Nothing is filtered or calculated here. Narrowing to NYC and computing % people of color happen in Transform.

5. **Transform** (SQL, three files run in order)
   - `02_zip_demographics.sql` builds `analytics.zip_demographics`, one row per NYC ZIP. It renames and casts the Census columns, computes % people of color, keeps only ZIPs that belong to NYC (see Key Decisions), and assigns each ZIP a quartile with `NTILE(4)`.
   - `03_requests_clean.sql` builds `analytics.requests_clean`, one row per complaint. It keeps the ten columns the analysis needs, casts the dates to timestamps, removes rows that can't be used, and adds `days_to_close`. Open complaints are kept, with `days_to_close` empty.
   - `04_response_by_quartile.sql` builds `analytics.response_by_quartile_type`, one row per complaint type and quartile. It joins the two tables above on ZIP and computes the metrics below.
   - Every file drops and rebuilds its table, so all three can be rerun after each load.

6. **Serve**: `analytics.response_by_quartile_type` is the table the dashboard reads.

   | Column | Meaning |
   |---|---|
   | `complaint_type` | The 311 complaint category |
   | `quartile` | 1 = ZIPs with the highest % people of color, 4 = the lowest |
   | `complaint_count` | Complaints of that type filed in that quartile's ZIPs |
   | `median_days_to_close` | Median time from filed to closed, for closed complaints |
   | `pct_not_closed_in_30_days` | Of complaints old enough to judge, the percent still open or closed after more than 30 days |
   | `instant_count`, `pct_closed_instantly` | Complaints closed at the moment they were filed, as a count and as a percent |

   A Power BI dashboard on top of it is planned: median days to close by quartile for a selected complaint type. A ZIP-level table for a "find my neighborhood" view is planned after that.

The raw layer is kept untouched so that Transform logic can be fixed and rerun without calling the API again, and any dashboard number can be traced back to the source data.

## Key Decisions & Limitations

### Analysis

Counts in this section are from October 9 to 11, 2026.

- **Median, not mean.** A few complaints stay open for months; the median keeps those outliers from distorting typical response times.
- **A second metric for slow and unclosed complaints.** The median only sees complaints that closed, and it can't tell a group where 1% took months from one where 40% did. So each group also gets **% not closed within 30 days**: complaints that are still open, or that took more than 30 days. Only complaints filed at least 30 days before the newest complaint in the data are counted, because a complaint filed last week hasn't had its 30 days yet.
- **Compare within complaint type.** A noise complaint and a broken streetlight have very different normal close times. Comparing across types would mostly measure which complaints each neighborhood files, not how fast the city responds.
- **Quartiles of ZIPs.** ZIPs are ranked by % people of color and split into four equal groups, so each group has enough complaints to compare reliably. Quartile 1 is the highest share.
- **Which ZIPs count as NYC.** A ZIP is included only if at least 10 complaints were filed in it in 2026. Without this rule about 90 out-of-town ZIPs got in (San Francisco, Houston, Miami), because someone typed them on a complaint. The cutoff sits in a clear gap: out-of-town ZIPs topped out at 5 complaints and real ones started at 17.
- **ZIPs under 1,000 residents are not ranked.** Census figures are survey estimates and are too noisy for tiny populations. Before this rule, a ZIP with 7 residents ranked first. The result is 182 ZIPs.
- **Complaints with no usable ZIP are removed.** That is 27,701 complaints, about 0.9%. The original plan was to remove subway complaints, but the data showed subway is only 28% of the complaints with no ZIP; highways, streets, and bridges make up most of the rest.
- **A complaint is closed if it has a closed date.** The status column is not used. The two disagree on few rows: 9,121 have an open status with a closed date, and 9 have a closed status with no date.
- **Impossible dates are removed and counted.** 879 complaints were closed before they were filed, and 1 has a closed date in the future.
- **Instant closures are flagged, not removed.** 57,725 complaints (about 2%) have a closed time equal to their filed time. They are concentrated in a few complaint types, such as Real Time Enforcement (about 40% of its complaints) and Water System (about 25%). The serving table carries the share for every row, because a high share can make a quartile look faster than it is.
- **A complaint type needs 500 complaints in every quartile.** With small groups, one or two complaints swing the numbers. This keeps 78 of 185 complaint types and about 97% of complaints.
- **Every row is accounted for.** On October 9: 3,025,670 complaints filed in 2026, minus 27,701 with no usable ZIP, minus 879 closed before filing, minus 1 future-dated, equals the 2,997,089 rows in `analytics.requests_clean`. When the three tables were joined on October 11, 7,045 of 3,050,611 cleaned complaints (0.23%) fell in ZIPs that are not ranked.
- **Disparity, not causation.** Differences in close times can have many causes (complaint mix within a type, agency staffing, how cases are closed). This project shows *whether* a gap exists, not *why*.

### Pipeline

- **Upsert instead of replace.** The first version replaced the table with the latest 7 days on every run, which threw away history. The table now has a primary key on `unique_key`, and each run inserts new complaints and updates existing ones.
- **The table is defined in code.** `01_setup.sql` creates `raw.service_requests` with all 44 columns as text, so its shape doesn't depend on which pull happens to run first.
- **Pull by "filed or closed", not just "filed".** A filter on `created_date` alone has a blind spot: a complaint filed three weeks ago that closes today is outside the window, so the table would show it as open forever. That would push "% still open after 30 days" up and hide real closures. The daily filter therefore also pulls complaints whose `closed_date` is in the window.
- **Why not `:updated_at`.** The API has a hidden `:updated_at` field that would catch every kind of change. It was tested and rejected: the counts were correct, but response time was unpredictable (3 to 4 minutes for the first page on one run, a timeout past 10 minutes on the next). The filed-or-closed filter returns in seconds and covers the two events the metrics depend on.
- **A fixed start date, to avoid selection bias.** The filed-or-closed filter on its own pulls in old complaints only when they finally close, for example one filed in 2022 that took four years. A table built that way holds the slowest cases from past years without the fast ones, and any median computed from it would be badly skewed. A period can only be measured if the table holds every complaint filed in it. So the project is scoped to complaints filed on or after 2026-01-01, the backfill loads that whole period, and the daily filter ignores closures of anything filed earlier.
- **Backfill in weekly chunks.** A full year is about 3 million rows, too many to hold in memory at once. A week is about 68,000.
- **7-day lookback.** The pipeline is currently run by hand, so the window has to be longer than the longest gap between runs. Overlap costs nothing because of the upsert. It can shrink once the pipeline runs on a schedule.
- **Checked against the source.** After each change, the row count was compared with the API's own `count(*)` for the same filter. Two test weeks matched exactly (68,368 and 67,914), and so did the full backfill (3,025,670).

- **Census: replace, not upsert.** Each Census pull is the complete table, not a slice of it, so nothing in the old copy is worth keeping. That is the opposite of the 311 table, where each pull is one week and a replace would wipe out the rest.
- **Census column names are kept as received.** The raw table has columns named `B03002_001E` and `zip code tabulation area`, exactly as the API sends them, so raw stays a true copy of the source. The cost is that they need double quotes in SQL. They are renamed once, in Transform.
- **The ACS year is stored with the data.** Nothing in the API response says which year the numbers are from; the year only appears in the request URL. One `year` variable at the top of `census.py` sets both the URL and the `acs_year` column, so they can't disagree.
- **Census load checked.** The table has 33,772 rows, which is the 33,773 items in the API response minus the header. No ZCTA has a non-Hispanic white count larger than its total population, and a known ZIP was spot-checked by hand.

### Known limitations

- Changes that are neither a filing nor a closure (for example a status moving to "In Progress") are only picked up if the complaint is also inside the 7-day window.
- A few complaints filed before 2026 are in the raw table from early test runs. Transform filters them out.
- The main table's columns are fixed in `01_setup.sql`. If the city adds a column to the dataset, the load stops with an error until the column is added there.
- `load.py` assumes each pull is non-empty; an empty pull stops the run with an error.
- Census ZCTAs approximate USPS ZIP codes but are not identical to them. Two ZIPs in the table, 11001 and 11040, appear to straddle the Queens and Nassau County border, so their Census numbers include residents outside the city.
- The ACS year is changed by hand in `census.py` when a new release comes out. The margins of error that come with ACS estimates are not used.
- Duplicate reports are not handled. Several people can report the same issue, and each report counts as its own complaint.
- Complaint categories change during the year. Water System and Sewer have no complaints after July 29, 2026, while Water Maintenance and Sewer Maintenance run all year, so those rows cover different periods.
- Some complaint types appear to be closed by a fixed rule and not when the work is done. Food Establishment has a median of 60.01 days in every quartile, and Vendor Enforcement about 19 minutes in every quartile. They are left in the table.
- The reason for the instant closures is not known.
- One known bad record is excluded by its `unique_key` in `03_requests_clean.sql` (filed February 14, 2026 with a closed date of December 14, 2026). A general rule also removes any closed date later than the time of the run.
- The counts written in the SQL comments are from the day each file was written and will drift as new complaints load.

## Setup / How to Run

**Requirements:** Python 3.11+, PostgreSQL, a free [NYC Open Data app token](https://data.cityofnewyork.us/profile/edit/developer_settings), and a free [Census API key](https://api.census.gov/data/key_signup.html).

1. **Clone the repo and create a virtual environment**
   ```bash
   git clone https://github.com/EscoAl516/nyc311-pipeline.git
   cd nyc311-pipeline
   python -m venv venv
   venv\Scripts\activate        # Windows
   # source venv/bin/activate   # macOS/Linux
   ```

2. **Install dependencies**
   ```bash
   pip install requests pandas sqlalchemy psycopg2-binary python-dotenv
   ```

3. **Create a `.env` file** in the project folder (it's git-ignored, so credentials never reach GitHub):
   ```
   NYC_API_TOKEN=your_app_token
   CENSUS_API_TOKEN=your_census_key
   DB_USER=postgres
   DB_PASSWORD=your_password
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=nyc311
   ```

4. **Create the database, schema, and main table**
   ```bash
   psql -U postgres -f 01_setup.sql
   ```
   This creates the `nyc311` database, the `raw` schema, and `raw.service_requests` with its primary key on `unique_key`.

5. **Load the history**
   ```bash
   python backfill.py
   ```
   This loads every complaint filed since 2026-01-01, one week at a time, and prints a line per week. Expect it to take a while. If it stops partway, change `start` in `backfill.py` to the last week it printed and run it again.

6. **Load the Census data**
   ```bash
   python census.py
   ```
   This loads the 2024 ACS numbers for every ZCTA into `raw.census_b03002` and prints the row count (33,772). It only needs to run again when a new ACS release comes out: change `year` at the top of `census.py` and rerun.

7. **Build the analytics tables**
   ```bash
   psql -U postgres -d nyc311 -f 02_zip_demographics.sql
   psql -U postgres -d nyc311 -f 03_requests_clean.sql
   psql -U postgres -d nyc311 -f 04_response_by_quartile.sql
   ```
   Run them in this order, since each one reads the tables before it. They can also be run from a SQL client such as DBeaver. `03_requests_clean.sql` rebuilds a table of about 3 million rows and takes a minute or so.

8. **Keep it current**
   ```bash
   python load.py
   ```
   This pulls complaints filed or closed in the last 7 days and upserts them. Run it at least once every 7 days, then rerun the three SQL files from step 7. To test the extract step alone, run `python extract.py`.

## Status & Roadmap

- [x] Extract: 311 API with paging and error handling
- [x] Load: raw 311 data into PostgreSQL
- [x] Incremental loading: staging table and upsert on `unique_key`
- [x] Daily filter that picks up complaints closed after they were filed
- [x] Backfill of all complaints filed in 2026, verified against the API
- [x] Main table and primary key created by the setup script
- [x] Extract and load Census ACS table B03002
- [ ] Make the load handle empty pulls
- [x] Transform: cleaning, filtering, metrics, and the 311–Census join in SQL
- [x] Serving table by complaint type and quartile
- [ ] Power BI dashboard
- [ ] ZIP-level table for a "find my neighborhood" view
- [ ] Automation with Airflow and Docker
- [ ] Migration to Azure

## Tech Stack

Python (requests, pandas, SQLAlchemy) · PostgreSQL · SQL · Power BI · *planned:* Airflow, Docker, Azure
