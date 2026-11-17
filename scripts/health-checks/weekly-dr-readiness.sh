#!/usr/bin/env bash
# Weekly DR readiness run: the 12 checks of annual-drill-plan.md Section 10a (52 runs a year).
# Read-only. Exit 0 = all 12 pass. Schedule: Mondays 06:00 IST (cron, EventBridge or the CI scheduler).
# Usage: HC_MUM_ID=... HC_HYD_ID=... ./weekly-dr-readiness.sh
# Optional: TEXTFILE_DIR (Prometheus textfile collector), DR_CONTEXT, MIN_DR_NODES, HOST (default api.paysecure.in)
set -euo pipefail
HERE="$(dirname "$0")"
# shellcheck source=../common.sh
source "$HERE/../common.sh"
require_cmd aws kubectl
: "${HC_MUM_ID:?set HC_MUM_ID}" "${HC_HYD_ID:?set HC_HYD_ID}"
DR_CONTEXT="${DR_CONTEXT:-paysecure-dr}"
MIN_DR_NODES="${MIN_DR_NODES:-12}"
HOST="${HOST:-api.paysecure.in}"

run_check() { # run_check "label" command...
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

log "Weekly DR readiness run"

# 1-3 replication lag (Aurora, DynamoDB, MSK) and 4 S3: the lag script covers 1-3
run_check "1-3 Replication lag inside thresholds (Aurora, DynamoDB, MSK)" "$HERE/replication-lag-check.sh"

failed_repl="$(aws cloudwatch describe-alarms --region "$PRIMARY_REGION" --alarm-name-prefix paysecure-s3- --state-value ALARM --query 'length(MetricAlarms)' --output text)"
[ "$failed_repl" = "0" ] && pass "4 No S3 replication failure alarms" || fail "4 S3 replication failure alarms active: ${failed_repl}"

# 5 Route 53 health checks not inverted and reporting
ok=1
for id in "$HC_MUM_ID" "$HC_HYD_ID"; do
  inv="$(aws route53 get-health-check --health-check-id "$id" --query 'HealthCheck.HealthCheckConfig.Inverted' --output text)"
  [ "$inv" = "False" ] || ok=0
done
[ "$ok" = "1" ] && pass "5 Route 53 health checks present and not inverted" || fail "5 A Route 53 health check is inverted"

# 6 Hyderabad nodes ready
READY="$(kubectl --context "$DR_CONTEXT" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)"
[ "$READY" -ge "$MIN_DR_NODES" ] && pass "6 ${READY} Hyderabad nodes Ready" || fail "6 Only ${READY} Hyderabad nodes Ready (minimum ${MIN_DR_NODES})"

# 7 Capacity reservations
ACTIVE="$(aws ec2 describe-capacity-reservations --region "$DR_REGION" --filters Name=state,Values=active --query 'length(CapacityReservations)' --output text)"
ALL="$(aws ec2 describe-capacity-reservations --region "$DR_REGION" --query 'length(CapacityReservations)' --output text)"
{ [ "$ALL" -ge 1 ] && [ "$ACTIVE" = "$ALL" ]; } && pass "7 All ${ALL} capacity reservations active" || fail "7 Capacity reservations: ${ACTIVE} of ${ALL} active"

# 8 KMS replica keys enabled
bad=0
for alias in alias/paysecure-cde alias/paysecure-data; do
  st="$(aws kms describe-key --region "$DR_REGION" --key-id "$alias" --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo Missing)"
  [ "$st" = "Enabled" ] || bad=1
done
[ "$bad" = "0" ] && pass "8 KMS replica keys enabled in Hyderabad" || fail "8 A KMS replica key is missing or not enabled"

# 9 TLS certificates (expiry and chain in both regions)
run_check "9 TLS certificate valid for 30+ days with a trusted chain" "$HERE/tls-client-matrix.sh" "$HOST"

# 10 Data sovereignty
run_check "10 No resources outside ap-south-1 / ap-south-2" "$HERE/sovereignty-check.sh"

# 11 Signed-image policy enforced in both clusters
pol_ok=1
for ctx in paysecure-primary "$DR_CONTEXT"; do
  mode="$(kubectl --context "$ctx" get clusterpolicy verify-signed-images -o jsonpath='{.spec.validationFailureAction}' 2>/dev/null || echo none)"
  [ "$mode" = "Enforce" ] || pol_ok=0
done
[ "$pol_ok" = "1" ] && pass "11 verify-signed-images is Enforce in both clusters" || fail "11 verify-signed-images not Enforce in both clusters"

# 12 Last backup restore test within 7 days: expects the restore job to tag its result in SSM Parameter Store
LAST="$(aws ssm get-parameter --region "$PRIMARY_REGION" --name /paysecure/dr/last-restore-test-epoch --query 'Parameter.Value' --output text 2>/dev/null || echo 0)"
AGE=$(( $(date +%s) - LAST ))
[ "$AGE" -le 604800 ] && pass "12 Backup restore test ran within 7 days" || fail "12 No successful backup restore test in the last 7 days (parameter /paysecure/dr/last-restore-test-epoch)"

write_metric paysecure_weekly_readiness_failures "$FAIL_COUNT"
write_metric paysecure_weekly_readiness_timestamp_seconds "$(date +%s)"
summary_and_exit
