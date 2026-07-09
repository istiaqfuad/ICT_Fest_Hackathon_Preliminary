"""Smoke and regression tests covering core contract behaviors.

Run with ``pytest`` after installing requirements. It exercises a single,
sequential golden path plus a few targeted regressions.
"""
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone

from fastapi.testclient import TestClient

from app.auth import create_access_token, decode_token
from app.main import app
from app.timeutils import parse_input_datetime

client = TestClient(app)


def _future(hours: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).replace(
        minute=0, second=0, microsecond=0
    ).isoformat()


def _org_name(prefix: str = "acme") -> str:
    return f"{prefix}-{datetime.now().timestamp()}"


def _register_and_login(org: str, username: str = "alice") -> dict[str, str]:
    reg = client.post(
        "/auth/register",
        json={"org_name": org, "username": username, "password": "pw12345"},
    )
    assert reg.status_code == 201

    login = client.post(
        "/auth/login",
        json={"org_name": org, "username": username, "password": "pw12345"},
    )
    assert login.status_code == 200
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _create_room(headers: dict[str, str], name: str = "Focus Room") -> int:
    room = client.post(
        "/rooms",
        json={"name": name, "capacity": 4, "hourly_rate_cents": 1000},
        headers=headers,
    )
    assert room.status_code == 201
    return room.json()["id"]


def test_core_flow():
    assert client.get("/health").json() == {"status": "ok"}

    org = _org_name()
    headers = _register_and_login(org)
    room_id = _create_room(headers)

    booking = client.post(
        "/bookings",
        json={"room_id": room_id, "start_time": _future(50), "end_time": _future(52)},
        headers=headers,
    )
    assert booking.status_code == 201
    assert booking.json()["price_cents"] == 2000

    listing = client.get("/bookings", headers=headers)
    assert listing.status_code == 200
    assert listing.json()["total"] >= 1


def test_parse_input_datetime_normalizes_offsets_to_utc():
    parsed = parse_input_datetime("2026-07-10T10:00:00+06:00")
    assert parsed == datetime(2026, 7, 10, 4, 0, 0)


def test_access_tokens_expire_in_exactly_900_seconds():
    token = create_access_token(SimpleNamespace(id=1, org_id=2, role="member"))
    payload = decode_token(token)
    assert payload["exp"] - payload["iat"] == 900


def test_booking_rejects_past_and_non_positive_windows():
    headers = _register_and_login(_org_name("window"))
    room_id = _create_room(headers, "Window Room")

    start = datetime.now(timezone.utc) - timedelta(minutes=1)
    end = start + timedelta(hours=1)
    past = client.post(
        "/bookings",
        json={"room_id": room_id, "start_time": start.isoformat(), "end_time": end.isoformat()},
        headers=headers,
    )
    assert past.status_code == 400
    assert past.json()["code"] == "INVALID_BOOKING_WINDOW"

    start = datetime.now(timezone.utc) + timedelta(hours=2)
    invalid = client.post(
        "/bookings",
        json={
            "room_id": room_id,
            "start_time": start.isoformat(),
            "end_time": start.isoformat(),
        },
        headers=headers,
    )
    assert invalid.status_code == 400
    assert invalid.json()["code"] == "INVALID_BOOKING_WINDOW"


def test_booking_detail_preserves_booking_start_time():
    headers = _register_and_login(_org_name("detail"))
    room_id = _create_room(headers, "Detail Room")
    start = datetime.now(timezone.utc) + timedelta(hours=50)
    end = start + timedelta(hours=2)

    created = client.post(
        "/bookings",
        json={"room_id": room_id, "start_time": start.isoformat(), "end_time": end.isoformat()},
        headers=headers,
    )
    assert created.status_code == 201

    detail = client.get(f"/bookings/{created.json()['id']}", headers=headers)
    assert detail.status_code == 200
    assert detail.json()["start_time"] == created.json()["start_time"]


def test_usage_report_accepts_iso_datetimes_and_returns_utc_bounds():
    headers = _register_and_login(_org_name("report"))
    room_id = _create_room(headers, "Report Room")
    tz = timezone(timedelta(hours=6))
    start_utc = datetime.now(timezone.utc) + timedelta(hours=50)
    end_utc = start_utc + timedelta(hours=2)

    created = client.post(
        "/bookings",
        json={
            "room_id": room_id,
            "start_time": start_utc.astimezone(tz).isoformat(),
            "end_time": end_utc.astimezone(tz).isoformat(),
        },
        headers=headers,
    )
    assert created.status_code == 201

    from_bound = (start_utc - timedelta(hours=1)).astimezone(tz).isoformat()
    to_bound = start_utc.astimezone(tz).isoformat()
    report = client.get(
        "/admin/usage-report",
        params={"from": from_bound, "to": to_bound},
        headers=headers,
    )
    assert report.status_code == 200
    assert report.json()["from"] == parse_input_datetime(from_bound).replace(tzinfo=timezone.utc).isoformat()
    assert report.json()["to"] == parse_input_datetime(to_bound).replace(tzinfo=timezone.utc).isoformat()
    assert report.json()["rooms"][0]["confirmed_bookings"] == 1


def test_cancellation_notice_uses_correct_time_thresholds():
    headers = _register_and_login(_org_name("cancel"))
    room_id = _create_room(headers, "Cancel Room")

    start = datetime.now(timezone.utc) + timedelta(hours=48, minutes=1)
    end = start + timedelta(hours=1)
    booking = client.post(
        "/bookings",
        json={"room_id": room_id, "start_time": start.isoformat(), "end_time": end.isoformat()},
        headers=headers,
    )
    assert booking.status_code == 201

    cancelled = client.post(f"/bookings/{booking.json()['id']}/cancel", headers=headers)
    assert cancelled.status_code == 200
    assert cancelled.json()["refund_percent"] == 100

    start = datetime.now(timezone.utc) + timedelta(hours=23, minutes=59)
    end = start + timedelta(hours=1)
    booking = client.post(
        "/bookings",
        json={"room_id": room_id, "start_time": start.isoformat(), "end_time": end.isoformat()},
        headers=headers,
    )
    assert booking.status_code == 201

    cancelled = client.post(f"/bookings/{booking.json()['id']}/cancel", headers=headers)
    assert cancelled.status_code == 200
    assert cancelled.json()["refund_percent"] == 0
