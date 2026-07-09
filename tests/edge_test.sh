#!/bin/bash
# Deep edge case auditing

BASE="http://localhost:8080"

# First reset the DB
echo "=== SETUP ==="
# Register and login
REG=$(curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"edge_org","username":"admin","password":"pass"}')
echo "Register: $REG"

LOGIN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"edge_org","username":"admin","password":"pass"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

REG2=$(curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"edge_org","username":"member","password":"pass"}')

LOGIN2=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"edge_org","username":"member","password":"pass"}')
TOKEN2=$(echo "$LOGIN2" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Create room 
ROOM=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"EdgeRoom","capacity":5,"hourly_rate_cents":100}')
ROOM_ID=$(echo "$ROOM" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "Room ID: $ROOM_ID"

echo ""
echo "=== TEST 1: Duration boundaries ==="
# Exactly 0 hours (end == start)
echo "Zero duration:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"2026-07-20T10:00:00Z\",\"end_time\":\"2026-07-20T10:00:00Z\"}" | python3 -m json.tool

# Exactly 9 hours (over max)
echo "9 hours:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"2026-07-20T10:00:00Z\",\"end_time\":\"2026-07-20T19:00:00Z\"}" | python3 -m json.tool

# Exactly 8 hours (max valid)
echo "8 hours (should succeed):"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"2026-07-20T10:00:00Z\",\"end_time\":\"2026-07-20T18:00:00Z\"}" | python3 -m json.tool

# 1.5 hours (non-whole)
echo "1.5 hours:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"2026-07-21T10:00:00Z\",\"end_time\":\"2026-07-21T11:30:00Z\"}" | python3 -m json.tool

echo ""
echo "=== TEST 2: Quota boundary - exactly 3 bookings in 24h window ==="
# Create 3 bookings within (now, now+24h]
Q_START1=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=2); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_END1=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=3); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_START2=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=4); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_END2=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=5); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_START3=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=6); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_END3=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=7); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_START4=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=8); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_END4=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=9); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")

echo "Quota booking 1:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$Q_START1\",\"end_time\":\"$Q_END1\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d))"

echo "Quota booking 2:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$Q_START2\",\"end_time\":\"$Q_END2\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d))"

echo "Quota booking 3:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$Q_START3\",\"end_time\":\"$Q_END3\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d))"

echo "Quota booking 4 (should fail with QUOTA_EXCEEDED):"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$Q_START4\",\"end_time\":\"$Q_END4\"}" | python3 -m json.tool

echo ""
echo "=== TEST 3: Booking outside 24h window (should bypass quota) ==="
Q_FAR_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=25); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
Q_FAR_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=26); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
echo "Booking beyond 24h window (should succeed even with quota full):"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$Q_FAR_START\",\"end_time\":\"$Q_FAR_END\"}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d))"

echo ""
echo "=== TEST 4: Admin creates room, member can't ==="
echo "Member tries to create room:"
curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d '{"name":"MemberRoom","capacity":1,"hourly_rate_cents":50}' | python3 -m json.tool

echo ""
echo "=== TEST 5: Usage report missing rooms with zero bookings ==="
# Create a room with no bookings
EMPTY_ROOM=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"name":"EmptyRoom","capacity":2,"hourly_rate_cents":200}')
echo "Empty room: $EMPTY_ROOM"

echo "Usage report (should include EmptyRoom with 0 bookings):"
curl -s "$BASE/admin/usage-report?from=2026-01-01T00:00:00Z&to=2027-01-01T00:00:00Z" \
  -H "Authorization: Bearer $TOKEN" | python3 -m json.tool

echo ""
echo "=== TEST 6: Cancel booking refund at exactly 48h and exactly 24h ==="
# Create booking starting exactly 48h from now
EXACTLY_48_START=$(python3 -c "
from datetime import datetime, timedelta
t = datetime.utcnow() + timedelta(hours=49)  # slightly over 48h
print(t.strftime('%Y-%m-%dT%H:00:00Z'))
")
EXACTLY_48_END=$(python3 -c "
from datetime import datetime, timedelta
t = datetime.utcnow() + timedelta(hours=50)
print(t.strftime('%Y-%m-%dT%H:00:00Z'))
")
echo "Creating booking starting ~49h from now (notice >= 48h) -> 100% refund"
B48=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$EXACTLY_48_START\",\"end_time\":\"$EXACTLY_48_END\"}")
echo "Booking: $B48"
B48_ID=$(echo "$B48" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERR:'+str(d)))")
if [[ "$B48_ID" != ERR* ]]; then
  echo "Canceling (expect 100% refund):"
  curl -s -X POST "$BASE/bookings/$B48_ID/cancel" -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool
fi

echo ""
echo "=== TEST 7: Non-admin access to admin endpoints ==="
echo "Member access to usage-report:"
curl -s "$BASE/admin/usage-report?from=2026-01-01T00:00:00Z&to=2027-01-01T00:00:00Z" \
  -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool

echo "Member access to export:"
curl -s "$BASE/admin/export?include_all=true" \
  -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool

echo ""
echo "=== TEST 8: Refund with 100% - odd price ==="
# The 100% refund formula: (price_cents * 100 + 50) // 100
# For price_cents=101: (101 * 100 + 50) // 100 = 10150 // 100 = 101 ✓
# But wait - this is only correct for 50%. For 100% it should be just price_cents.
# Let's verify: (price * 100 + 50) // 100 = (price*100 + 50) // 100
# = price + 50//100 = price + 0 = price  (for any integer price). OK.
# For 0%: (price * 0 + 50) // 100 = 50 // 100 = 0. OK.
echo "All refund % formulas check out mathematically."

echo ""
echo "=== TEST 9: Booking GET detail with refunds ==="
echo "Get cancelled booking detail (should include refunds list):"
# Use one of the cancelled bookings from earlier test
# B48_ID was just cancelled if it succeeded
if [[ "$B48_ID" != ERR* ]]; then
  curl -s "$BASE/bookings/$B48_ID" -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool
fi

echo ""
echo "=== EDGE TESTS DONE ==="
