#!/bin/bash
BASE="http://localhost:8080"

echo "=== 1. REGISTER & LOGIN ==="
# Register first user (should be admin)
REG1=$(curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"pass123"}')
echo "Register admin1: $REG1"

# Register second user (should be member)
REG2=$(curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"member1","password":"pass123"}')
echo "Register member1: $REG2"

# Register user in different org
REG3=$(curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"other_org","username":"admin2","password":"pass123"}')
echo "Register admin2 (other_org): $REG3"

# Login admin1
LOGIN1=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"pass123"}')
echo "Login admin1: $LOGIN1"
TOKEN1=$(echo "$LOGIN1" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")
REFRESH1=$(echo "$LOGIN1" | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")

# Login member1
LOGIN2=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"member1","password":"pass123"}')
TOKEN2=$(echo "$LOGIN2" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Login admin2
LOGIN3=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"other_org","username":"admin2","password":"pass123"}')
TOKEN3=$(echo "$LOGIN3" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo ""
echo "=== 2. ROOM MANAGEMENT ==="
# Create room 
ROOM1=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN1" \
  -d '{"name":"Room A","capacity":10,"hourly_rate_cents":1000}')
echo "Create Room A: $ROOM1"
ROOM_ID=$(echo "$ROOM1" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Create room in other org
ROOM2=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN3" \
  -d '{"name":"Room B","capacity":5,"hourly_rate_cents":2000}')
echo "Create Room B (other_org): $ROOM2"
ROOM_ID2=$(echo "$ROOM2" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo ""
echo "=== 3. BOOKING CREATION ==="
# Create a booking for 2 hours tomorrow
START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=1); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=1,hours=2); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
echo "Booking start=$START end=$END"

BOOK1=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$START\",\"end_time\":\"$END\"}")
echo "Create booking: $BOOK1"
BOOK_ID=$(echo "$BOOK1" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo ""
echo "=== 4. MULTI-TENANCY TEST ==="
# Try to access room from other org
echo "Try cross-org room access:"
curl -s "$BASE/rooms/$ROOM_ID/availability?date=2026-07-10" \
  -H "Authorization: Bearer $TOKEN3" | python3 -m json.tool

# Try to access booking from other org
echo "Try cross-org booking access:"
curl -s "$BASE/bookings/$BOOK_ID" \
  -H "Authorization: Bearer $TOKEN3" | python3 -m json.tool

echo ""
echo "=== 5. BOOKING VISIBILITY ==="
# Member trying to view admin's booking should get 404
echo "Member1 tries to see admin-created bookings:"
# Create a booking as admin
ADMIN_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=2); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
ADMIN_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=2,hours=1); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
ADMIN_BOOK=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN1" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$ADMIN_START\",\"end_time\":\"$ADMIN_END\"}")
echo "Admin booking: $ADMIN_BOOK"
ADMIN_BOOK_ID=$(echo "$ADMIN_BOOK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Member tries to access admin's booking
echo "Member tries admin booking:"
curl -s "$BASE/bookings/$ADMIN_BOOK_ID" -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool

echo ""
echo "=== 6. PAGINATION TEST ==="
echo "GET /bookings (member1, page=1, limit=1):"
curl -s "$BASE/bookings?page=1&limit=1" -H "Authorization: Bearer $TOKEN2" | python3 -m json.tool

echo ""
echo "=== 7. REFUND CALCULATION TEST ==="
# Create a booking far in the future (>48h notice) then cancel
FAR_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=5); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
FAR_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=5,hours=3); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
FAR_BOOK=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$FAR_START\",\"end_time\":\"$FAR_END\"}")
echo "Far future booking: $FAR_BOOK"
FAR_BOOK_ID=$(echo "$FAR_BOOK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "Price: $(echo $FAR_BOOK | python3 -c "import sys,json; print(json.load(sys.stdin)['price_cents'])")"

# Cancel it (should be 100% refund)
CANCEL=$(curl -s -X POST "$BASE/bookings/$FAR_BOOK_ID/cancel" \
  -H "Authorization: Bearer $TOKEN2")
echo "Cancel far booking: $CANCEL"

# Try double cancel
DOUBLE_CANCEL=$(curl -s -X POST "$BASE/bookings/$FAR_BOOK_ID/cancel" \
  -H "Authorization: Bearer $TOKEN2")
echo "Double cancel: $DOUBLE_CANCEL"

echo ""
echo "=== 8. REFUND WITH ODD CENTS ==="
# Create room with odd hourly rate
ODD_ROOM=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN1" \
  -d '{"name":"Room Odd","capacity":5,"hourly_rate_cents":1001}')
echo "Odd room: $ODD_ROOM"
ODD_ROOM_ID=$(echo "$ODD_ROOM" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Create a 1-hour booking (price = 1001 cents)
ODD_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=6); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
ODD_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=6,hours=1); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
ODD_BOOK=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ODD_ROOM_ID,\"start_time\":\"$ODD_START\",\"end_time\":\"$ODD_END\"}")
echo "Odd booking: $ODD_BOOK"
ODD_BOOK_ID=$(echo "$ODD_BOOK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

# Cancel with 50% refund (between 24h and 48h notice)
# price_cents=1001, 50% = 500.5, should round to 501
# We need to create one with 24-48h notice
NEAR_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=36); print(t.strftime('%Y-%m-%dT') + '{:02d}:00:00Z'.format(t.hour))")
NEAR_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(hours=37); print(t.strftime('%Y-%m-%dT') + '{:02d}:00:00Z'.format(t.hour))")

