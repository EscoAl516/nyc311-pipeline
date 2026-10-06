from datetime import date, timedelta
from extract import extract_rows
from load import get_engine, load_raw


start = date(2026, 1, 1)
end = date.today()

engine = get_engine()

week_start = start
while week_start < end:
    week_end = week_start + timedelta(days=7)

    where = f"created_date >= '{week_start}' AND created_date < '{week_end}'"

    rows = extract_rows(where)
    count = load_raw(rows, engine)
    print(f"{week_start} to {week_end}: loaded {count} rows")

    week_start = week_end