"""Export the two tables the dashboard reads to CSV files in data/.

GitHub shows CSV files as a searchable table, so anyone can browse the results
without a database or Power BI. Run after the SQL files:

    python export_csv.py
"""
from pathlib import Path

import pandas as pd
from sqlalchemy import text

from load import get_engine

TABLES = {
    "gap_by_type": """
        SELECT * FROM analytics.gap_by_type
        ORDER BY pct_point_gap DESC
    """,
    "response_by_quartile_type": """
        SELECT * FROM analytics.response_by_quartile_type
        ORDER BY complaint_type, quartile
    """,
}


def export_tables(engine, out_dir="data"):
    out = Path(out_dir)
    out.mkdir(exist_ok=True)

    with engine.connect() as conn:
        for name, sql in TABLES.items():
            df = pd.read_sql(text(sql), conn)
            # Medians come out of Postgres with 15+ decimal places; 3 is enough
            # to read minutes on types that close within hours.
            df = df.round(3)
            path = out / f"{name}.csv"
            df.to_csv(path, index=False)
            print(f"{path}: {len(df)} rows")


if __name__ == "__main__":
    export_tables(get_engine())
