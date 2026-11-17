# Post-Drill Report Template

Copy this file to `docs/08-dr-drill-plan/reports/YYYY-MM-<drill-name>.md` (success criteria: `drill-success-criteria.md`) after each drill. Complete within 5 business days. Signed by the Incident Commander and the Compliance Officer.

## 1. Drill identity
| Field | Value |
|---|---|
| Drill ID | |
| Month in plan / date (IST) | |
| Type | Full failover / Component |
| Method | Planned switchover / Fault-injected / Under load / Unannounced / Chaos |
| Scenario and runbooks | |
| Environment | Production / Staging |
| Drill Director / IC / Observer / Safety Officer | |
| Start, end | |
| Aborted? (reason) | |

## 2. Results against targets
| Metric | Target | Measured | Pass? |
|---|---|---|---|
| Time to detect | Under 30 s | | |
| Time to decide | Under 60 s | | |
| Time to first successful write | Under 4 min (P95 under 5 min) | | |
| Time to fully verified | Under 6 min nominal | | |
| Data-loss window (RPO) | Under 60 s | | |
| Reconciliation: missing / duplicate | 0 / 0 unexplained | | |
| P99 latency after failover (at load tested) | Under 300 ms | | |
| Peak TPS tested | Full drills: up to 1,200 | | |
| Payment success rate during window | Above 98% outside failover | | |
| Runbook steps changed or skipped | Under 5% | | |
| Resources outside ap-south-1 / ap-south-2 | 0 | | |

## 3. Overall result
- [ ] Pass: all targets met
- [ ] Pass with findings: targets met, runbook or tooling issues found
- [ ] Fail: one or more of RTO, RPO, reconciliation or sovereignty targets missed (escalate to BCRB; review active-active triggers if RTO exceeded 5 minutes)

## 4. Timeline
| Time (IST) | Event | Planned | Actual | Notes |
|---|---|---|---|---|

## 5. Deviations from the runbook
| Step | What the runbook says | What happened | Fix needed |
|---|---|---|---|

## 6. Sovereignty and compliance check
| Check | Result | Evidence |
|---|---|---|
| Config query for resources outside the two Indian regions | | |
| Replication topology unchanged and Indian-only | | |
| No payment data in logs, traces or alerts (sample) | | |
| Notifications sent as planned (partners, NPCI, merchants, regulator if required) | | |
| Evidence stored in the immutable audit bucket | | |

## 7. Findings
| ID | Severity (High/Med/Low) | Finding | Owner | Due date | Status |
|---|---|---|---|---|---|

## 8. Cost and effort
Person-hours used, any AWS cost of the drill, and comparison with the planning estimate in the drill plan.

## 9. Sign-off
| Role | Name | Date |
|---|---|---|
| Incident Commander | | |
| Compliance Officer | | |
| Drill Director | | |
