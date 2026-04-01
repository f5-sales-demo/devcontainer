#!/bin/bash
# Firecrawl Stack Integration Tests
# Run: bash tests/test-firecrawl.sh
set -euo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Firecrawl Stack Integration Tests ==="
echo ""

echo "1. Infrastructure Prerequisites"
check "Redis is running on port 6379" redis-cli -p 6379 ping
check "PostgreSQL is accepting connections" pg_isready -h /var/run/postgresql -q
check "Firecrawl database exists" \
  bash -c "psql -h /var/run/postgresql -U postgres -lqt 2>/dev/null | grep -qw firecrawl"

echo ""
echo "2. Playwright Microservice (port 3000)"
check "Playwright process is listening on port 3000" \
  bash -c "ss -tlnp 2>/dev/null | grep -q ':3000 '"
check "Playwright /health endpoint responds" \
  curl -sf --connect-timeout 5 http://localhost:3000/health

echo ""
echo "3. Firecrawl API (port 3002)"
check "API root endpoint responds" \
  curl -sf --connect-timeout 5 http://localhost:3002/
check "API root returns expected JSON" \
  bash -c "curl -sf http://localhost:3002/ | jq -e '.message == \"Firecrawl API\"'"

echo ""
echo "4. Scrape Endpoint"
check "Scrape returns success for example.com" \
  bash -c "curl -sf --max-time 30 http://localhost:3002/v1/scrape \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"url\":\"https://example.com\",\"formats\":[\"markdown\"]}' \
    | jq -e '.success == true'"
check "Scraped markdown contains expected text" \
  bash -c "curl -sf --max-time 30 http://localhost:3002/v1/scrape \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"url\":\"https://example.com\",\"formats\":[\"markdown\"]}' \
    | jq -e '.data.markdown | test(\"Example Domain\")'"

echo ""
echo "5. Crawl Endpoint"
check "Crawl endpoint accepts request" \
  bash -c "curl -sf --max-time 15 http://localhost:3002/v1/crawl \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"url\":\"https://example.com\",\"limit\":1}' \
    | jq -e '.success == true'"

echo ""
echo "6. Map Endpoint"
check "Map endpoint accepts request" \
  bash -c "curl -sf --max-time 15 http://localhost:3002/v1/map \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"url\":\"https://example.com\"}' \
    | jq -e '.success == true'"

echo ""
echo "7. Batch Scrape Endpoint"
check "Batch scrape accepts request" \
  bash -c "curl -sf --max-time 15 http://localhost:3002/v1/batch/scrape \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"urls\":[\"https://example.com\"],\"formats\":[\"markdown\"]}' \
    | jq -e '.success == true'"

echo ""
echo "8. Search Endpoint"
check "Search returns results" \
  bash -c "curl -sf --max-time 15 http://localhost:3002/v1/search \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"query\":\"example domain\",\"limit\":2}' \
    | jq -e '.success == true'"

echo ""
echo "9. llms.txt Endpoint"
check "llms.txt generation accepts request" \
  bash -c "curl -sf --max-time 15 http://localhost:3002/v1/llmstxt \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"url\":\"https://example.com\"}' \
    | jq -e '.success == true'"

echo ""
echo "10. Crawl Management"
check "Active crawls endpoint responds" \
  bash -c "curl -sf --max-time 10 http://localhost:3002/v1/crawl/active \
    | jq -e '.success == true'"
# Start a crawl to test cancel and errors
CRAWL_MGMT_ID=$(curl -sf --max-time 15 http://localhost:3002/v1/crawl \
  -X POST -H "Content-Type: application/json" \
  -d '{"url":"https://example.com","limit":5}' 2>/dev/null | jq -r '.id // empty')
if [ -n "$CRAWL_MGMT_ID" ]; then
  check "Crawl errors endpoint responds" \
    bash -c "curl -sf --max-time 10 http://localhost:3002/v1/crawl/${CRAWL_MGMT_ID}/errors \
      | jq -e 'has(\"errors\")'"
  check "Crawl cancel returns cancelled status" \
    bash -c "curl -sf -X DELETE --max-time 10 http://localhost:3002/v1/crawl/${CRAWL_MGMT_ID} \
      | jq -e '.status == \"cancelled\"'"
else
  echo "  SKIP: Could not start crawl for management tests"
fi

echo ""
echo "11. Worker Infrastructure"
check "RabbitMQ is running" \
  bash -c "sudo rabbitmqctl status >/dev/null 2>&1"
check "NuQ prefetch worker process is running" \
  bash -c "pgrep -f 'nuq-prefetch-worker.js' >/dev/null 2>&1"
check "NuQ scrape worker process is running" \
  bash -c "pgrep -f 'nuq-worker.js' >/dev/null 2>&1"
check "Extract worker process is running" \
  bash -c "pgrep -f 'extract-worker.js' >/dev/null 2>&1"

echo ""
echo "12. LLM Configuration (Extract prerequisite)"
check "OPENAI_BASE_URL is set in environment" \
  bash -c "test -n \"\${OPENAI_BASE_URL:-}\""
check "OPENAI_API_KEY is set in environment" \
  bash -c "test -n \"\${OPENAI_API_KEY:-}\""

echo ""
echo "13. Extract Endpoint (LLM-powered)"
check "Extract returns structured data from example.com" \
  bash -c "curl -sf --max-time 120 http://localhost:3002/v1/extract \
    -X POST -H 'Content-Type: application/json' \
    -d '{\"urls\":[\"https://example.com\"],\"prompt\":\"Extract the main heading.\",\"schema\":{\"type\":\"object\",\"properties\":{\"heading\":{\"type\":\"string\"}}}}' \
    | jq -e '.success == true'"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL"
  exit 1
else
  echo "RESULT: PASS"
  exit 0
fi
