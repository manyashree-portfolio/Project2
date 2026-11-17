#!/usr/bin/env bash
# Moves PaySecure payment traffic from Mumbai (ap-south-1) to Hyderabad (ap-south-2), following RB-01.
#
#   --mode planned     Aurora planned switchover (no data loss), DNS flipped by inverting the Mumbai health check.
#   --mode unplanned   Aurora failover with --allow-data-loss (region is down). DNS flips by itself through the
#                      Route 53 health check; this script only verifies it.
#
# DRY RUN BY DEFAULT: prints what it would do. Add --execute to change anything; you must then type FAILOVER.
# For a real incident follow docs/05-runbooks/RB-01-region-failure.md; the IC approves the decision first.
#
# Required environment:
#   HC_MUM_ID           Route 53 health check ID of HC-MUM-CALCULATED
#   KAFKA_BOOTSTRAP_DR  Hyderabad MSK bootstrap string (IAM, port 9098)
#   ZONE_ID             Hosted zone ID for paysecure.in
# Optional: DR_CONTEXT (kubectl context, default paysecure-dr), TEXTFILE_DIR (writes drill metrics)
#
# NOT TESTED against a live environment. Rehearse in staging, then in drill #1 (annual-drill-plan.md).
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"

MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --execute) EXECUTE=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ "$MODE" = "planned" ] || [ "$MODE" = "unplanned" ] || die "use --mode planned or --mode unplanned"
: "${HC_MUM_ID:?set HC_MUM_ID}" "${KAFKA_BOOTSTRAP_DR:?set KAFKA_BOOTSTRAP_DR}" "${ZONE_ID:?set ZONE_ID}"
require_cmd aws kubectl curl

DR_CONTEXT="${DR_CONTEXT:-paysecure-dr}"
ACCOUNT="$(account_id)"
SECONDARY_ARN="arn:aws:rds:${DR_REGION}:${ACCOUNT}:cluster:paysecure-secondary"
T0=$(date +%s)
mark() { local d=""; [ "$EXECUTE" = "1" ] || d=" [dry-run, not performed]"; log "T+$(( $(date +%s) - T0 ))s  $*${d}"; }

log "Mode: ${MODE}   Execute: ${EXECUTE}   Account: ${ACCOUNT}"
[ "$EXECUTE" = "1" ] || log "DRY RUN: nothing will be changed"
confirm FAILOVER

# 1. Preconditions
kubectl --context "$DR_CONTEXT" -n paysecure get configmap region-config >/dev/null || die "cannot read region-config on ${DR_CONTEXT}"
mark "Preconditions ok"

# 2. Aurora
if [ "$MODE" = "planned" ]; then
  run aws rds failover-global-cluster --region "$PRIMARY_REGION" --global-cluster-identifier "$GLOBAL_CLUSTER" \
      --target-db-cluster-identifier "$SECONDARY_ARN" --switchover
else
  run aws rds failover-global-cluster --region "$DR_REGION" --global-cluster-identifier "$GLOBAL_CLUSTER" \
      --target-db-cluster-identifier "$SECONDARY_ARN" --allow-data-loss
fi
if [ "$EXECUTE" = "1" ]; then
  for _ in $(seq 1 60); do
    W="$(aws rds describe-global-clusters --region "$DR_REGION" --global-cluster-identifier "$GLOBAL_CLUSTER" \
          --query "GlobalClusters[0].GlobalClusterMembers[?DBClusterArn=='${SECONDARY_ARN}'].IsWriter | [0]" --output text)"
    [ "$W" = "True" ] && break
    sleep 5
  done
  [ "${W:-}" = "True" ] || die "Hyderabad did not become the Aurora writer within 5 minutes"
fi
mark "Aurora writer is Hyderabad"

# 3. Redis global datastore
run aws elasticache failover-global-replication-group --global-replication-group-id paysecure-redis-global \
    --primary-region "$DR_REGION" --primary-replication-group-id paysecure-redis-hyd --region "$DR_REGION"
mark "Redis promotion requested"

# 4. Point services at Hyderabad, restart, then open for writes
DB_ENDPOINT="paysecure-secondary.cluster-REPLACE.${DR_REGION}.rds.amazonaws.com"
if [ "$EXECUTE" = "1" ]; then
  DB_ENDPOINT="$(aws rds describe-db-clusters --region "$DR_REGION" --db-cluster-identifier paysecure-secondary --query 'DBClusters[0].Endpoint' --output text)"
fi
run kubectl --context "$DR_CONTEXT" -n paysecure patch configmap region-config --type merge \
    -p "{\"data\":{\"aurora-endpoint\":\"${DB_ENDPOINT}\",\"kafka-bootstrap\":\"${KAFKA_BOOTSTRAP_DR}\"}}"
run kubectl --context "$DR_CONTEXT" -n paysecure rollout restart deployment payment-api transaction-processor
if [ "$EXECUTE" = "1" ]; then
  kubectl --context "$DR_CONTEXT" -n paysecure rollout status deployment/payment-api --timeout=180s
  kubectl --context "$DR_CONTEXT" -n paysecure rollout status deployment/transaction-processor --timeout=180s
fi
run kubectl --context "$DR_CONTEXT" -n paysecure patch configmap region-config --type merge \
    -p '{"data":{"write_ready":"true","region-role":"primary"}}'
mark "Services restarted and write_ready=true (first successful write expected now)"

# 5. DNS
if [ "$MODE" = "planned" ]; then
  # Inverting the Mumbai health check makes Route 53 treat Mumbai as unhealthy, so traffic moves to Hyderabad.
  # Undo with scripts/dr-drill/restore-normal.sh (--no-inverted).
  run aws route53 update-health-check --health-check-id "$HC_MUM_ID" --inverted
else
  log "Unplanned: Route 53 flips on its own once the Mumbai health check fails. Verifying only."
fi
sleep "${DNS_SETTLE_SECONDS:-0}"
run aws route53 test-dns-answer --hosted-zone-id "$ZONE_ID" --record-name api.paysecure.in --record-type CNAME
mark "DNS step done"

# 6. Verify
if [ "$EXECUTE" = "1" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 https://api-hyd.paysecure.in/health/synthetic || echo 000)"
  [ "$code" = "200" ] && mark "Hyderabad synthetic payment health: 200" || die "Hyderabad synthetic health returned ${code}"
  TOTAL=$(( $(date +%s) - T0 ))
  log "Elapsed since script start: ${TOTAL}s. Fault-to-first-write must be measured from the dashboard (RTO target 300 s)."
  write_metric paysecure_failover_script_seconds "$TOTAL" "{mode=\"${MODE}\"}"
fi
log "Next: run scripts/dr-drill/post-drill-reconcile.sh (reconciliation, sovereignty). Follow RB-01 verification steps."
