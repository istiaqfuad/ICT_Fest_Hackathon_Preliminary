"""CSV export of bookings for administrators."""
import csv
import io

from sqlalchemy.orm import Session

from ..models import Booking, Room
from ..timeutils import iso_utc

# Remove underscrore to match specification
EXPORT_HEADER = [
    "id",
    "reference code",
    "room id",
    "user id",
    "start time",
    "end time",
    "status",
    "price cents",
]


def fetch_bookings_raw(
    db: Session,
    org_id: int,
    room_id: int,
) -> list[Booking]:
    """
    Load every booking for a room that belongs to the
    administrator's organization. By filtering Org id and Booking room Id
    """
    return (
        db.query(Booking)
        .join(Room)
        .filter(
            Booking.room_id == room_id,
            Room.org_id == org_id,
        )
        .order_by(Booking.id.asc())
        .all()
    )

def _fetch_scoped(db: Session, org_id: int, user_id: int | None, room_id: int | None) -> list[Booking]:
    query = db.query(Booking).join(Room).filter(Room.org_id == org_id)
    if user_id is not None:
        query = query.filter(Booking.user_id == user_id)
    if room_id is not None:
        query = query.filter(Booking.room_id == room_id)
    return query.order_by(Booking.id.asc()).all()


def generate_export(
    db: Session,
    org_id: int,
    user_id: int,
    room_id: int | None,
    include_all: bool,
) -> str:
    """
    Generate a CSV export of bookings.

    - include_all=True  -> export all bookings within the admin's organization.
    - include_all=False -> export only the requesting user's bookings.
    - room_id (optional) further restricts the export to a specific room.
    """

    if include_all:
        if room_id is not None:
            # FIX:
            # Scope the export by organization as well to prevent
            # cross-organization data leakage.
            rows = fetch_bookings_raw(db, org_id, room_id)
        else:
            rows = _fetch_scoped(db, org_id, None, None)
    else:
        rows = _fetch_scoped(db, org_id, user_id, room_id)

    buffer = io.StringIO()
    writer = csv.writer(buffer)

    writer.writerow(EXPORT_HEADER)

    for b in rows:
        writer.writerow(
            [
                b.id,
                b.reference_code,
                b.room_id,
                b.user_id,
                iso_utc(b.start_time),
                iso_utc(b.end_time),
                b.status,
                b.price_cents,
            ]
        )

    return buffer.getvalue()
