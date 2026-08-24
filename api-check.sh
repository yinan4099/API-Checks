#!/usr/bin/env bash
#
# api-check.sh — generic HTTP/JSON API health checker.
#
# Hits a list of endpoints and verifies HTTP status + (optionally) that the
# body is valid JSON. Meant to be extended with real endpoints as needed.
#
# Usage:  ./api-check.sh
#         ./api-check.sh https://example.com/api/health https://example.com/api/status
#
set -uo pipefail

PASS=0; FAIL=0

c()  { printf '\033[%sm%s\033[0m' "$1" "$2"; }
ok() { PASS=$((PASS+1)); printf '  %s %s\n' "$(c 32 PASS)" "$1"; }
no() { FAIL=$((FAIL+1)); printf '  %s %s\n' "$(c 31 FAIL)" "$1"; }

# check_endpoint <url>
check_endpoint() {
  local url="$1"
  local body code ctype
  body="$(mktemp)"
  code="$(curl -sS -L -o "$body" -w '%{http_code}' -D "$body.h" --max-time 20 "$url" 2>/dev/null || echo 000)"
  ctype="$(grep -i '^content-type:' "$body.h" 2>/dev/null | tail -1 | tr -d '\r' | cut -d' ' -f2-)"

  if [ "$code" != "200" ]; then
    no "$url — HTTP $code"
    rm -f "$body" "$body.h"
    return
  fi
  ok "$url — HTTP 200 ($ctype)"

  if printf '%s' "$ctype" | grep -qi 'json'; then
    if jq empty "$body" >/dev/null 2>&1; then
      ok "$url — valid JSON body"
    else
      no "$url — Content-Type is JSON but body did not parse"
    fi
  fi

  rm -f "$body" "$body.h"
}

DEFAULT_ENDPOINTS=(
  "https://www.conifer.build"
)

ENDPOINTS=("${@:-${DEFAULT_ENDPOINTS[@]}}")

for url in "${ENDPOINTS[@]}"; do
  check_endpoint "$url"
done

echo
printf 'Results: %s passed, %s failed\n' "$(c 32 "$PASS")" "$(c 31 "$FAIL")"
[ "$FAIL" -eq 0 ]
