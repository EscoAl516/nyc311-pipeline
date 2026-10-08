import requests
import os
import pandas as pd
from dotenv import load_dotenv
from load import get_engine


year = 2024

def extract_census():

    load_dotenv()
    app_token = os.getenv("CENSUS_API_TOKEN")
    if not app_token:
        raise Exception(
            "CENSUS_API_TOKEN is not set. Add a line like CENSUS_API_TOKEN=your_token "
            "to the .env file in the project folder."
        )

    url = f"https://api.census.gov/data/{year}/acs/acs5"

    params = {
        "get": "NAME,B03002_001E,B03002_003E",
        "for": "zip code tabulation area:*",
        "key": app_token
    }
    response = requests.get(url, params=params, timeout=120)

    if response.status_code != 200:
        raise Exception((
            f"API request failed with status {response.status_code}"
            f"Response: {response.text[:500]}"
        ))
    
    data = response.json()
    
    df = pd.DataFrame(data[1:],columns = data[0])
    df["acs_year"] = year

    return df

def load_census(rows, engine):

    rows.to_sql(
        name = "census_b03002",
        con = engine,
        schema = "raw",
        if_exists = "replace",
        index = False,
        chunksize = 5000,
    )

if __name__ == "__main__":
    df = extract_census()
    engine = get_engine()
    load_census(df, engine)
    print(len(df))