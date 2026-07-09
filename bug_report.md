# Bug Report

This report is based on the API contract in `ICT_Fest_Hackathon_Preliminary.md` and a code review of the current repository. The entries below describe the bug, why it violates the contract, and the intended fix.

## 1\. Timezone offsets are stripped instead of converted to UTC

- Status: Fixed  
- Files/lines: `app/timeutils.py:11-14`  
- Bug: `parse_input_datetime()` calls `dt.replace(tzinfo=None)` for aware datetimes. This drops the offset without changing the clock time.  
- Impact: `2026-07-10T10:00:00+06:00` is stored as `2026-07-10 10:00:00` instead of `2026-07-10 04:00:00` UTC. Booking conflict checks, quotas, reports, availability, and responses can all be wrong.  
- Fix: For aware datetimes, convert with `dt.astimezone(timezone.utc).replace(tzinfo=None)`. Keep naive inputs as UTC.

## 2\. Booking start time allows a 5-minute past grace window

- Status: Fixed  
- Files/lines: `app/routers/bookings.py:84-87`  
- Bug: The code rejects only `start <= now - 5 minutes`.  
- Impact: The contract requires `start_time` to be strictly in the future at request time, with no grace window. A booking that started moments ago is incorrectly accepted.  
- Fix: Reject `start <= now`.

## 3\. Booking duration validation misses zero and negative durations

- Status: Fixed  
- Files/lines: `app/routers/bookings.py:89-94`  
- Bug: The code checks for whole hours and `> 8`, but never checks `end_time > start_time` or minimum duration `>= 1`.  
- Impact: Zero-hour or negative-duration bookings can be accepted, producing zero or negative prices.  
- Fix: Reject `end <= start`, then require `1 <= duration_hours <= 8`.

## 4\. Back-to-back bookings are treated as conflicts

- Files/lines: `app/routers/bookings.py:42-51`  
- Bug: `_has_conflict()` uses `b.start_time <= end and start <= b.end_time`.  
- Impact: A booking ending at 11:00 blocks a new booking starting at 11:00, but the contract explicitly allows back-to-back bookings.  
- Fix: Use the strict overlap predicate from the spec: `existing.start_time < new_end and new_start < existing.end_time`.

## 5\. Double-booking protection is not concurrency-safe

- Files/lines: `app/routers/bookings.py:42-52`, `app/routers/bookings.py:100-118`, `app/models.py:46-57`  
- Bug: Conflict detection is a read-before-write check with no transaction-level serialization or database constraint. The sleep in `_pricing_warmup()` widens the race window.  
- Impact: Concurrent requests can both see no conflict and commit overlapping confirmed bookings for the same room.  
- Fix: Serialize booking creation per room/time range, or enforce the invariant inside a transaction with an application lock suitable for SQLite. Keep the conflict check and insert atomic.

## 6\. Quota enforcement is not concurrency-safe

- Files/lines: `app/routers/bookings.py:55-71`, `app/routers/bookings.py:103-118`  
- Bug: Quota is counted before insert without any lock or transaction protection. `_quota_audit()` widens the race window.  
- Impact: Concurrent requests can all see fewer than 3 bookings and create more than 3 confirmed bookings in the next 24 hours.  
- Fix: Perform quota check and booking insert under the same per-user critical section or transaction.

## 7\. Rate limiter is not concurrency-safe

- Status: Fixed
- Files/lines: `app/services/ratelimit.py:9-26`  
- Bug: `_buckets` is a shared dict/list updated without locking. Concurrent calls can read the same old bucket and overwrite each other.  
- Impact: More than 20 concurrent `POST /bookings` requests in 60 seconds can be accepted.  
- Fix: Guard bucket read/trim/append/write with a lock, or use an atomic shared rate limiter.

## 8\. Reference codes are not unique under concurrency or restart

- Files/lines: `app/services/reference.py:8-21`, `app/models.py:55`  
- Bug: `next_reference_code()` reads and writes a process-local counter without locking, and `Booking.reference_code` has no unique constraint.  
- Impact: Concurrent bookings can receive the same reference code. After a process restart, the counter resets to `CW-001000`, which can duplicate existing rows.  
- Fix: Add a uniqueness guarantee at the database level and generate references from a transaction-safe source, retrying on collision.

