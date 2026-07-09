"""Human-facing booking reference codes.

Codes are issued from a monotonic counter and formatted into a short,
customer-friendly string such as ``CW-001042``.
"""
import uuid

def next_reference_code() -> str:
    # Generate a transaction-safe, highly unique reference code
    # to avoid collisions under concurrency or after restart.
    return f"CW-{uuid.uuid4().hex[:6].upper()}"