ODD_BOOK2=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ODD_ROOM_ID,\"start_time\":\"$NEAR_START\",\"end_time\":\"$NEAR_END\"}")
echo "Odd 36h-ahead booking: $ODD_BOOK2"
ODD_BOOK2_ID=$(echo "$ODD_BOOK2" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id','ERROR: '+str(d)))")

if [ "$ODD_BOOK2_ID" != "" ] && [[ ! "$ODD_BOOK2_ID" == ERROR* ]]; then
  ODD_CANCEL=$(curl -s -X POST "$BASE/bookings/$ODD_BOOK2_ID/cancel" \
    -H "Authorization: Bearer $TOKEN2")
  echo "Cancel odd 36h booking: $ODD_CANCEL"
  echo "Expected refund_amount_cents: 501 (1001 * 50 / 100 = 500.5, rounds up)"
fi

echo ""
echo "=== 9. USAGE REPORT ==="
curl -s "$BASE/admin/usage-report?from=2026-01-01T00:00:00Z&to=2027-01-01T00:00:00Z" \
  -H "Authorization: Bearer $TOKEN1" | python3 -m json.tool

echo ""
echo "=== 10. ROOM STATS ==="
curl -s "$BASE/rooms/$ROOM_ID/stats" -H "Authorization: Bearer $TOKEN1" | python3 -m json.tool

echo ""
echo "=== 11. AVAILABILITY ==="
DATE=$(python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow()+timedelta(days=1)).strftime('%Y-%m-%d'))")
curl -s "$BASE/rooms/$ROOM_ID/availability?date=$DATE" \
  -H "Authorization: Bearer $TOKEN1" | python3 -m json.tool

echo ""
echo "=== 12. EXPORT CSV ==="
curl -s "$BASE/admin/export?include_all=true" \
  -H "Authorization: Bearer $TOKEN1"

echo ""
echo "=== 13. REFRESH TOKEN TEST ==="
# Use refresh token once
REFRESH_RES=$(curl -s -X POST "$BASE/auth/refresh" -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH1\"}")
echo "Refresh result: $REFRESH_RES"

# Try to reuse same refresh token
REFRESH_RES2=$(curl -s -X POST "$BASE/auth/refresh" -H "Content-Type: application/json" \
  -d "{\"refresh_token\":\"$REFRESH1\"}")
echo "Refresh reuse result: $REFRESH_RES2"

echo ""
echo "=== 14. LOGOUT TEST ==="
# Get a new token for logout test
NEW_LOGIN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"pass123"}')
NEW_TOKEN=$(echo "$NEW_LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Logout
curl -s -X POST "$BASE/auth/logout" -H "Authorization: Bearer $NEW_TOKEN" | python3 -m json.tool

# Try to use logged-out token
echo "Use logged-out token:"
curl -s "$BASE/rooms" -H "Authorization: Bearer $NEW_TOKEN" | python3 -m json.tool

echo ""
echo "=== 15. PAST BOOKING TEST ==="
# Try to book in the past
PAST=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()-timedelta(hours=2); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
PAST_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()-timedelta(hours=1); print(t.strftime('%Y-%m-%dT%H:00:00Z'))")
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$PAST\",\"end_time\":\"$PAST_END\"}" | python3 -m json.tool

echo ""
echo "=== 16. TIMEZONE HANDLING ==="
# Book with timezone offset
TZ_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=3); print(t.strftime('%Y-%m-%dT%H:00:00+06:00'))")
TZ_END=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=3,hours=1); print(t.strftime('%Y-%m-%dT%H:00:00+06:00'))")
echo "TZ booking start=$TZ_START end=$TZ_END"
TZ_BOOK=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$TZ_START\",\"end_time\":\"$TZ_END\"}")
echo "TZ Booking: $TZ_BOOK"

echo ""
echo "=== 17. ADMIN CANCEL MEMBER BOOKING ==="
# Admin cancels member's booking
echo "Admin cancels member booking $BOOK_ID:"
curl -s -X POST "$BASE/bookings/$BOOK_ID/cancel" \
  -H "Authorization: Bearer $TOKEN1" | python3 -m json.tool

echo ""
echo "=== 18. BACK-TO-BACK BOOKING ==="
# Create two back-to-back bookings
BB_START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=7); print(t.strftime('%Y-%m-%dT10:00:00Z'))")
BB_END="$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=7); print(t.strftime('%Y-%m-%dT11:00:00Z'))")"
BB_START2="$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=7); print(t.strftime('%Y-%m-%dT11:00:00Z'))")"
BB_END2="$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=7); print(t.strftime('%Y-%m-%dT12:00:00Z'))")"

BB1=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$BB_START\",\"end_time\":\"$BB_END\"}")
echo "Back-to-back 1: $BB1"

BB2=$(curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN2" \
  -d "{\"room_id\":$ROOM_ID,\"start_time\":\"$BB_START2\",\"end_time\":\"$BB_END2\"}")
echo "Back-to-back 2: $BB2"

echo ""
echo "=== 19. BOOKING LIST (ADMIN) ==="
echo "Admin's booking list:"
curl -s "$BASE/bookings?page=1&limit=100" -H "Authorization: Bearer $TOKEN1" | python3 -m json.tool

echo ""
echo "=== 20. ERROR CODES CHECK ==="
# Bad credentials
echo "Bad login:"
curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"wrong"}' | python3 -m json.tool

# Duplicate username
echo "Duplicate register:"
curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"pass123"}' | python3 -m json.tool

echo ""
echo "=== DONE ==="
