import os
import json
import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from extract import extract_last_7_days

load_dotenv()

def get_engine():
    url = URL.create(
        drivername = "postgresql+psycopg2",
        username =os.getenv("DB_USER"),
        password=os.getenv("DB_PASSWORD"),
        host=os.getenv("DB_HOST"),
        port=os.getenv("DB_PORT"),
        database=os.getenv("DB_NAME"),
    )
    return create_engine(url)

def load_raw(rows, engine):    
    df = pd.DataFrame(rows) #DF makes a table like a spreadsheet. Each dictionary from rows becomes a row. The Keys are the columns. A missing key is a missing cell
    df["location"] = df["location"].apply(lambda x: json.dumps(x) if isinstance(x, dict) else x)

    df.to_sql(
        name = "service_requests_staging",
        con = engine,
        schema = "raw",
        if_exists = "replace",  
        index = False,
        chunksize = 5000,
    )

    cols = list(df.columns)

    col_str = ", ".join(cols)

    update_items = []
    for col in cols:
        if col != "unique_key":
            update_items.append(f"{col} = EXCLUDED.{col}")
    update_str = ", ".join(update_items)

    sql = f"""
    INSERT INTO raw.service_requests ({col_str})
    SELECT {col_str}
    FROM raw.service_requests_staging
    ON CONFLICT (unique_key) DO UPDATE SET {update_str};
    """

    with engine.begin() as conn:
        conn.execute(text(sql))

    return len(df) #Returns the number of rows
if __name__ == "__main__":
    engine = get_engine()
    rows = extract_last_7_days() #rows is a list of dictionaries. It hold every complaint and all it's values. Every Key is a column and the value is the value that goes with it.
    count = load_raw(rows, engine) #count = the number of rows
    print(f"Loaded {count} rows into staging and upserted into raw.service_requests")
    with engine.connect() as conn:
        result = conn.execute(text("SELECT current_database(), current_user"))
        print(result.fetchone())