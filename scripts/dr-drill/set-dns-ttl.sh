#!/usr/bin/env bash
# Sets the TTL of both api.paysecure.in failover records (PRIMARY and SECONDARY).
# Drills: 10 s at T-24h. After drills: back to 30 s (restore-normal.sh does this).
# Dry run by default. Usage: ZONE_ID=Z... ./set-dns-ttl.sh 10 [--execute]
# Note: if Terraform manages these records (modules/dns), also change var.ttl_seconds or the next apply reverts it.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
require_cmd aws jq
: "${ZONE_ID:?set ZONE_ID}"
TTL="${1:?usage: set-dns-ttl.sh TTL_SECONDS [--execute]}"
# shellcheck disable=SC2034
[ "${2:-}" = "--execute" ] && EXECUTE=1
case "$TTL" in ''|*[!0-9]*) die "TTL must be a number" ;; esac

BATCH="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='api.paysecure.in.' && Type=='CNAME']" --output json \
  | jq --argjson ttl "$TTL" '{Comment:"DR drill TTL change", Changes: map({Action:"UPSERT", ResourceRecordSet: (.TTL = $ttl)})}')"
[ "$(jq '.Changes | length' <<<"$BATCH")" -eq 2 ] || die "expected 2 failover CNAME records for api.paysecure.in, found $(jq '.Changes | length' <<<"$BATCH")"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
echo "$BATCH" > "$TMP"
run aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "file://${TMP}"
