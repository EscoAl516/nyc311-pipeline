# NYC 311 Response Time Equity Pipeline

## Overview

Does New York City close 311 complaints as quickly in communities of color as it does elsewhere? This project builds a data pipeline that pulls NYC 311 service requests and U.S. Census demographic data, then compares how long complaints take to close across ZIP codes grouped by their share of residents of color.

It's designed for community organizers and city staff who want to see whether service response times differ between neighborhoods. The analysis measures a **disparity** in response times; it does not, on its own, prove discrimination or explain why a gap exists.

## Data Sources

| Source | What it provides | Granularity | Refresh |
|---|---|---|---|
| [NYC 311 Service Requests](https://data.cityofnewyork.us/Social-Services/311-Service-Requests-from-2010-to-Present/erm2-nwe9) (NYC Open Data, dataset `erm2-nwe9`) | Every 311 complaint: type, created/closed dates, ZIP, location | One row per complaint | Daily |
| U.S. Census ACS 5-Year Estimates, table **B03002** (Hispanic or Latino Origin by Race) | Population by race and ethnicity | ZIP code (ZCTA) | Yearly |

**% people of color** per ZIP = (total population − non-Hispanic white population) ÷ total population.

## Pipeline Design

```
NYC 311 API ──▶ Extract (Python) ──▶ Load ──▶ PostgreSQL: raw schema
                                                     │
Census ACS ─────────────────────────────────────────▶│
                                                     ▼
                                           Transform (SQL)
                                                     │
                                                     ▼
                                           Serving table ──▶ Power BI dashboard
```

1. **Extract** (`extract.py`): calls the 311 API (SoQL) for a rolling 7-day window, paging through results with `$limit`/`$offset` ordered by `unique_key`. Fails loudly on a missing API token or any non-200 response.
2. **Load** (`load.py`): writes every column exactly as received into `raw.service_requests` in PostgreSQL using pandas and SQLAlchemy. Nested JSON fields (e.g., `location`) are stored as JSON strings; missing values stay `NULL`.
3. **Transform** (SQL, planned):
   - Clean: convert `"N/A"` and blank strings to `NULL`; cast text to proper types
   - Filter: remove subway complaints (no neighborhood address) and rows where the closed date is before the created date (counting what's dropped)
   - Calculate: days to close, % people of color per ZIP, ZIP quartile (`NTILE(4)`), duplicate-report flag
   - Join: 311 complaints to Census data on ZIP
4. **Serve** (planned): a final table with one row per ZIP and complaint type:

   `zip | quartile | complaint_type | median_days_to_close | pct_open_after_30_days | complaint_count`

   This feeds a Power BI dashboard: median days to close by quartile for a selected complaint type, plus a "find my neighborhood" view.

The raw layer is kept untouched so that Transform logic can be fixed and rerun without calling the API again, and any dashboard number can be traced back to the source data.

## Key Decisions & Limitations

- **Median, not mean.** A few complaints stay open for months; the median keeps those outliers from distorting typical response times.
- **Compare within complaint type.** A noise complaint and a broken streetlight have very different normal close times. Comparing across types would mostly measure which complaints each neighborhood files, not how fast the city responds.
- **Quartiles of ZIPs.** ZIPs are ranked by % people of color and split into four equal groups, so each group has enough complaints to compare reliably.
- **Open complaints are tracked, not ignored.** Days-to-close only works for closed complaints, so a second metric, **% still open after 30 days**, keeps slow neighborhoods from looking fast just because their complaints haven't closed yet.
- **Geography is `incident_zip`.** Subway complaints are excluded because they have no neighborhood address.
- **Bad dates are removed and counted.** Rows with a closed date before the created date are filtered out, and the number dropped is reported.
- **Duplicate reports are flagged, not removed (v1).** Several people can report the same issue; this is a known limitation.
- **Disparity, not causation.** Differences in close times can have many causes (complaint mix within a type, agency staffing, how cases are closed). This project shows *whether* a gap exists, not *why*.

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

5. **Run the pipeline**
   ```bash
   python load.py
   ```
   This extracts the last 7 days of complaints and loads them into `raw.service_requests`. To only test the extract step, run `python extract.py`.

## Status & Roadmap

- [x] Extract: 311 API with paging and error handling
- [x] Load: raw 311 data into PostgreSQL
- [ ] Incremental loading: upsert by `unique_key` so history accumulates and later closures update existing rows (currently each run replaces the table with the latest 7 days)
- [ ] Extract and load Census ACS table B03002
- [ ] Transform: cleaning, filtering, metrics, and the 311–Census join in SQL
- [ ] Serving table and Power BI dashboard
- [ ] Automation with Airflow and Docker
- [ ] Migration to Azure

## Tech Stack

Python (requests, pandas, SQLAlchemy) · PostgreSQL · SQL · Power BI · *planned:* Airflow, Docker, Azure
