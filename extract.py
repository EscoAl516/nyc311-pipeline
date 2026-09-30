import requests
import os
from dotenv import load_dotenv
from datetime import date, timedelta

load_dotenv()
app_token = os.getenv("NYC_APP_TOKEN")
print(app_token is not None)
url = "https://data.cityofnewyork.us/resource/erm2-nwe9.json"

all_rows = []
offset = 0
limit = 10000

start = date.today() #This pulls todays date
end = start - timedelta(days = 7) #Pulls a week before today

headers = {
    "X-App-Token": app_token
}

while True:
    params = {
        "$where": f"created_date >= '{end}' AND created_date < '{start}'",
        "$order": "unique_key",
        "$limit": limit,
        "$offset": offset,
    }

    response = requests.get(url, params=params, headers = headers, timeout=60)

    if response.status_code != 200:
        raise Exception(f"You received an error with {response.status_code} response code at offset {offset}")

    data = response.json()

    print(offset, len(data))

    all_rows.extend(data)

    if len(data) < limit:
        break

    offset += limit

print(len(all_rows))
print(response.status_code)
print(all_rows[-3:])