#!/usr/bin/env bash
# Test script for Transaction Service
# Validates every requirement from the spec:
#   - POST /user/{userId}/transaction  (win/lose, idempotency, validation)
#   - GET  /user/{userId}/balance      (structure, precision)
#   - userId uint64 edge cases
#   - All 3 Source-Type values
#   - Required body fields
#   - Negative balance prevention
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
# Falls back to /proc/sys/kernel/random/uuid on Linux without uuidgen.
txn_id() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Random amount 0.10–10.00 to 2 decimal places.
# Seeded with RANDOM so rapid concurrent calls don't collide.
random_amount() {
    awk -v seed="$RANDOM" 'BEGIN { srand(seed); printf "%.2f", 0.10 + rand() * 9.90 }'
}

# Floating-point arithmetic — awk avoids bc dependency.
add() { awk "BEGIN { printf \"%.2f\", $1 + $2 }"; }
sub() { awk "BEGIN { printf \"%.2f\", $1 - $2 }"; }

post_transaction() {
    # Args: user_id state amount txn_id [source=game]
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

# Two distinct valid users + one guaranteed-invalid user for this run.
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
# Spec: predefined users 1, 2 and 3 must exist on a fresh service.
# We verify all three are reachable and return valid balance responses.
echo "Test 2: All 3 predefined users exist (spec: userId 1, 2, 3)"
for uid in 1 2 3; do
    resp=$(get_balance "$uid")
    uid_field=$(echo "$resp" | jq -r '.userId')
    bal_field=$(echo "$resp" | jq -r '.balance')
    [ "$uid_field" = "$uid" ] && [[ "$bal_field" =~ ^[0-9]+\.[0-9]{2}$ ]]
    print_result $? "user $uid reachable, balance=$bal_field"
done
echo ""

# ------------------------------------------
# Spec: response must contain userId (uint64) and balance (string, 2 dp).
echo "Test 3: GET /balance response structure"
resp=$(get_balance "$MAIN_USER")
uid_field=$(echo "$resp" | jq -r '.userId')
bal_field=$(echo "$resp" | jq -r '.balance')
[ "$uid_field" = "$MAIN_USER" ]
print_result $? "userId field matches requested user ($MAIN_USER)"
[[ "$bal_field" =~ ^[0-9]+\.[0-9]{2}$ ]]
print_result $? "balance is a string with exactly 2 decimal places ($bal_field)"
# Spec: balance field must be a JSON string, not a number.
bal_type=$(echo "$resp" | jq -r '.balance | type')
[ "$bal_type" = "string" ]
print_result $? "balance is JSON string type (not number)"
echo "  Response: $resp"
echo ""

# ------------------------------------------
# Spec: win must increase balance by exact amount.
echo "Test 4: WIN — balance increases by exact amount"
before=$(get_balance "$MAIN_USER" | jq -r '.balance')
amount=$(random_amount)
source=$(random_source)
echo "  source=$source  amount=$amount"
resp=$(post_transaction "$MAIN_USER" "win" "$amount" "$(txn_id)" "$source")
[ "$(http_code "$resp")" = "200" ]
print_result $? "win returns 200"
after=$(get_balance "$MAIN_USER" | jq -r '.balance')
[ "$after" = "$(add "$before" "$amount")" ]
print_result $? "balance increased: $before + $amount = $after"
echo ""

# ------------------------------------------
# Spec: lose must decrease balance.
echo "Test 5: LOSE — balance decreases by exact amount"
before=$(get_balance "$MAIN_USER" | jq -r '.balance')
# Fixed small amount: avoids accidentally going negative regardless of prior state.
amount="1.00"
source=$(random_source)
echo "  source=$source  amount=$amount"
resp=$(post_transaction "$MAIN_USER" "lose" "$amount" "$(txn_id)" "$source")
[ "$(http_code "$resp")" = "200" ]
print_result $? "lose returns 200"
after=$(get_balance "$MAIN_USER" | jq -r '.balance')
[ "$after" = "$(sub "$before" "$amount")" ]
print_result $? "balance decreased: $before - $amount = $after"
echo ""

# ------------------------------------------
# Spec: each transactionId must be processed only once.
echo "Test 6: Idempotency — same transactionId is a no-op"
amount=$(random_amount)
dup_id=$(txn_id)
post_transaction "$MAIN_USER" "win" "$amount" "$dup_id" >/dev/null
balance_once=$(get_balance "$MAIN_USER" | jq -r '.balance')
# Second request — identical in every field.
resp=$(post_transaction "$MAIN_USER" "win" "$amount" "$dup_id")
[ "$(http_code "$resp")" = "200" ]
print_result $? "duplicate returns 200 (not an error)"
balance_twice=$(get_balance "$MAIN_USER" | jq -r '.balance')
[ "$balance_once" = "$balance_twice" ]
print_result $? "balance unchanged after duplicate ($balance_once)"
echo ""

# ------------------------------------------
# Spec: balance cannot go negative.
echo "Test 7: Negative balance prevention"
resp=$(post_transaction "$MAIN_USER" "lose" "999999.99" "$(txn_id)")
code=$(http_code "$resp")
[ "$code" != "200" ]
print_result $? "overdraft rejected (got $code, expected non-200)"
echo ""

# ------------------------------------------
# Spec: userId is a positive uint64 — zero must be rejected.
echo "Test 8: userId=0 rejected (must be positive uint64)"
resp=$(post_transaction "0" "win" "1.00" "$(txn_id)")
code=$(http_code "$resp")
[ "$code" != "200" ]
print_result $? "userId=0 rejected (got $code)"
resp=$(curl -s -w "\n%{http_code}" "$BASE_URL/user/0/balance")
code=$(http_code "$resp")
[ "$code" != "200" ]
print_result $? "GET balance userId=0 rejected (got $code)"
echo ""

# ------------------------------------------
# Spec: non-existent userId → error on both routes.
echo "Test 9: Unknown userId → error on both routes"
resp=$(post_transaction "$INVALID_USER" "win" "10.00" "$(txn_id)")
[ "$(http_code "$resp")" = "404" ]
print_result $? "POST unknown user returns 404"
resp=$(curl -s -w "\n%{http_code}" "$BASE_URL/user/$INVALID_USER/balance")
[ "$(http_code "$resp")" = "404" ]
print_result $? "GET balance unknown user returns 404"
echo ""

# ------------------------------------------
# Spec: Source-Type is required.
echo "Test 10: Missing Source-Type header → 400"
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" \
    -d "{\"state\":\"win\",\"amount\":\"1.00\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing Source-Type returns 400"
echo ""

# ------------------------------------------
# Spec: Source-Type values game/server/payment are valid; others are not.
echo "Test 11: Invalid Source-Type → 400"
resp=$(post_transaction "$MAIN_USER" "win" "1.00" "$(txn_id)" "casino")
[ "$(http_code "$resp")" = "400" ]
print_result $? "unknown source type 'casino' returns 400"
echo ""

# ------------------------------------------
# Spec: all 3 documented Source-Type values must be accepted.
echo "Test 12: All 3 valid Source-Type values accepted"
for src in "game" "server" "payment"; do
    resp=$(post_transaction "$MAIN_USER" "win" "0.01" "$(txn_id)" "$src")
    [ "$(http_code "$resp")" = "200" ]
    print_result $? "Source-Type '$src' returns 200"
done
echo ""

# ------------------------------------------
# Spec: state must be 'win' or 'lose'.
echo "Test 13: Invalid state → 400"
resp=$(post_transaction "$MAIN_USER" "draw" "1.00" "$(txn_id)")
[ "$(http_code "$resp")" = "400" ]
print_result $? "state='draw' returns 400"
echo ""

# ------------------------------------------
# Spec: body fields state, amount, transactionId are all required.
echo "Test 14: Missing required body fields → 400"
# Missing amount
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"state\":\"win\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing amount returns 400"

# Missing transactionId
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"state\":\"win\",\"amount\":\"1.00\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing transactionId returns 400"

# Missing state
resp=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$MAIN_USER/transaction" \
    -H "Content-Type: application/json" -H "Source-Type: game" \
    -d "{\"amount\":\"1.00\",\"transactionId\":\"$(txn_id)\"}")
[ "$(http_code "$resp")" = "400" ]
print_result $? "missing state returns 400"
echo ""

# ------------------------------------------
# Spec: amount precision — up to 2 decimal places.
echo "Test 15: Decimal precision — 0.01 stored and returned correctly"
before=$(get_balance "$MAIN_USER" | jq -r '.balance')
post_transaction "$MAIN_USER" "win" "0.01" "$(txn_id)" >/dev/null
after=$(get_balance "$MAIN_USER" | jq -r '.balance')
[ "$after" = "$(add "$before" "0.01")" ]
print_result $? "0.01 precision maintained ($before + 0.01 = $after)"
echo ""

# ------------------------------------------
# Spec: application must handle 20-30 concurrent transactions.
# We fire 30 simultaneous win requests and assert:
#   (a) all 30 committed (exact balance delta)
#   (b) all 30 completed within 10 seconds (well within 30 RPS)
echo "Test 16: Concurrent throughput — 30 parallel requests"
CONCURRENT=30
AMOUNT_EACH="1.00"
pre=$(get_balance "$MAIN_USER" | jq -r '.balance')
echo "  Balance before: $pre  firing $CONCURRENT x \$$AMOUNT_EACH wins..."
START_MS=$(date +%s%3N)
for i in $(seq 1 $CONCURRENT); do
    ( post_transaction "$MAIN_USER" "win" "$AMOUNT_EACH" "$(txn_id)" "$(random_source)" \
        >/dev/null 2>&1 ) &
done
wait
END_MS=$(date +%s%3N)
ELAPSED_MS=$(( END_MS - START_MS ))
echo "  Completed in ${ELAPSED_MS}ms"

post=$(get_balance "$MAIN_USER" | jq -r '.balance')
expected=$(add "$pre" "$(awk "BEGIN { printf \"%.2f\", $CONCURRENT * $AMOUNT_EACH }")")
[ "$post" = "$expected" ]
print_result $? "all $CONCURRENT transactions committed ($pre + ${CONCURRENT}.00 = $post)"
[ "$ELAPSED_MS" -lt 10000 ]
print_result $? "${CONCURRENT} requests completed in ${ELAPSED_MS}ms (< 10 000ms)"
echo ""

# ------------------------------------------
# Spec: transactions are isolated per user.
echo "Test 17: User isolation — transaction on user A does not affect user B"
before_a=$(get_balance "$MAIN_USER" | jq -r '.balance')
before_b=$(get_balance "$USER_B"    | jq -r '.balance')
amount=$(random_amount)
post_transaction "$MAIN_USER" "win" "$amount" "$(txn_id)" >/dev/null
after_a=$(get_balance "$MAIN_USER" | jq -r '.balance')
after_b=$(get_balance "$USER_B"    | jq -r '.balance')
[ "$after_a" = "$(add "$before_a" "$amount")" ]
print_result $? "user $MAIN_USER balance updated correctly"
[ "$after_b" = "$before_b" ]
print_result $? "user $USER_B balance unchanged"
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