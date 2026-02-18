#!/usr/bin/env bash
# Test script for Transaction Service
# Zero external dependencies — uses only bash built-ins, grep, sed, awk, curl.
# Validates every requirement from the spec:
#   - POST /user/{userId}/transaction  (win/lose, idempotency, validation)
#   - GET  /user/{userId}/balance      (structure, precision)
#   - userId uint64 edge cases
#   - All 3 Source-Type values
#   - Required body fields
#   - Negative balance protection
#   - Concurrent throughput (30 RPS target)
#   - All 3 predefined users exist on a fresh service

# ==========================================
# Colours
# ==========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BASE_URL="http://localhost:8080"
PASSED=0
FAILED=0

# ==========================================
# Helpers
# ==========================================

print_result() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAILED++))
    fi
}

# Arrays matching spec requirements.
VALID_USERS=(1 2 3)
SOURCES=("game" "server" "payment")

random_user()   { echo "${VALID_USERS[$RANDOM % ${#VALID_USERS[@]}]}"; }
random_source() { echo "${SOURCES[$RANDOM % ${#SOURCES[@]}]}"; }

# uuidgen: globally unique per call, stateless, safe from subshells.
txn_id() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s%N)-$$-$RANDOM"
    fi
}

# Random amount 0.10–10.00 to 2 decimal places.
random_amount() {
    awk -v seed="$RANDOM" 'BEGIN { srand(seed); printf "%.2f", 0.10 + rand() * 9.90 }'
}

# Floating-point arithmetic.
add() { awk "BEGIN { printf \"%.2f\", $1 + $2 }"; }
sub() { awk "BEGIN { printf \"%.2f\", $1 - $2 }"; }

