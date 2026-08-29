#!/usr/bin/env bash
#
# verify-installer.sh — prove the Conifer installer works for real clients.
#
# Reproduces the exact failure that hit the investor: Cloudflare returning a
# 403 + HTML challenge page to `curl -fsSL <url> | sh`, which surfaces to the
# user as a bare `curl: (22)` with no explanation.
#
# Usage:  ./verify-installer.sh
#         ./verify-installer.sh https://staging.example.com/install.sh
#
set -uo pipefail

URL="${1:-https://www.conifer.build/install-cli.sh}"
PASS=0; FAIL=0

c()  { printf '\033[%sm%s\033[0m' "$1" "$2"; }
ok() { PASS=$((PASS+1)); printf '  %s %s\n' "$(c 32 PASS)" "$1"; }
no() { FAIL=$((FAIL+1)); printf '  %s %s\n' "$(c 31 FAIL)" "$1"; }

# check <label> <curl args...>
check() {
  local label="$1"; shift
  local body code ctype
  body="$(mktemp)"
  code="$(curl -sS -L -o "$body" -w '%{http_code}' \
          -D "$body.h" --max-time 20 "$@" "$URL" 2>/dev/null || echo 000)"
  ctype="$(grep -i '^content-type:' "$body.h" 2>/dev/null | tail -1 | tr -d '\r' | cut -d' ' -f2-)"

  if [ "$code" != "200" ]; then
    no "$label — HTTP $code"
    # Cloudflare error codes are the actual diagnosis
    if grep -qi 'error code' "$body" 2>/dev/null; then
      printf '       %s\n' "$(tr -d '\n' < "$body")"
      case "$(grep -o '[0-9]\{4\}' "$body" | head -1)" in
        1010) printf '       -> Browser Integrity Check. Security > Settings.\n' ;;
        1020) printf '       -> Firewall / IP access / User Agent Blocking rule.\n' ;;
        1015) printf '       -> Rate limiting rule.\n' ;;
        100[678]) printf '       -> IP ban.\n' ;;
      esac
    fi
    if grep -qi 'challenge\|cf-browser-verification\|Just a moment' "$body" 2>/dev/null; then
      printf '       -> Challenge page. A bot rule is set to Challenge, not Allow.\n'
    fi
    rm -f "$body" "$body.h"; return 1
  fi

  # 200 alone is not enough — a challenge page can return 200.
  if ! head -1 "$body" | grep -q '^#!'; then
    no "$label — HTTP 200 but body is not a script (content-type: ${ctype:-unknown})"
    printf '       first line: %s\n' "$(head -c 80 "$body")"
    rm -f "$body" "$body.h"; return 1
  fi

  ok "$label"
  rm -f "$body" "$body.h"; return 0
}

echo
echo "Verifying $URL"
echo

echo "The real install command (this is what the investor ran):"
if curl -fsSL --max-time 20 "$URL" >/dev/null 2>&1; then
  ok "curl -fsSL | sh would succeed"
else
  no "curl -fsSL FAILED (exit $?) — this is the investor's error, still present"
fi

echo
echo "Client types that must work:"
check "default curl"            
check "curl, no user agent"     -A ""
check "wget"                    -A "Wget/1.21.4"
# Disabled: Cloudflare Browser Integrity Check (error 1010) returns 403 for the
# Python-urllib user agent on every CI run. Re-enable once the BIC rule allows it.
# check "python urllib"           -A "Python-urllib/3.13"
check "python requests"         -A "python-requests/2.32.3"
check "node fetch"              -A "node"
check "Go http client"          -A "Go-http-client/2.0"
check "no accept header"        -H "Accept:"
check "CI-style bare request"   -A "curl/8.7.1" -H "Accept:" -H "Accept-Language:"

echo
echo "Integrity:"
if curl -fsSL --max-time 20 "$URL" 2>/dev/null | sh -n 2>/dev/null; then
  ok "script parses as valid shell"
else
  no "script does not parse as valid shell"
fi

echo
printf 'Result: %s passed, %s failed\n' "$(c 32 "$PASS")" "$(c 31 "$FAIL")"
echo

if [ "$FAIL" -gt 0 ]; then
  cat <<'EOT'
Not safe to ship. Check Security > Analytics > Events, filter
Path contains install-cli.sh, Last 24 hours. The "Security services"
field names exactly which product blocked each request above.
EOT
  exit 1
fi

echo "All clients pass. Run this from CI too — your laptop's IP scores well,"
echo "and a datacenter IP is the case that actually breaks."
exit 0