## 9\. Room stats are process-local and can drift from the database

- Status: Fixed  
- Files/lines: `app/services/stats.py:8-30`, `app/routers/rooms.py:103-115`  
- Bug: `/rooms/{id}/stats` reads from an in-memory counter instead of aggregating confirmed bookings from the database.  
- Impact: Stats are wrong after app restart, after existing data is loaded, after failed partial side effects, and after concurrent bursts that lose updates in `_stats`.  
- Fix: Compute stats from `Booking` rows on each request, or maintain counters transactionally and concurrency-safely in the database.

## 10\. Usage-report cache is stale after booking creation

- Files/lines: `app/routers/bookings.py:120-122`, `app/routers/admin.py:25-27`, `app/cache.py:12-22`  
- Bug: Creating a booking invalidates availability cache but not usage-report cache.  
- Impact: `GET /admin/usage-report` may return a stale result immediately after a booking is created, violating the "current state immediately" rule.  
- Fix: Invalidate the organization's report cache after successful booking creation.

## 11\. Availability cache is stale after cancellation

- Files/lines: `app/routers/bookings.py:216-218`, `app/routers/rooms.py:69-100`, `app/cache.py:25-34`  
- Bug: Cancelling a booking invalidates report cache but not availability cache.  
- Impact: `GET /rooms/{id}/availability` can continue showing a cancelled booking as busy.  
- Fix: Invalidate availability for the cancelled booking's room and start date after cancellation.

## 12\. Usage report accepts dates only, not ISO 8601 datetimes

- Status: Fixed  
- Files/lines: `app/routers/admin.py:29-36`  
- Bug: `from` and `to` are parsed with `"%Y-%m-%d"` and expanded to whole days.  
- Impact: The contract says API datetimes are ISO 8601 and usage reports count bookings starting in `[from, to]` UTC inclusive. Datetime inputs with time or offset are rejected or interpreted incorrectly.  
- Fix: Parse `from` and `to` with the same UTC-normalizing datetime helper used for bookings, and query `start_time >= from_dt` and `start_time <= to_dt`.

## 13\. Booking list pagination and ordering are wrong

- Files/lines: `app/routers/bookings.py:134-140`  
- Bug: Results are sorted by `start_time.desc()` instead of ascending. The offset is `page * limit` instead of `(page - 1) * limit`. The query always applies `.limit(10)` instead of the requested `limit`.  
- Impact: Page 1 skips the first `limit` bookings, ordering is reversed, and non-default limits do not work. Sequential pages can skip items.  
- Fix: Use ascending order, `offset((page - 1) * limit)`, and `.limit(limit)`.

## 14\. Members can read other members' bookings in the same org

- Status: Fixed  
- Files/lines: `app/routers/bookings.py:156-175`  
- Bug: `GET /bookings/{id}` filters by organization only. It does not enforce owner visibility for non-admin users.  
- Impact: Any member can read another member's booking and refund details if they know the booking id. The contract requires `404 BOOKING_NOT_FOUND`.  
- Fix: After loading the org-scoped booking, return `404 BOOKING_NOT_FOUND` when `user.role != "admin"` and `booking.user_id != user.id`.

## 15\. Booking detail returns the wrong `start_time`

- Status: Fixed  
- Files/lines: `app/routers/bookings.py:165-167`  
- Bug: The response is serialized correctly, then `response["start_time"]` is overwritten with `booking.created_at`.  
- Impact: `GET /bookings/{id}` reports the booking creation time as the booking start time.  
- Fix: Remove the overwrite and keep `serialize_booking()`'s `start_time`.

## 16\. Duplicate registration returns success instead of `409 USERNAME_TAKEN`

	–**fixed**

- Files/lines: `app/routers/auth.py:32-43`  
- Bug: If a username already exists in the organization, the existing user is returned with `201`.  
- Impact: The contract requires duplicate usernames within an org to return `409 USERNAME_TAKEN`.  
- Fix: Raise `AppError(409, "USERNAME_TAKEN", ...)` when the existing user is found.

## 17\. Registration can crash on concurrent duplicate org/user creation

