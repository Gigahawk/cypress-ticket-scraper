from datetime import datetime
from cypress_ticket_scraper.util import season_year
from cypress_ticket_scraper.main import TZ

def test_season_year():
    expected_season = datetime(2025, 1, 1, tzinfo=TZ)
    # Before season
    dt = datetime(2024, 8, 1, tzinfo=TZ)
    try:
        resp = season_year(dt)
        raise AssertionError(
            f"{dt} should not be before season, but got back {resp}"
        )
    except ValueError:
        pass

    # During season previous year
    dt = datetime(2024, 11, 1, tzinfo=TZ)
    resp = season_year(dt)
    assert resp == expected_season

    # During season same year
    dt = datetime(2025, 2, 1, tzinfo=TZ)
    resp = season_year(dt)
    assert resp == expected_season

    # After season
    dt = datetime(2025, 6, 1, tzinfo=TZ)
    try:
        resp = season_year(dt)
        raise AssertionError(
            f"{dt} should not be after season, but got back {resp}"
        )
    except ValueError:
        pass
