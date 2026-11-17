#!/usr/bin/env bash
# After a drill: sovereignty check, replication state, reconciliation job, drill metrics.
# Usage: ./post-drill-reconcile.sh --drill-type unplanned --rto-seconds 232 [--context paysecure-dr]
# The reconciliation step expects a CronJob named by RECON_CRONJOB (default reconciliation-window-check) that
# prints lines "missing=<n>" and "duplicates=<n>". That job is an ASSUMPTION of this repository: adapt to the real one.
set -euo pipefail
HERE="$(dirname "$0")"
# shellcheck source=../common.sh
source "$HERE/../common.sh"
require_cmd aws kubectl

DRILL_TYPE=""; RTO=""; CONTEXT="${DR_CONTEXT:-paysecure-dr}"; CRON="${RECON_CRONJOB:-reconciliation-window-check}"
while [ $# -gt 0 ]; do
  case "$1" in
    --drill-type) DRILL_TYPE="${2:-}"; shift 2 ;;
    --rto-seconds) RTO="${2:-}"; shift 2 ;;
    --context) CONTEXT="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

log "Post-drill checks (context ${CONTEXT})"

"$HERE/../health-checks/sovereignty-check.sh" && pass "Sovereignty check clean" || fail "Sovereignty check failed"

"$HERE/../health-checks/replication-lag-check.sh" >/dev/null 2>&1 && pass "Replication lag inside thresholds" || warn "Replication lag outside thresholds: check direction after failback"

JOB="recon-$(date +%s)"
if kubectl --context "$CONTEXT" -n paysecure get cronjob "$CRON" >/dev/null 2>&1; then
  kubectl --context "$CONTEXT" -n paysecure create job --from="cronjob/${CRON}" "$JOB" >/dev/null
  if kubectl --context "$CONTEXT" -n paysecure wait --for=condition=complete "job/${JOB}" --timeout=900s >/dev/null 2>&1; then
    OUT="$(kubectl --context "$CONTEXT" -n paysecure logs "job/${JOB}")"
    MISSING="$(grep -oE 'missing=[0-9]+' <<<"$OUT" | tail -1 | cut -d= -f2 || true)"
    DUPES="$(grep -oE 'duplicates=[0-9]+' <<<"$OUT" | tail -1 | cut -d= -f2 || true)"
    if [ "${MISSING:-x}" = "0" ] && [ "${DUPES:-x}" = "0" ]; then pass "Reconciliation: 0 missing, 0 duplicate"
    else fail "Reconciliation: missing=${MISSING:-unknown} duplicates=${DUPES:-unknown} (investigate before sign-off)"; fi
  else fail "Reconciliation job ${JOB} did not complete in 15 minutes"; fi
else
  warn "CronJob ${CRON} not found: run reconciliation manually and attach the result to the drill report"
fi

if [ -n "$DRILL_TYPE" ] && [ -n "$RTO" ]; then
  write_metric paysecure_drill_rto_seconds "$RTO" "{drill_type=\"${DRILL_TYPE}\"}"
  [ "$RTO" -le 300 ] && pass "Measured RTO ${RTO}s is within 300s" || fail "Measured RTO ${RTO}s exceeds 300s: escalate to the BCRB"
fi
warn "Manual: complete docs/08-dr-drill-plan/post-drill-template.md and attach this output"
summary_and_exit
