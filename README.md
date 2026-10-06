# NYC 311 Response Time Equity Pipeline

## Overview

Does New York City close 311 complaints as quickly in communities of color as it does elsewhere? This project builds a data pipeline that pulls NYC 311 service requests and U.S. Census demographic data, then compares how long complaints take to close across ZIP codes grouped by their share of residents of color.

It's designed for community organizers and city staff who want to see whether service response times differ between neighborhoods. The analysis measures a **disparity** in response times; it does not, on its own, prove discrimination or explain why a gap exists.

**Scope:** every 311 complaint filed on or after January 1, 2026. As of October 5, 2026 that is 3,025,670 complaints, loaded and checked against the source API.

## Data Sources

| Source | What it provides | Granularity | Refresh |
|---|---|---|---|
| [NYC 311 Service Requests](https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9) (NYC Open Data, dataset `erm2-nwe9`) | Every 311 complaint: type, created/closed dates, ZIP, location | One row per complaint | Daily |
| U.S. Census ACS 5-Year Estimates, table **B03002** (Hispanic or Latino Origin by Race) | Population by race and ethnicity | ZIP code (ZCTA) | Yearly |

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
    │◀──── Census ACS B03002 (planned)
    ▼
Transform (SQL, planned)
    │
    ▼
Serving table ──▶ Power BI dashboard (planned)
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