- Files/lines: `app/routers/auth.py:24-53`, `app/models.py:20-26`  
- Bug: Registration checks for existing org/user before insert, but does not handle `IntegrityError` from concurrent inserts into unique constraints.  
- Impact: Concurrent registration for the same org or same org+username can produce a 500 instead of the required admin/member creation or `409 USERNAME_TAKEN`.  
- Fix: Catch unique-constraint failures, roll back, reload the org/user, and return the contract response/error.

## 18\. Access tokens expire after 900 minutes, not 900 seconds

- Status: Fixed  
- Files/lines: `app/auth.py:48-58`, `app/config.py:11`  
- Bug: `ACCESS_TOKEN_EXPIRE_MINUTES` is 15, but `create_access_token()` uses `timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES * 60)`.  
- Impact: Access token lifetime is 54,000 seconds instead of exactly 900 seconds.  
- Fix: Use `timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)` or set `exp = iat + 900`.

## 19\. Logout does not invalidate the presented access token

	–**fixed**

- Files/lines: `app/auth.py:85-98`, `app/routers/auth.py:96-99`  
- Bug: `revoke_access_token()` stores the token `jti`, but `get_token_payload()` checks whether `sub` is in `_revoked_tokens`.  
- Impact: The logged-out access token continues to work.  
- Fix: Check `payload["jti"]` against the revoked-token set.

## 20\. Refresh tokens are reusable

	—-**fixed**

- Files/lines: `app/routers/auth.py:81-93`, `app/auth.py:63-82`  
- Bug: `/auth/refresh` validates token type but never records refresh-token `jti` usage or revocation.  
- Impact: The same refresh token can be reused indefinitely until expiration, violating the single-use refresh-token rule.  
- Fix: Store used refresh-token JTIs and reject reuse with `401`. Record the presented refresh JTI before returning rotated tokens.

## 21\. Cancellation refund policy has incorrect thresholds

- Status: Fixed  
- Files/lines: `app/routers/bookings.py:198-206`  
- Bug: The 100% branch uses `notice_hours > 48`, based on floored hours, instead of `notice >= 48 hours`. The `< 24 hours` branch returns 50% instead of 0%.  
- Impact: A cancellation exactly 48 hours before start, or 48 hours plus minutes, receives 50% instead of 100%. A cancellation under 24 hours receives 50% instead of 0%.  
- Fix: Compare `notice` directly against `timedelta(hours=48)` and `timedelta(hours=24)`, returning 100, 50, or 0\.

## 22\. Refund amount rounding is wrong and response can disagree with ledger

**—-----------------------FIXED**

- Files/lines: `app/routers/bookings.py:208-210`, `app/services/refunds.py:14-27`  
- Bug: The response uses Python `round()`, which is bankers rounding, while `log_refund()` truncates via `int(refund_dollars * 100)`. The contract requires nearest cent with half-cents rounding up, and the response amount must equal the stored `RefundLog`.  
- Impact: For odd-cent 50% refunds, the returned amount can be wrong, and for some values it can differ from the ledger.  
- Fix: Calculate the refund amount once using integer arithmetic or `Decimal(..., ROUND_HALF_UP)`, pass that exact amount into `RefundLog`, and return the same value.

## 23\. Cancellation is not concurrency-safe and can create multiple refunds

**—------------FIXED**

- Files/lines: `app/routers/bookings.py:195-214`, `app/services/refunds.py:24-25`, `app/models.py:62-69`  
- Bug: The cancellation path checks status, commits a `RefundLog`, sleeps, then marks the booking cancelled. There is no lock and no unique constraint on `refund_logs.booking_id`.  
- Impact: Concurrent cancellation requests can both see `confirmed`, both write refund logs, and both return success. The contract requires exactly one refund log and `409 ALREADY_CANCELLED` for subsequent cancellation.  
- Fix: Make status transition and refund creation atomic under a per-booking lock or transaction, and add a unique constraint on `RefundLog.booking_id`.

## 24\. Cancellation can leave a refund log for a still-confirmed booking

**—--------------FIXED**

- Files/lines: `app/services/refunds.py:24-25`, `app/routers/bookings.py:210-214`  
- Bug: `log_refund()` commits the refund before the booking status update is committed.  
- Impact: If the process fails between those commits, the database can contain a processed refund for a confirmed booking.  
- Fix: Add the refund and update booking status in one transaction, committing once.

## 25\. Export can leak cross-org bookings when `include_all=true&room_id=...`

