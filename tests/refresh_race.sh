#!/bin/bash
# Test refresh token race condition

BASE="http://localhost:8080"

# Register & Login
curl -s -X POST "$BASE/auth/register" -H "Content-Type: application/json" \
  -d '{"org_name":"race_org","username":"race_user","password":"password"}' > /dev/null

LOGIN=$(curl -s -X POST "$BASE/auth/login" -H "Content-Type: application/json" \
  -d '{"org_name":"race_org","username":"race_user","password":"password"}')

REFRESH_TOKEN=$(echo "$LOGIN" | python3 -c "import sys,json; print(json.load(sys.stdin)['refresh_token'])")

echo "Starting 10 concurrent refresh requests..."

for i in {1..10}; do
  curl -s -X POST "$BASE/auth/refresh" -H "Content-Type: application/json" \
    -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}" &
done

wait
echo ""
echo "Done."
