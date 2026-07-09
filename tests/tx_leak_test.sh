#!/bin/bash
# Test: Verify that booking creation errors don't leave transactions open

BASE="http://localhost:8080"

# Login as existing member
LOGIN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"member1","password":"pass123"}')
TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

LOGIN_ADMIN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"audit_org","username":"admin1","password":"pass123"}')
TOKEN_ADMIN=$(echo "$LOGIN_ADMIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

echo "=== Test: Error in booking doesn't break subsequent requests ==="
# Try to create an invalid booking (past start time)
echo "Invalid booking attempt:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"room_id":1,"start_time":"2020-01-01T10:00:00Z","end_time":"2020-01-01T11:00:00Z"}' | python3 -m json.tool

# Now try a valid request - should still work
echo "Valid request after error:"
curl -s "$BASE/rooms" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Got {len(d)} rooms')"

# Try to create a booking with a non-existent room
echo "Non-existent room:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"room_id":99999,"start_time":"2026-08-01T10:00:00Z","end_time":"2026-08-01T11:00:00Z"}' | python3 -m json.tool

echo "Valid request after room error:"
curl -s "$BASE/rooms" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Got {len(d)} rooms')"

# Try to create a booking with room conflict
echo "Create booking for conflict test:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"room_id":1,"start_time":"2026-08-15T10:00:00Z","end_time":"2026-08-15T11:00:00Z"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d))"

echo "Conflict attempt:"
curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"room_id":1,"start_time":"2026-08-15T10:00:00Z","end_time":"2026-08-15T11:00:00Z"}' | python3 -m json.tool

echo "Valid request after conflict:"
curl -s "$BASE/rooms" -H "Authorization: Bearer $TOKEN" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'Got {len(d)} rooms')"

echo "=== DONE ==="
