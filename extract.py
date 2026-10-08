import requests
import os
from dotenv import load_dotenv
from datetime import date, timedelta
def extract_rows(where):

    load_dotenv()
    app_token = os.getenv("NYC_API_TOKEN")
    if not app_token:
        raise Exception(
            "NYC_APP_TOKEN is not set. Add a line like NYC_APP_TOKEN=your_token "
            "to the .env file in the project folder."
            )
    url = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"

    all_rows = []
    offset = 0
    limit = 50000

    headers = {
        "X-App-Token": app_token
    }

    while True:
        params = {
            "$where": where,
            "$order": "unique_key",
            "$limit": limit,
            "$offset": offset,
        }

        response = requests.get(url, params=params, headers = headers, timeout=120)

        if response.status_code != 200:
            raise Exception((
                f"API request failed with status {response.status_code} at offset {offset}. "
                f"Response: {response.text[:500]}"
            ))

        data = response.json()

        print(offset, len(data))

        all_rows.extend(data)

        if len(data) < limit:
            break

        offset += limit
    return all_rows
def extract_last_7_days():
    window_start = date.today() - timedelta(days=7)
    where = f"created_date >= '{window_start}' OR (closed_date >= '{window_start}' AND created_date >= '2026-01-01')"
    return extract_rows(where)
if __name__ == "__main__":
    rows = extract_last_7_days()
    print(f"Extracted {len(rows)} rows")