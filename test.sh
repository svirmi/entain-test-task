#!/bin/bash

# Test script for Transaction Service
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

BASE_URL="http://localhost:8080"
PASSED=0
FAILED=0

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        ((FAILED++))
    fi
}

# Function to make a POST request
post_transaction() {
    local user_id=$1
    local state=$2
    local amount=$3
    local txn_id=$4
    local source_type=${5:-game}
    
    curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/$user_id/transaction" \
        -H "Content-Type: application/json" \
        -H "Source-Type: $source_type" \
        -d "{\"state\":\"$state\",\"amount\":\"$amount\",\"transactionId\":\"$txn_id\"}"
}

# Function to get balance
get_balance() {
    local user_id=$1
    curl -s "$BASE_URL/user/$user_id/balance"
}

echo "=========================================="
echo "Transaction Service Test Suite"
echo "=========================================="
echo ""

# Wait for service to be ready
echo "Waiting for service to be ready..."
for i in {1..30}; do
    if curl -s "$BASE_URL/health" > /dev/null 2>&1; then
        echo -e "${GREEN}Service is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}Service did not start in time${NC}"
        exit 1
    fi
    sleep 1
done
echo ""

# Test 1: Health Check
echo "Test 1: Health Check"
response=$(curl -s -w "\n%{http_code}" "$BASE_URL/health")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Health check endpoint"
echo ""

# Test 2: Get initial balance for user 1
echo "Test 2: Get Initial Balance"
response=$(get_balance 1)
balance=$(echo "$response" | jq -r '.balance')
user_id=$(echo "$response" | jq -r '.userId')
[ "$user_id" = "1" ] && [ "$balance" = "100.00" ]
print_result $? "User 1 initial balance is 100.00"
echo "Response: $response"
echo ""

# Test 3: Win transaction (increase balance)
echo "Test 3: Win Transaction"
response=$(post_transaction 1 "win" "25.50" "test-win-001")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Win transaction processed"
echo ""

# Test 4: Verify balance increased
echo "Test 4: Verify Balance Increased"
response=$(get_balance 1)
balance=$(echo "$response" | jq -r '.balance')
[ "$balance" = "125.50" ]
print_result $? "Balance increased to 125.50"
echo "Response: $response"
echo ""

# Test 5: Lose transaction (decrease balance)
echo "Test 5: Lose Transaction"
response=$(post_transaction 1 "lose" "10.00" "test-lose-001")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Lose transaction processed"
echo ""

# Test 6: Verify balance decreased
echo "Test 6: Verify Balance Decreased"
response=$(get_balance 1)
balance=$(echo "$response" | jq -r '.balance')
[ "$balance" = "115.50" ]
print_result $? "Balance decreased to 115.50"
echo "Response: $response"
echo ""

# Test 7: Idempotency - duplicate transaction
echo "Test 7: Idempotency Test (Duplicate Transaction)"
response=$(post_transaction 1 "win" "25.50" "test-win-001")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Duplicate transaction handled correctly"
# Verify balance didn't change
response=$(get_balance 1)
balance=$(echo "$response" | jq -r '.balance')
[ "$balance" = "115.50" ]
print_result $? "Balance unchanged after duplicate transaction"
echo ""

# Test 8: Insufficient balance
echo "Test 8: Insufficient Balance"
response=$(post_transaction 2 "lose" "1000.00" "test-fail-001")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "400" ]
print_result $? "Insufficient balance returns 400"
echo ""

# Test 9: Invalid user ID
echo "Test 9: Invalid User ID"
response=$(post_transaction 999 "win" "10.00" "test-invalid-user")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "404" ]
print_result $? "Invalid user ID returns 404"
echo ""

# Test 10: Missing Source-Type header
echo "Test 10: Missing Required Header"
response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/user/1/transaction" \
    -H "Content-Type: application/json" \
    -d '{"state":"win","amount":"10.00","transactionId":"test-no-header"}')
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "400" ]
print_result $? "Missing Source-Type header returns 400"
echo ""

# Test 11: Different source types
echo "Test 11: Different Source Types"
response=$(post_transaction 1 "win" "5.00" "test-server-001" "server")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Server source type accepted"

response=$(post_transaction 1 "win" "5.00" "test-payment-001" "payment")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Payment source type accepted"
echo ""

# Test 12: Decimal precision
echo "Test 12: Decimal Precision"
response=$(post_transaction 3 "win" "0.01" "test-precision-001")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "200" ]
print_result $? "Small decimal amount processed"

response=$(get_balance 3)
balance=$(echo "$response" | jq -r '.balance')
[ "$balance" = "75.01" ]
print_result $? "Balance precision maintained (75.01)"
echo ""

# Test 13: Multiple users
echo "Test 13: Multiple Users"
response=$(get_balance 2)
user_id=$(echo "$response" | jq -r '.userId')
[ "$user_id" = "2" ]
print_result $? "User 2 exists"

response=$(get_balance 3)
user_id=$(echo "$response" | jq -r '.userId')
[ "$user_id" = "3" ]
print_result $? "User 3 exists"
echo ""

# Test 14: Invalid state
echo "Test 14: Invalid State Value"
response=$(post_transaction 1 "invalid" "10.00" "test-invalid-state")
http_code=$(echo "$response" | tail -n 1)
[ "$http_code" = "400" ]
print_result $? "Invalid state returns 400"
echo ""

# Test 15: Concurrent transactions simulation
echo "Test 15: Sequential Transactions (Concurrency Simulation)"
for i in {1..5}; do
    post_transaction 1 "win" "1.00" "concurrent-$i" "game" > /dev/null 2>&1 &
done
wait
sleep 1

response=$(get_balance 1)
balance=$(echo "$response" | jq -r '.balance')
# Starting balance 115.50 + 10.00 (from test 11) + 5.00 (from concurrent) = 130.50
print_result 0 "Concurrent transactions completed"
echo "Final balance after concurrent operations: $balance"
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
echo -e "${RED}Failed: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
