#!/usr/bin/env bash
# Cross-client TLS test for RB-09 (certificate expiry / renewal): ./tls-client-matrix.sh api.paysecure.in
# Checks certificate expiry, protocol versions, and that available client runtimes can connect.
# Clients that are not installed are reported as SKIP. Android, iOS and partner-bank endpoints are NOT
# covered here and must be tested separately (RB-09 step 17). Read-only. Exit 0 = all run tests passed.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"

HOST="${1:-api.paysecure.in}"
PORT="${PORT:-443}"
MIN_DAYS="${MIN_DAYS:-30}"
skip() { printf '  SKIP  %s\n' "$*"; }
require_cmd openssl curl

log "TLS client matrix for ${HOST}:${PORT}"

# --- Certificate ---
CERT="$(openssl s_client -connect "${HOST}:${PORT}" -servername "$HOST" </dev/null 2>/dev/null | openssl x509 2>/dev/null || true)"
if [ -z "$CERT" ]; then
  fail "Could not read a certificate from ${HOST}:${PORT}"
else
  END_DATE="$(openssl x509 -noout -enddate <<<"$CERT" | cut -d= -f2)"
  DAYS=$(( ( $(date -d "$END_DATE" +%s) - $(date +%s) ) / 86400 ))
  if [ "$DAYS" -ge "$MIN_DAYS" ]; then pass "Certificate valid for ${DAYS} more days (expires ${END_DATE})"
  elif [ "$DAYS" -ge 0 ]; then fail "Certificate expires in ${DAYS} days (minimum ${MIN_DAYS})"
  else fail "Certificate EXPIRED ${DAYS#-} days ago"; fi
  if openssl x509 -noout -checkhost "$HOST" <<<"$CERT" | grep -q "does match"; then pass "Certificate name matches ${HOST}"
  else fail "Certificate does not match host name ${HOST}"; fi
fi

# --- Chain verification with the system trust store ---
if openssl s_client -connect "${HOST}:${PORT}" -servername "$HOST" -verify_return_error </dev/null >/dev/null 2>&1; then
  pass "Certificate chain verifies against the system trust store"
else
  fail "Certificate chain does not verify (missing intermediate or untrusted CA)"
fi

# --- Protocol versions: TLS 1.2 and 1.3 must work, 1.0 and 1.1 must be refused ---
for v in tls1_2 tls1_3; do
  if openssl s_client -connect "${HOST}:${PORT}" -servername "$HOST" "-${v}" </dev/null >/dev/null 2>&1; then pass "Protocol ${v} accepted"
  else fail "Protocol ${v} refused (clients need it)"; fi
done
for v in tls1 tls1_1; do
  if openssl s_client -connect "${HOST}:${PORT}" -servername "$HOST" "-${v}" </dev/null >/dev/null 2>&1; then fail "Legacy protocol ${v} is accepted (PCI DSS requires strong cryptography)"
  else pass "Legacy protocol ${v} refused"; fi
done

# --- curl, HTTP/1.1 and HTTP/2 ---
for h in --http1.1 --http2; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$h" "https://${HOST}:${PORT}/health/live" || echo 000)"
  if [ "$code" = "200" ]; then pass "curl ${h} /health/live -> 200"; else fail "curl ${h} /health/live -> ${code}"; fi
done

# --- Language runtimes (health endpoint only; no payment data) ---
URL="https://${HOST}:${PORT}/health/live"
if command -v python3 >/dev/null && python3 -c 'import requests' 2>/dev/null; then
  if python3 -c "import requests,sys; sys.exit(0 if requests.get('${URL}',timeout=10).status_code==200 else 1)"; then pass "Python requests"; else fail "Python requests"; fi
else skip "Python requests (not installed)"; fi

if command -v node >/dev/null; then
  if node -e "fetch('${URL}').then(r=>process.exit(r.status===200?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    pass "Node $(node -v)"; else fail "Node $(node -v)"; fi
else skip "Node (not installed)"; fi

if command -v java >/dev/null; then
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  cat > "$TMP/Check.java" <<JAVA
import java.net.URI; import java.net.http.*;
public class Check { public static void main(String[] a) throws Exception {
  var r = HttpClient.newHttpClient().send(HttpRequest.newBuilder(URI.create("${URL}")).build(), HttpResponse.BodyHandlers.discarding());
  System.exit(r.statusCode()==200?0:1); } }
JAVA
  if java "$TMP/Check.java" >/dev/null 2>&1; then pass "Java $(java -version 2>&1 | head -1)"; else fail "Java $(java -version 2>&1 | head -1)"; fi
else skip "Java (not installed; test JDK 11 and 17 separately)"; fi

skip "Android, iOS and partner bank endpoints: test manually (RB-09 step 17)"
summary_and_exit