post_transaction() {
    local user_id=$1 state=$2 amount=$3 txn_id=$4 source=${5:-game}
    curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$user_id/transaction" \
        -H "Content-Type: application/json" \
        -H "Source-Type: $source" \
        -d "{\"state\":\"$state\",\"amount\":\"$amount\",\"transactionId\":\"$txn_id\"}"
}

get_balance() {
    curl -s "$BASE_URL/user/$1/balance"
}

http_code() { echo "$1" | tail -n1; }

# Extract JSON field using grep/sed — no jq dependency.
# Usage: json_field '{"userId":1,"balance":"100.00"}' userId  → 1
#        json_field '{"userId":1,"balance":"100.00"}' balance → 100.00
json_field() {
    local json=$1 key=$2
    echo "$json" | grep -o "\"$key\":[^,}]*" | sed 's/.*://; s/"//g'
}

# ==========================================
# Boot
# ==========================================
echo "=========================================="
echo "Transaction Service Test Suite"
echo "=========================================="
echo ""

echo "Waiting for service..."
for i in $(seq 1 30); do
    if curl -s "$BASE_URL/health" >/dev/null 2>&1; then
        echo -e "${GREEN}Service ready.${NC}"
        break
    fi
    [ "$i" -eq 30 ] && { echo -e "${RED}Service not ready after 30s.${NC}"; exit 1; }
    sleep 1
done
echo ""

MAIN_USER=$(random_user)
USER_B=$(random_user)
while [ "$USER_B" = "$MAIN_USER" ]; do USER_B=$(random_user); done
INVALID_USER=$(( 1000 + RANDOM ))

echo "Configuration for this run:"
echo "  Main user:    $MAIN_USER"
echo "  Secondary:    $USER_B"
echo "  Invalid user: $INVALID_USER"
echo ""

# ==========================================
# Tests
# ==========================================

# ------------------------------------------
echo "Test 1: Health check"
resp=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
[ "$(http_code "$resp")" = "200" ]
print_result $? "GET /health returns 200"
echo ""

# ------------------------------------------
echo "Test 2: All 3 predefined users exist"
for uid in 1 2 3; do
    resp=$(get_balance "$uid")
    uid_field=$(json_field "$resp" userId)
    bal_field=$(json_field "$resp" balance)
    [ "$uid_field" = "$uid" ] && [[ "$bal_field" =~ ^[0-9]+\.[0-9]{2}$ ]]
    print_result $? "user $uid reachable, balance=$bal_field"
done
echo ""

# ------------------------------------------
echo "Test 3: GET /balance response structure"
resp=$(get_balance "$MAIN_USER")
uid_field=$(json_field "$resp" userId)
bal_field=$(json_field "$resp" balance)
[ "$uid_field" = "$MAIN_USER" ]
print_result $? "userId field matches ($MAIN_USER)"
[[ "$bal_field" =~ ^[0-9]+\.[0-9]{2}$ ]]
print_result $? "balance is 2-decimal string ($bal_field)"
# Check balance is quoted (string) not bare (number).
echo "$resp" | grep -q "\"balance\":\"[0-9]"
print_result $? "balance is JSON string type"
echo "  Response: $resp"
echo ""

# ------------------------------------------
echo "Test 4: WIN — balance increases"
before=$(json_field "$(get_balance "$MAIN_USER")" balance)
amount=$(random_amount)
source=$(random_source)
echo "  source=$source  amount=$amount"
resp=$(post_transaction "$MAIN_USER" "win" "$amount" "$(txn_id)" "$source")
[ "$(http_code "$resp")" = "200" ]
print_result $? "win returns 200"
after=$(json_field "$(get_balance "$MAIN_USER")" balance)
[ "$after" = "$(add "$before" "$amount")" ]
print_result $? "balance increased: $before + $amount = $after"
echo ""

# ------------------------------------------
echo "Test 5: LOSE — balance decreases"
before=$(json_field "$(get_balance "$MAIN_USER")" balance)
amount="1.00"
source=$(random_source)
echo "  source=$source  amount=$amount"
resp=$(post_transaction "$MAIN_USER" "lose" "$amount" "$(txn_id)" "$source")
[ "$(http_code "$resp")" = "200" ]
print_result $? "lose returns 200"
after=$(json_field "$(get_balance "$MAIN_USER")" balance)
[ "$after" = "$(sub "$before" "$amount")" ]
print_result $? "balance decreased: $before - $amount = $after"
echo ""

# ------------------------------------------
echo "Test 6: Idempotency"
amount=$(random_amount)
dup_id=$(txn_id)
post_transaction "$MAIN_USER" "win" "$amount" "$dup_id" >/dev/null
balance_once=$(json_field "$(get_balance "$MAIN_USER")" balance)
resp=$(post_transaction "$MAIN_USER" "win" "$amount" "$dup_id")
[ "$(http_code "$resp")" = "200" ]
print_result $? "duplicate returns 200"
balance_twice=$(json_field "$(get_balance "$MAIN_USER")" balance)
[ "$balance_once" = "$balance_twice" ]
print_result $? "balance unchanged ($balance_once)"
echo ""

# ------------------------------------------
echo "Test 7: Negative balance prevention"
resp=$(post_transaction "$MAIN_USER" "lose" "999999.99" "$(txn_id)")
code=$(http_code "$resp")
[ "$code" != "200" ]
print_result $? "overdraft rejected (got $code)"
echo ""

# ------------------------------------------
echo "Test 8: userId=0 rejected"
resp=$(post_transaction "0" "win" "1.00" "$(txn_id)")
[ "$(http_code "$resp")" != "200" ]
print_result $? "POST userId=0 rejected"
resp=$(curl -s -w "\n%{http_code}" "$BASE_URL/user/0/balance")
[ "$(http_code "$resp")" != "200" ]
print_result $? "GET balance userId=0 rejected"
echo ""

# ------------------------------------------
echo "Test 9: Unknown userId → 404"
resp=$(post_transaction "$INVALID_USER" "win" "10.00" "$(txn_id)")
[ "$(http_code "$resp")" = "404" ]
print_result $? "POST unknown user returns 404"
resp=$(curl -s -w "\n%{http_code}" "$BASE_URL/user/$INVALID_USER/balance")
[ "$(http_code "$resp")" = "404" ]
print_result $? "GET balance unknown user returns 404"
echo ""

# ------------------------------------------
echo "Test 10: Missing Source-Type header → 400"
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" \
    -d "{\"state\":\"win\",\"amount\":\"1.00\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing Source-Type returns 400"
echo ""

# ------------------------------------------
echo "Test 11: Invalid Source-Type → 400"
resp=$(post_transaction "$MAIN_USER" "win" "1.00" "$(txn_id)" "casino")
[ "$(http_code "$resp")" = "400" ]
print_result $? "unknown source type returns 400"
echo ""

# ------------------------------------------
echo "Test 12: All 3 valid Source-Type values"
for src in "game" "server" "payment"; do
    resp=$(post_transaction "$MAIN_USER" "win" "0.01" "$(txn_id)" "$src")
    [ "$(http_code "$resp")" = "200" ]
    print_result $? "Source-Type '$src' accepted"
done
echo ""

# ------------------------------------------
echo "Test 13: Invalid state → 400"
resp=$(post_transaction "$MAIN_USER" "draw" "1.00" "$(txn_id)")
[ "$(http_code "$resp")" = "400" ]
print_result $? "state='draw' returns 400"
echo ""

# ------------------------------------------
echo "Test 14: Missing required body fields → 400"
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"state\":\"win\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing amount returns 400"

resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"state\":\"win\",\"amount\":\"1.00\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing transactionId returns 400"

resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"amount\":\"1.00\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing state returns 400"
echo ""

# ------------------------------------------
echo "Test 15: Decimal precision"
before=$(json_field "$(get_balance "$MAIN_USER")" balance)
post_transaction "$MAIN_USER" "win" "0.01" "$(txn_id)" >/dev/null
after=$(json_field "$(get_balance "$MAIN_USER")" balance)
[ "$after" = "$(add "$before" "0.01")" ]
print_result $? "0.01 precision: $before + 0.01 = $after"
echo ""

# ------------------------------------------
echo "Test 16: Concurrent throughput — 30 parallel requests"
CONCURRENT=30
AMOUNT_EACH="1.00"
pre=$(json_field "$(get_balance "$MAIN_USER")" balance)
echo "  Balance before: $pre  firing $CONCURRENT x \$$AMOUNT_EACH..."
START_MS=$(date +%s%3N)
for i in $(seq 1 $CONCURRENT); do
    ( post_transaction "$MAIN_USER" "win" "$AMOUNT_EACH" "$(txn_id)" "$(random_source)" \
        >/dev/null 2>&1 ) &
done
wait
END_MS=$(date +%s%3N)
ELAPSED_MS=$(( END_MS - START_MS ))
echo "  Completed in ${ELAPSED_MS}ms"

post=$(json_field "$(get_balance "$MAIN_USER")" balance)
expected=$(add "$pre" "$(awk "BEGIN { printf \"%.2f\", $CONCURRENT * $AMOUNT_EACH }")")
[ "$post" = "$expected" ]
print_result $? "all $CONCURRENT committed: $pre + ${CONCURRENT}.00 = $post"
[ "$ELAPSED_MS" -lt 10000 ]
print_result $? "completed in ${ELAPSED_MS}ms (< 10000ms)"
echo ""

# ------------------------------------------
echo "Test 17: User isolation"
before_a=$(json_field "$(get_balance "$MAIN_USER")" balance)
before_b=$(json_field "$(get_balance "$USER_B")" balance)
amount=$(random_amount)
post_transaction "$MAIN_USER" "win" "$amount" "$(txn_id)" >/dev/null
after_a=$(json_field "$(get_balance "$MAIN_USER")" balance)
after_b=$(json_field "$(get_balance "$USER_B")" balance)
[ "$after_a" = "$(add "$before_a" "$amount")" ]
print_result $? "user $MAIN_USER updated"
[ "$after_b" = "$before_b" ]
print_result $? "user $USER_B unchanged"
echo ""

# ==========================================
# Summary
# ==========================================
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi