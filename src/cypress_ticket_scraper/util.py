from datetime import datetime



def season_year(dt: datetime) -> datetime:
    season_end = dt.replace(
        month=5, day=1,
        hour=0, minute=0, second=0,
        microsecond=0
    )
    season_start = dt.replace(
        month=11, day=1,
        hour=0, minute=0, second=0,
        microsecond=0
    )

    if season_end < dt < season_start:
        raise ValueError(
            f"{dt} is not within a ski season"
        )
    if season_start <= dt:
        target_year = dt.year + 1
    elif dt <= season_end:
        target_year = dt.year
    else:
        raise Exception(
            f"Unknown error for date {dt}"
        )
    return dt.replace(
        year=target_year, month=1, day=1,
        hour=0, minute=0, second=0,
        microsecond=0
    )
