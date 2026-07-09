"""Administrative reporting and export endpoints."""

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from .. import cache
from ..auth import require_admin
from ..database import get_db
from ..errors import AppError
from ..models import Booking, Room, User
from ..services.export import generate_export
from ..timeutils import iso_utc, parse_input_datetime

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/usage-report")
def usage_report(
    frm: str = Query(..., alias="from"),
    to: str = Query(...),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    try:
        range_start = parse_input_datetime(frm)
        range_end = parse_input_datetime(to)
    except ValueError:
        raise AppError(400, "INVALID_BOOKING_WINDOW", "Invalid date range")
    if range_end < range_start:
        raise AppError(400, "INVALID_BOOKING_WINDOW", "Invalid date range")

    rooms = db.query(Room).filter(Room.org_id == admin.org_id).order_by(Room.id.asc()).all()
    room_rows = []
    for room in rooms:
        bookings = (
            db.query(Booking)
            .filter(
                Booking.room_id == room.id,
                Booking.status == "confirmed",
                Booking.start_time >= range_start,
                Booking.start_time <= range_end,
            )
            .all()
        )
        room_rows.append(
            {
                "room_id": room.id,
                "room_name": room.name,
                "confirmed_bookings": len(bookings),
                "revenue_cents": sum(b.price_cents for b in bookings),
            }
        )

    result = {"from": iso_utc(range_start), "to": iso_utc(range_end), "rooms": room_rows}
    return result
@router.get("/export")
def export(
    room_id: int | None = Query(None),
    include_all: bool = Query(False),
    db: Session = Depends(get_db),
    admin: User = Depends(require_admin),
):
    # If a room was requested, ensure it belongs to the admin's organization.
    if room_id is not None:
        room = (
            db.query(Room)
            .filter(
                Room.id == room_id,
                Room.org_id == admin.org_id,
            )
            .first()
        )

        # Business Rule #9:
        # Cross-org resources must behave as non-existent.
        if room is None:
            raise AppError(
                404,
                "ROOM_NOT_FOUND",
                "Room not found",
            )

    csv_body = generate_export(
        db,
        admin.org_id,
        admin.id,
        room_id,
        include_all,
    )

    return Response(
        content=csv_body,
        media_type="text/csv",
    )