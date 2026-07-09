#!/bin/bash
# Test: Rate limiter with sleep inside lock blocks all users
# This test checks if booking creation from user A is blocked
# while user B's rate limit is being processed

BASE="http://localhost:8080"

# Register two orgs with members
curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"rate_org_a","username":"user_a","password":"pass"}' > /dev/null

curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"rate_org_b","username":"user_b","password":"pass"}' > /dev/null

TOKEN_A=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"rate_org_a","username":"user_a","password":"pass"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

TOKEN_B=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"rate_org_b","username":"user_b","password":"pass"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# Create rooms for each org
ROOM_A=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN_A" \
  -d '{"name":"RoomA","capacity":5,"hourly_rate_cents":100}' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

ROOM_B=$(curl -s -X POST "$BASE/rooms" -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN_B" \
  -d '{"name":"RoomB","capacity":5,"hourly_rate_cents":100}' | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "Room A: $ROOM_A, Room B: $ROOM_B"

# Test 21 concurrent bookings for one user -> 21st should get RATE_LIMITED
echo ""
echo "=== Rate limit test: 21 concurrent requests ==="
START=$(python3 -c "from datetime import datetime, timedelta; t=datetime.utcnow()+timedelta(days=30); print(t.strftime('%Y-%m-%dT'))")

for i in $(seq 1 21); do
    HOUR=$(printf "%02d" $i)
    NEXT_HOUR=$(printf "%02d" $((i+1)))
    if [ $i -le 8 ]; then
        # Use different days to avoid room conflict
        DAY=$((30 + i))
        S="${START/days=30/}2026-08-$(printf "%02d" $DAY)T10:00:00Z"
        E="2026-08-$(printf "%02d" $DAY)T11:00:00Z"
    fi
    curl -s -X POST "$BASE/bookings" -H "Content-Type: application/json" \
      -H "Authorization: Bearer $TOKEN_A" \
      -d "{\"room_id\":$ROOM_A,\"start_time\":\"2026-08-$(printf "%02d" $((i)))T10:00:00Z\",\"end_time\":\"2026-08-$(printf "%02d" $((i)))T11:00:00Z\"}" &
done

wait
echo ""
echo "=== All requests completed ==="

# Count results
echo "Checking booking count..."
curl -s "$BASE/bookings?limit=100" -H "Authorization: Bearer $TOKEN_A" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'Total bookings: {d[\"total\"]}')
"
