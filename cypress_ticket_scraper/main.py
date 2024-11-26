import itertools
from datetime import datetime
from enum import Enum
import json

from pytz import timezone
import requests


class Duration(Enum):
    FULL_DAY = 3969
    AFTERNOON = 3970
    NIGHT_OWL = 4203


class Age(Enum):
    ADULT = 3964
    YOUTH = 3965
    CHILD = 3966
    SKOOTER = 3967
    SENIOR = 3968


TZ = timezone("Canada/Pacific")
REQ_DATE_FMT = r"%Y-%m-%dT00:00:00.000Z"
FILE_DATE_FMT = r"%Y-%m-%d_%H-%M-%S"


def nearest_year(dt: datetime) -> datetime:
    midpoint = dt.replace(
        month=7,day=1,
        hour=0, minute=0, second=0,
        microsecond=0
    )
    if dt < midpoint:
        target_year = dt.year
    else:
        target_year = dt.year + 1
    return dt.replace(
        year=target_year, month=1, day=1,
        hour=0, minute=0, second=0,
        microsecond=0
    )


def main():
    now = datetime.now(tz=TZ)
    now_str = datetime.strftime(now, FILE_DATE_FMT)
    today = now.replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    today_str = datetime.strftime(today, REQ_DATE_FMT)

    # Idk Cypress site seems to always use this as the end date
    end_date = nearest_year(today).replace(
        month=10, day=30
    )
    end_date_str = datetime.strftime(end_date, REQ_DATE_FMT)

    print(f"Today is {today_str}")
    for duration, age in itertools.product(Duration, Age):
        print(f"Fetching price data for {duration}, {age}")

        fname = (
            f"{now_str}_cypress_tickets_"
            f"{duration.name}_{age.name}.json"
        )

        request_data = {
            "ProductAttributeValueIds": [
                duration.value,
                age.value
            ],
            "ProductId": 214,
            "StartDate": today_str,
            "EndDate": end_date_str,
        }

        resp = requests.post(
            "https://shop.cypressmountain.com/api/v1/product-variant",
            headers={
                "Content-Type": "application/json",
            },
            data=json.dumps(request_data)
        )
        if resp.ok:
            print(f"Response OK, saving to {fname}")
            with open(fname, "w") as f:
                json.dump(resp.json(), f, indent=2)
        else:
            print(f"Response not OK: {resp.status_code}")
            print(resp.text)
            return



if __name__ == "__main__":
    main()