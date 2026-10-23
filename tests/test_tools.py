from datetime import datetime
from zoneinfo import ZoneInfo
import pytest
from app.graph import get_time

def test_get_time_returns_valid_iso():
    out = get_time.invoke({"tz": "Asia/Kolkata"})
    parsed = datetime.fromisoformat(out)
    assert parsed.tzinfo is not None

def test_get_time_respects_timezone():
    tokyo = datetime.fromisoformat(get_time.invoke({"tz": "Asia/Tokyo"}))
    utc = datetime.fromisoformat(get_time.invoke({"tz": "UTC"}))
    assert tokyo.utcoffset() != utc.utcoffset()

def test_get_time_bad_timezone_raises():
    with pytest.raises(Exception):
        get_time.invoke({"tz": "Not/AZone"})