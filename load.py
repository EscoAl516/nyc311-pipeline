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
    df = pd.DataFrame(rows)
    df["location"] = df["location"].apply(lambda x: json.dumps(x) if isinstance(x, dict) else x)

    df.to_sql(
        name = "service_requests",
        con = engine,
        schema = "raw",
        if_exists = "replace",  
        index = False,
        chunksize = 5000,
    )
    return len(df)
if __name__ == "__main__":
    engine = get_engine()
    rows = extract_last_7_days()
    count = load_raw(rows, engine)
    with engine.connect() as conn:
        result = conn.execute(text("SELECT current_database(), current_user"))
        print(result.fetchone())