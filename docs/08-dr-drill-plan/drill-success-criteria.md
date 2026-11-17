# DR Drill Success Criteria

These criteria decide whether a drill passed. They apply to every drill in `annual-drill-plan.md`. Results are recorded in `post-drill-template.md`.

Baseline (same as every other document): 3.2M txns/day | 500 crore INR/day | 1,200 peak TPS | 180 ms P99 | 45,000 merchants | RPO under 60 s | RTO under 5 min (documented 4 min).

## 1. Full regional failover drills (Months 3, 6, 9, 12)

| Criterion | Pass | Measured how |
|---|---|---|
| Time to first successful write on Hyderabad | Under 4 min target, P95 across the year under 5 min | Fault (or switchover) start to first committed payment, from the dashboard |
| Time to fully verified | Under 6 min nominal, reported separately | Verification step timestamps in the drill log |
| Data loss (RPO) | Under 60 s of committed writes | Last committed transaction on each side |
| Reconciliation | Zero unexplained missing or duplicate transactions within 1 hour | `post-drill-reconcile.sh` |
| Latency | P99 under 300 ms (NPCI ceiling) at the load tested | Prometheus |
| Payment success rate | At least 98% outside the failover window | CloudWatch / Prometheus |
| Runbook accuracy | Under 5% of steps changed or skipped | Scribe log |
| Sovereignty | Zero resources outside ap-south-1 and ap-south-2 | `sovereignty-check.sh` |
| Failback | Completed and verified within the window | Drill log |
| Report | Signed within 5 business days | Drill Director |

A full drill **fails** if RTO exceeds 5 minutes, RPO exceeds 60 seconds, reconciliation shows unexplained loss, data leaves India, or the drill is aborted for a safety reason. A fail triggers a re-run within 30 days and an escalation to the BCRB; an RTO miss also reviews the active-active upgrade triggers.

## 2. Component drills (monthly)

| Drill | Pass criterion |
|---|---|
| Aurora single-AZ failover, AZ chaos | Success rate above 95% after scale-out; no manual region failover needed |
| ElastiCache failover, Kafka recovery, outbox bypass | No lost audit event; backlog cleared; replay idempotent |
| DNS failover only | Client switch measured at 10 s TTL; no split-brain |
| EKS node failure | Pods rescheduled within 30 s; no transaction failures |
| KMS rotation, certificate renewal | No payment failure; all client types connect |
| Kafka rebuild | Cluster rebuilt from Hyderabad within the RB-04 target |
| S3 replication validation | RTC met; restore sample matches |
| Cascading failure chaos | Circuit breaker opens; success rate recovers within the RB-12 target |
| Partner allow-list, WAF rehearsal, capacity test, sovereignty sweep | Partner confirmations 100%; no legitimate merchant blocked; time to full capacity fits the RTO; every control evidenced |

## 3. Weekly automated checks (52 per year)

The weekly run passes only if all 12 checks pass (`annual-drill-plan.md` Section 10a). Target: at least 50 of 52 weekly runs pass in a year; no more than 2 consecutive failures.

## 4. Grading

| Result | Meaning |
|---|---|
| **Pass** | All criteria met, no High finding |
| **Pass with findings** | Criteria met; runbook, tooling or documentation issues recorded with owners and dates |
| **Fail** | Any failure condition above; re-run and BCRB escalation |

Findings: High (a criterion failed or a safety issue), Medium (runbook wrong or slow), Low (cosmetic). High findings are fixed and re-tested within 30 days.

## 5. Evidence kept

Drill log with timestamps, dashboard exports, reconciliation output, sovereignty check output, signed report, and findings tracker, retained for 7 years. This evidence supports PCI DSS 12.10.2 (incident response plan tested annually) and the System Audit Report.
