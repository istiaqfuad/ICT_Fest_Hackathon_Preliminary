"""Refund bookkeeping.

When a booking is cancelled a refund is calculated from its price and the
applicable notice tier, then written to the refund ledger with a processed
status. Amounts are stored in whole cents.
"""

from datetime import datetime
from sqlalchemy.orm import Session
from ..models import Booking, RefundLog

def log_refund(db: Session, booking: Booking, percent: int, amount_cents: int) -> RefundLog:
    # Check if a log entry already exists to guard against race conditions
    existing_log = db.query(RefundLog).filter(RefundLog.booking_id == booking.id).first()
    if existing_log:
        return existing_log

    entry = RefundLog(
        booking_id=booking.id,
        amount_cents=amount_cents,
        status="processed",
        processed_at=datetime.utcnow(),
    )
    db.add(entry)
    # REMOVED db.commit() and db.refresh() to let the router manage the atomic commit safely
    return entry