4. **Transform** (SQL, planned)
   - Clean: convert `"N/A"` and blank strings to `NULL`; cast text to proper types
   - Filter: keep complaints filed on or after 2026-01-01; remove subway complaints (no neighborhood address) and rows where the closed date is before the created date (counting what's dropped)
   - Calculate: days to close, % people of color per ZIP, ZIP quartile (`NTILE(4)`), duplicate-report flag
   - Join: 311 complaints to Census data on ZIP

5. **Serve** (planned): a final table with one row per ZIP and complaint type:

   `zip | quartile | complaint_type | median_days_to_close | pct_open_after_30_days | complaint_count`

   This feeds a Power BI dashboard: median days to close by quartile for a selected complaint type, plus a "find my neighborhood" view.

The raw layer is kept untouched so that Transform logic can be fixed and rerun without calling the API again, and any dashboard number can be traced back to the source data.

## Key Decisions & Limitations

### Analysis

- **Median, not mean.** A few complaints stay open for months; the median keeps those outliers from distorting typical response times.
- **Compare within complaint type.** A noise complaint and a broken streetlight have very different normal close times. Comparing across types would mostly measure which complaints each neighborhood files, not how fast the city responds.
- **Quartiles of ZIPs.** ZIPs are ranked by % people of color and split into four equal groups, so each group has enough complaints to compare reliably.
- **Open complaints are tracked, not ignored.** Days-to-close only works for closed complaints, so a second metric, **% still open after 30 days**, keeps slow neighborhoods from looking fast just because their complaints haven't closed yet.
- **Geography is `incident_zip`.** Subway complaints are excluded because they have no neighborhood address.
- **Bad dates are removed and counted.** Rows with a closed date before the created date are filtered out, and the number dropped is reported.
- **Duplicate reports are flagged, not removed (v1).** Several people can report the same issue; this is a known limitation.
- **Disparity, not causation.** Differences in close times can have many causes (complaint mix within a type, agency staffing, how cases are closed). This project shows *whether* a gap exists, not *why*.

### Pipeline

- **Upsert instead of replace.** The first version replaced the table with the latest 7 days on every run, which threw away history. The table now has a primary key on `unique_key`, and each run inserts new complaints and updates existing ones.
- **Pull by "filed or closed", not just "filed".** A filter on `created_date` alone has a blind spot: a complaint filed three weeks ago that closes today is outside the window, so the table would show it as open forever. That would push "% still open after 30 days" up and hide real closures. The daily filter therefore also pulls complaints whose `closed_date` is in the window.
- **Why not `:updated_at`.** The API has a hidden `:updated_at` field that would catch every kind of change. It was tested and rejected: the counts were correct, but response time was unpredictable (3 to 4 minutes for the first page on one run, a timeout past 10 minutes on the next). The filed-or-closed filter returns in seconds and covers the two events the metrics depend on.
- **A fixed start date, to avoid selection bias.** The filed-or-closed filter on its own pulls in old complaints only when they finally close, for example one filed in 2022 that took four years. A table built that way holds the slowest cases from past years without the fast ones, and any median computed from it would be badly skewed. A period can only be measured if the table holds every complaint filed in it. So the project is scoped to complaints filed on or after 2026-01-01, the backfill loads that whole period, and the daily filter ignores closures of anything filed earlier.
- **Backfill in weekly chunks.** A full year is about 3 million rows, too many to hold in memory at once. A week is about 68,000.
- **7-day lookback.** The pipeline is currently run by hand, so the window has to be longer than the longest gap between runs. Overlap costs nothing because of the upsert. It can shrink once the pipeline runs on a schedule.
- **Checked against the source.** After each change, the row count was compared with the API's own `count(*)` for the same filter. Two test weeks matched exactly (68,368 and 67,914), and so did the full backfill (3,025,670).

### Known limitations

- Changes that are neither a filing nor a closure (for example a status moving to "In Progress") are only picked up if the complaint is also inside the 7-day window.
- A few complaints filed before 2026 are in the raw table from early test runs. Transform filters them out.
- Creating the main table on a fresh database is a manual step (see Setup).
- `load.py` assumes each pull is non-empty and has no columns the main table lacks; either case stops the run with an error.

## Setup / How to Run

**Requirements:** Python 3.11+, PostgreSQL, and a free [NYC Open Data app token](https://data.cityofnewyork.us/profile/edit/developer_settings).

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
   NYC_APP_TOKEN=your_app_token
   DB_USER=postgres
   DB_PASSWORD=your_password
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=nyc311
   ```

4. **Create the database and schema**
   ```bash
   psql -U postgres -f 01_setup.sql
   ```

5. **First run only: create the main table.** The upsert needs `raw.service_requests` to exist with a primary key. This isn't scripted yet, so do it once by hand:
   1. Run `python load.py`. It fills the staging table, then stops with an error because the main table doesn't exist.
   2. In `psql` or DBeaver, connected to `nyc311`, run:
      ```sql
      CREATE TABLE raw.service_requests (LIKE raw.service_requests_staging);
      ALTER TABLE raw.service_requests ADD PRIMARY KEY (unique_key);
      ```

6. **Load the history**
   ```bash
   python backfill.py
   ```
   This loads every complaint filed since 2026-01-01, one week at a time, and prints a line per week. Expect it to take a while. If it stops partway, change `start` in `backfill.py` to the last week it printed and run it again.

7. **Keep it current**
   ```bash
   python load.py
   ```
   This pulls complaints filed or closed in the last 7 days and upserts them. Run it at least once every 7 days. To test the extract step alone, run `python extract.py`.

## Status & Roadmap

- [x] Extract: 311 API with paging and error handling
- [x] Load: raw 311 data into PostgreSQL
- [x] Incremental loading: staging table and upsert on `unique_key`
- [x] Daily filter that picks up complaints closed after they were filed
- [x] Backfill of all complaints filed in 2026, verified against the API
- [ ] Script the main table creation so setup is a single step
- [ ] Make the load handle empty pulls and new columns
- [ ] Extract and load Census ACS table B03002
- [ ] Transform: cleaning, filtering, metrics, and the 311–Census join in SQL
- [ ] Serving table and Power BI dashboard
- [ ] Automation with Airflow and Docker
- [ ] Migration to Azure

## Tech Stack

Python (requests, pandas, SQLAlchemy) · PostgreSQL · SQL · Power BI · *planned:* Airflow, Docker, Azure