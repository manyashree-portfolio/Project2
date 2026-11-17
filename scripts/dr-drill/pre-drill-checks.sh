#!/usr/bin/env bash
# Go/no-go checks for a DR drill (annual-drill-plan.md Section 4.1, T-1 hour). Read-only.
# Usage: HC_MUM_ID=... HC_HYD_ID=... ./pre-drill-checks.sh
# Exit 0 = all checks pass (GO). Any FAIL = NO-GO unless the Drill Director accepts the risk in writing.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
require_cmd aws kubectl jq
: "${HC_MUM_ID:?set HC_MUM_ID}" "${HC_HYD_ID:?set HC_HYD_ID}"
DR_CONTEXT="${DR_CONTEXT:-paysecure-dr}"
MIN_DR_NODES="${MIN_DR_NODES:-12}"

log "Pre-drill checks"

# 1. Replication lag inside thresholds
if "$(dirname "$0")/../health-checks/replication-lag-check.sh" >/dev/null 2>&1; then pass "Replication lag inside thresholds"
else fail "Replication lag check failed: run replication-lag-check.sh for detail"; fi

# 2. No P1/P2 alarms active
ACTIVE="$(aws cloudwatch describe-alarms --region "$PRIMARY_REGION" --state-value ALARM --alarm-name-prefix paysecure- --query 'length(MetricAlarms)' --output text)"
ACTIVE_DR="$(aws cloudwatch describe-alarms --region "$DR_REGION" --state-value ALARM --alarm-name-prefix paysecure- --query 'length(MetricAlarms)' --output text)"
if [ "$((ACTIVE + ACTIVE_DR))" -eq 0 ]; then pass "No paysecure alarms in ALARM state"; else fail "$((ACTIVE + ACTIVE_DR)) paysecure alarm(s) in ALARM state"; fi

# 3. Aurora global cluster healthy, Mumbai is the writer
W="$(aws rds describe-global-clusters --region "$DR_REGION" --global-cluster-identifier "$GLOBAL_CLUSTER" \
      --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn | [0]' --output text)"
case "$W" in *"${PRIMARY_REGION}"*) pass "Aurora writer is in Mumbai" ;; *) warn "Aurora writer is ${W} (expected Mumbai for a normal-direction drill)" ;; esac

# 4. DR cluster reachable, enough nodes ready
if READY="$(kubectl --context "$DR_CONTEXT" get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)"; then
  if [ "$READY" -ge "$MIN_DR_NODES" ]; then pass "${READY} Hyderabad nodes Ready (minimum ${MIN_DR_NODES})"
  else fail "Only ${READY} Hyderabad nodes Ready (minimum ${MIN_DR_NODES})"; fi
else fail "Cannot reach kubectl context ${DR_CONTEXT}"; fi

# 5. Capacity reservations active
CR="$(aws ec2 describe-capacity-reservations --region "$DR_REGION" --filters Name=state,Values=active --query 'length(CapacityReservations)' --output text)"
if [ "$CR" -ge 1 ]; then pass "${CR} active capacity reservation(s) in Hyderabad"; else fail "No active capacity reservations in Hyderabad"; fi

# 6. Route 53 health checks: Mumbai healthy, Hyderabad healthy, not inverted
for id in "$HC_MUM_ID" "$HC_HYD_ID"; do
  INV="$(aws route53 get-health-check --health-check-id "$id" --query 'HealthCheck.HealthCheckConfig.Inverted' --output text)"
  OK="$(aws route53 get-health-check-status --health-check-id "$id" --query 'length(HealthCheckObservations[?StatusReport.Status!=`null` && contains(StatusReport.Status, `Success`)])' --output text)"
  [ "$INV" = "False" ] && pass "Health check ${id} is not inverted" || fail "Health check ${id} is inverted (left over from a previous drill?)"
  [ "$OK" -ge 1 ] && pass "Health check ${id} has healthy observations" || fail "Health check ${id} has no healthy observations"
done

# 7. Sovereignty baseline
if "$(dirname "$0")/../health-checks/sovereignty-check.sh" >/dev/null 2>&1; then pass "Sovereignty baseline clean"
else fail "Sovereignty check failed: run sovereignty-check.sh for detail"; fi

warn "Manual: no open P1/P2 incident, no release freeze conflict, partners and merchants notified, TTL lowered 24 h ago (set-dns-ttl.sh 10), bridge and roles confirmed"
summary_and_exit