- Files/lines: `app/services/export.py:22-29`, `app/services/export.py:48-52`, `app/routers/admin.py:65-73`  
- Bug: `include_all=True` with a `room_id` calls `fetch_bookings_raw()`, which filters only by `Booking.room_id` and does not join/filter by organization.  
- Impact: An admin can export another organization's room bookings by guessing a room id.  
- Fix: Always scope export queries by `Room.org_id == admin.org_id`; return `404` for cross-org room ids if the endpoint treats `room_id` as a resource id.

## 26\. Export CSV header does not match the exact contract

- Files/lines: `app/services/export.py:10-19`  
- Bug: The header uses underscore field names such as `reference_code` and `room_id`.  
- Impact: The contract specifies the exact CSV header as `id,reference code,room id,user id,start time,end time,status,price cents`.  
- Fix: Change `EXPORT_HEADER` to the exact required labels while preserving row values.

## 27\. Notification locks can deadlock the service

- Status: Fixed
- Files/lines: `app/services/notifications.py:24-35`  
- Bug: `notify_created()` acquires `_email_lock` then `_audit_lock`; `notify_cancelled()` acquires `_audit_lock` then `_email_lock`.  
- Impact: A concurrent create and cancel can each hold one lock and wait forever for the other. The liveness rule says no valid concurrent request combination may hang the service.  
- Fix: Acquire locks in one consistent order, or use a single lock for the combined simulated side effect.

## 28\. In-memory auth/rate/cache/stat state is not process-safe

- Files/lines: `app/auth.py:24`, `app/services/ratelimit.py:9`, `app/cache.py:8-9`, `app/services/stats.py:8`  
- Bug: Revoked tokens, rate-limit buckets, caches, and stats are kept in per-process dictionaries/sets.  
- Impact: With multiple workers or restarts, logout revocations disappear, refresh/rate behavior is inconsistent, stale caches survive within a worker only, and stats diverge from the database. Several contract rules require immediate and consistent behavior.  
- Fix: Store security-critical and consistency-critical state in the database or another shared atomic store. For this SQLite-only challenge, prefer database-backed checks or request-time aggregation where possible.

## 29\. Room name uniqueness within an organization is not enforced

- Status: Fixed  
- Files/lines: `app/models.py:36-43`, `app/routers/rooms.py:42-57`  
- Bug: The `Room` model has no `UniqueConstraint("org_id", "name")`, and `create_room()` does not check whether a room with the same name already exists in the org before inserting.  
- Impact: The contract (Rule 1\) requires room names to be unique within an org. Without enforcement, multiple rooms with identical names can be created, causing ambiguity in reports, exports, and availability lookups.  
- Fix: Add `__table_args__ = (UniqueConstraint("org_id", "name", name="uq_room_org_name"),)` to the `Room` model. Optionally add an application-level check before insert and return an appropriate error on conflict.

## 30\. Room capacity and hourly rate validation is missing

- Status: Fixed  
- Files/lines: `app/schemas.py:21-24`, `app/routers/rooms.py:42-57`  
- Bug: `RoomCreateRequest` accepts any integer for `capacity` and `hourly_rate_cents` with no minimum-value constraints. The router also performs no validation.  
- Impact: The contract (Rule 1\) requires `capacity >= 1` and `hourly_rate_cents >= 0`. Without validation, rooms can be created with zero or negative capacity, or negative hourly rates, producing nonsensical bookings and prices.  
- Fix: Add `capacity: int = Field(ge=1)` and `hourly_rate_cents: int = Field(ge=0)` in `RoomCreateRequest`.

## 31\. Response datetimes use `+00:00` instead of `Z` UTC designator

- Status: Fixed
- Files/lines: `app/timeutils.py:17-19`  
- Bug: `iso_utc()` uses `dt.replace(tzinfo=timezone.utc).isoformat()`, which produces datetimes like `2026-07-10T04:00:00+00:00`. The contract says all response datetimes must use an explicit UTC designator, and the canonical ISO 8601 UTC designator is `Z`.  
- Impact: If the grader performs exact string matching against `Z`\-suffixed datetimes, all datetime fields in every response will fail comparison.  
- Fix: Use `dt.isoformat() + "Z"` instead of attaching `timezone.utc` and relying on Python's `+00:00` formatting.

22, 23, 24 needs review—------Anan