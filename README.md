# Entain Test task (golang)
Test task for Entain: REST web-server with Postgres database

### How to run application
```
git clone git@github.com:svirmi/entain-test-task.git
cd entain-test-task
docker compose up -d
```

Application will be running at ```http://localhost:8080``` with preset data for users with ids `1`, `2` and `3` .
To see balance for user with `id=1` run ```curl -s "http://localhost:8080/user/1/balance"```
To update balance ("win") for user with `id=1` run

```
curl -X POST http://localhost:8080/user/1/transaction \
  -H "Content-Type: application/json" \
  -H "Source-Type: game" \
  -d '{
    "state": "win",
    "amount": "11.99",
    "transactionId": "xxxxxxxx-0000-1111-2222-333000"
  }'
```

### How to automatically test
Application has test suit to test and check most obvious corner-cases
Run ```bash test.sh``` from the project root folder (application should be running)

#### Transaction Service Test Suite
1. Health check
2. All 3 predefined users exist (spec: userId 1, 2, 3)
3. GET /balance response structure
4. WIN — balance increases by exact amount
5. LOSE — balance decreases by exact amount
6. Transactions with the same transactionId is ignored 
7. Negative balance prevention
8. userId=0 rejected (must be positive uint64)
9. Unknown userId → error on both routes (GET, POST)
10. Missing Source-Type header → 400
11. Invalid Source-Type → 400
12. All 3 valid Source-Type values accepted
13. Invalid state → 400
14. Missing required body fields → 400
15. Decimal precision — 0.01 stored and returned correctly
16. Concurrent throughput — 30 parallel requests
17. User isolation — transaction on user A does not affect user B