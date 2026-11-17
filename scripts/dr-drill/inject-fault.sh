#!/usr/bin/env bash
# Starts or stops the fault for fault-injected drills #2 to #4 (annual-drill-plan.md Section 5.2).
#   --method fis      Starts an AWS Fault Injection Service experiment from a template you created beforehand.
#   --method hc       Inverts the Mumbai calculated health check, so Route 53 sees Mumbai as down.
#                     This tests detection and DNS only; it does NOT cut real connectivity.
# Usage: ./inject-fault.sh --method fis|hc --start|--stop [--execute]
# Env: FIS_TEMPLATE_ID (fis start), FIS_EXPERIMENT_ID (fis stop), HC_MUM_ID (hc)
# The FIS template must be defined separately, with a stop condition on the P1 payment-success alarm.
# Dry run by default.
set -euo pipefail
# shellcheck source=../common.sh
source "$(dirname "$0")/../common.sh"
require_cmd aws

METHOD=""; ACTION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --method) METHOD="${2:-}"; shift 2 ;;
    --start) ACTION=start; shift ;;
    --stop) ACTION=stop; shift ;;
    --execute) EXECUTE=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -n "$METHOD" ] && [ -n "$ACTION" ] || die "usage: --method fis|hc --start|--stop [--execute]"
confirm FAULT
log "Method=${METHOD} action=${ACTION} execute=${EXECUTE} (record the fault start time: RTO is measured from it)"

case "${METHOD}:${ACTION}" in
  fis:start) : "${FIS_TEMPLATE_ID:?set FIS_TEMPLATE_ID}"
             run aws fis start-experiment --region "$PRIMARY_REGION" --experiment-template-id "$FIS_TEMPLATE_ID" ;;
  fis:stop)  : "${FIS_EXPERIMENT_ID:?set FIS_EXPERIMENT_ID}"
             run aws fis stop-experiment --region "$PRIMARY_REGION" --id "$FIS_EXPERIMENT_ID" ;;
  hc:start)  : "${HC_MUM_ID:?set HC_MUM_ID}"
             run aws route53 update-health-check --health-check-id "$HC_MUM_ID" --inverted ;;
  hc:stop)   : "${HC_MUM_ID:?set HC_MUM_ID}"
             run aws route53 update-health-check --health-check-id "$HC_MUM_ID" --no-inverted ;;
  *) die "unknown method/action" ;;
esac
log "Fault ${ACTION} requested at $(ts)"
