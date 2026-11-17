# Annual DR Drill Plan - PaySecure Gateway

A DR design only counts if it is rehearsed. This plan schedules **4 full-failover drills and 12 component drills per year** (the cadence stated in `comparison-matrix.md`), and places every drill the runbooks already promise (Month 1, 2, 3, 4, 5, 7, 8 and 11) in the month they named.

Baseline (same as every other document): 3.2M txns/day | 500 crore INR/day | 1,200 peak TPS | 180 ms P99 | 45,000 merchants | 8 crore INR/yr infra | 42 engineers (8 platform) | RPO < 60 s | documented RTO 4 min (mandate < 5 min) | revenue at risk about 62,500 INR per minute.

## 1. Objectives and success criteria

| # | Objective | Pass criterion | Source |
|---|---|---|---|
| 1 | Prove the RTO | Full-failover P95 time to first successful write on Hyderabad under 5 min across the year; target 4 min | dns-failover-design.md Section 7 |
| 2 | Prove the RPO | Data loss under 60 s of writes; measured from Aurora, DynamoDB and MSK lag at the moment of failover | replication-strategy.md |
| 3 | No duplicate or lost payments | Reconciliation within 1 hour shows zero unexplained duplicates and zero unexplained missing transactions | replication-strategy.md Section 9.3 |
| 4 | Keep latency inside the NPCI ceiling | P99 below 300 ms on Hyderabad at the load tested | NPCI [B] |
| 5 | Stay in India | Post-drill sovereignty query returns no resources outside ap-south-1 and ap-south-2 | `docs/07-data-sovereignty/compliance-matrix.md` Section 8 |
| 6 | Keep the humans ready | Every on-call engineer has run at least two drills as an executor in the year; runbook steps match reality | RB-01 to RB-12 |
| 7 | Produce audit evidence | Signed drill report within 5 business days (PCI DSS 12.10.2 incident response test, RBI and CERT-In auditor evidence) | Compliance matrix Section 4 |

**Escalation rule (already stated in the DNS design):** if any full drill exceeds 5 minutes, the RTO risk is escalated to the BCRB and the active-active upgrade triggers in `comparison-matrix.md` are reviewed.

## 2. Annual calendar

Months are relative (Month 1 = first month after go-live of the Hyderabad standby). **One component drill runs every month (12 per year) and a full regional failover runs in Months 3, 6, 9 and 12 (4 per year).** The windows move from low-traffic to business hours as confidence grows. Shift the start month so full drills avoid festival-sale peak weeks.

| Month | Drill type | Scenario | Impact window | Participants | Runbooks |
|---|---|---|---|---|---|
| 1 | Component | Aurora database failover (single AZ) and AZ power-failure chaos test (terminate one AZ's nodes; 16 nodes would reach about 90% CPU at peak) | 30 min | Platform team, DBA | RB-10, RB-02 |
| 2 | Component | ElastiCache failover and Kafka broker recovery, including the outbox bypass | 45 min | Platform team | RB-04 |
| 3 | **Full failover #1** | **Complete region failover, Sunday 3 AM IST** (planned switchover and failback) | 2 hours | All engineering and management | RB-01 |
| 3 | Component | Partner bank allow-list and VPN test against Hyderabad (run two weeks before the full drill) | 30 min | Platform, networking, partner banks | RB-05 |
| 4 | Component | DNS failover only (Route 53 switchover), secondary DNS provider, and network partition with the "no promotion" rule | 15 min (DNS), 30 min (partition) | Platform and networking | RB-03, RB-05 |
| 5 | Component | EKS node failure and pod rescheduling; second AZ-loss test at higher load | 30 min | Platform team | RB-10 |
| 6 | **Full failover #2** | **Complete region failover, Saturday morning** (fault-injected, unplanned style) | 2 hours | All engineering and management | RB-01 |
| 6 | Component | Load test of Hyderabad at the cost-optimised capacity (25% pre-provisioned) to decide whether the cost cut is locked in | 1 hour (non-production traffic) | Platform, finance observer | RB-01 |
| 7 | Component | KMS key rotation and certificate renewal in both regions, including the standby-CA certificate swap | 30 min | Security and platform | RB-06, RB-09 |
| 8 | Component | Kafka cluster rebuild from the replicated cluster (MSK Replicator), outbox replay | 1 hour | Platform and data engineering | RB-04 |
| 9 | **Full failover #3** | **Complete region failover, weekday low-traffic window, under synthetic near-peak load** | 2 hours | All engineering; **merchants and partner banks notified** | RB-01 |
| 9 | Component | DDoS WAF switch from Count to Block rehearsal | 30 min | Platform, security | RB-07 |
| 10 | Component | S3 cross-region replication validation; point-in-time restore of Aurora to a clean cluster (isolated account) | 15 min (S3), 5 hours (restore, no production impact) | Platform team, DBA | RB-02 |
| 11 | Component | **Chaos day:** cascading microservice failure simulation, NPCI/UPI outage simulation and ransomware tabletop | 45 min (chaos), tabletop 2 hours | All engineering | RB-12, RB-08, RB-11 |
| 12 | **Full failover #4** | **Complete region failover, weekday business hours** (trigger time not told to on-call), then failback | 2 hours | Full company drill | RB-01 |
| 12 | Component | Annual data sovereignty evidence sweep and plan review | 3 hours | Compliance, security, platform | `docs/07-data-sovereignty` |

That is 4 full and 12 component drills. The impact window is the time production may be affected; preparation and stand-down happen outside it. A drill is not repeated in the month it runs for a different team.

**Go/no-go gate for drill #4 (business hours).** It runs only if drills #1 to #3 each met the P95 RTO target, no High finding is open, and the CTO and the BCRB approve in writing. If the gate fails, drill #4 is run at the drill #3 window instead and the reason is recorded.

### Progression of the four full drills

| Drill | Window | Method | What is new |
|---|---|---|---|
| #1 (Month 3) | Sunday 3 AM IST | Planned switchover in production, everything announced | Proves the mechanics and the first RTO number |
| #2 (Month 6) | Saturday morning | Unplanned-style: the primary is cut off with fault injection, no graceful steps | Proves detection, decision and promotion under fault |
| #3 (Month 9) | Weekday low-traffic | Unplanned-style with synthetic load near peak (target 1,200 TPS); merchants notified | Proves capacity and latency on Hyderabad with real weekday traffic |
| #4 (Month 12) | Weekday business hours | Trigger time not announced to the on-call team; followed by a failback | Proves readiness, handoffs and the full cycle under real load |

**Honest limit:** a planned switchover (drill #1) is not the same as a real regional outage, where the primary may give no warning and replication state is uncertain. Drills #2 to #4 narrow that gap. A real failure can still behave differently, so the RTO reported on the dashboard should always be labelled with the drill type that produced it.

## 3. Roles

Roles are the same as in `docs/05-runbooks/README.md`, with three drill-only roles added.

| Role | Who | Drill responsibility |
|---|---|---|
| Drill Director | Platform lead | Owns the plan, scope, go/no-go and abort decisions |
| Incident Commander (IC) | On-call IC | Runs the exercise as if real; approves failover steps |
| SRE-1 and SRE-2 | On-call SREs | Execute the runbook |
| DBA, NET, DATA, SEC | Per runbook | Execute their parts |
| COMP | Compliance Officer | Regulator and partner notifications, sovereignty check, sign-off |
| COMMS | Communications Lead | Merchant and partner notices |
| Observer / Scribe (drill-only) | Engineer not in the active rota | Times every step and records deviations from the runbook |
| Safety Officer (drill-only) | Senior SRE | Watches production health and can call an abort |
| Auditor liaison (drill-only) | COMP or delegate | Gathers evidence for QSA and the CERT-In empanelled auditor |

## 4. Rules for every drill

### 4.1 Before the drill

| When | Action | Owner |
|---|---|---|
| T-30 days | Scenario, scope, date and abort criteria approved; entered in the change calendar | Drill Director |
| T-14 days | Partner banks, NPCI contact and internal management told of the window. COMP confirms which regulator notifications apply to planned drills; this plan does not assume | COMP |
| T-7 days | Merchants notified of a possible short disruption for production full drills, with the idempotency-key reminder from the merchant template | COMMS |
| T-3 days | Replication health, drift report and capacity reservations reviewed; no open P1 or P2 incidents; no release freeze conflict | SRE-2 |
| T-24 hours | Route 53 TTL lowered to 10 s (restored to 30 s afterwards, as in the DNS design). On-call roster and bridge confirmed | NET |
| T-1 hour | Go/no-go: replication lag under thresholds, success rate normal, all roles present | Drill Director |

### 4.2 Abort criteria (apply to every production drill)

The Safety Officer or Drill Director stops the drill and returns to normal operation if any of these is true. These thresholds are **proposed** and should be agreed by the CTO and the BCRB.

- Payment success rate below 98% for 3 minutes outside the planned failover window
- Replication lag above the P1 thresholds in `replication-strategy.md` Section 10 before the drill starts
- A real incident of severity P2 or higher begins elsewhere
- Any sign that payment data has left India
- A partner bank or NPCI asks to stop
- The Drill Director loses confidence in the safety of the next step

On abort, use the rollback section of the relevant runbook and record the reason. An aborted drill does not count towards the 4 + 12 and is re-run within 30 days.

### 4.3 During the drill

1. The IC opens an incident channel marked **DRILL** on every message, and a PagerDuty incident of drill type so real escalation policies are not triggered.
2. The Observer logs each step: planned time, actual time, executor and result. The runbook is followed as written; every deviation is recorded.
3. Time-to-detect, time-to-decide, time-to-promote, time-to-first-write and time-to-verified are captured from dashboards, not memory.
4. Real merchant traffic is protected by the circuit-breaker and idempotency controls already in the runbooks.

### 4.4 After the drill

| Within | Action | Owner |
|---|---|---|
| 1 hour | Restore normal state, TTL back to 30 s, confirm replication healthy in the original direction or the new one as planned | SRE-1 |
| 1 hour | Run the reconciliation job and the sovereignty query; attach results | DBA, COMP |
| 24 hours | Hot-wash meeting: what worked, what failed, what surprised us | Drill Director |
| 5 business days | Drill report completed using `post-drill-template.md` and signed by IC and COMP | Drill Director |
| 10 business days | Findings entered in the tracker with owner and due date | Drill Director |
| 30 days | High-severity findings fixed and re-tested | Findings owners |

## 5. Scenario detail for the full drills

### 5.1 Full drill #1 (Month 3): planned switchover

1. Confirm lag under 1 s on Aurora, DynamoDB and MSK, and 15-minute S3 RTC compliance.
2. Run the planned switchover for the Aurora global cluster (no data loss path).
3. Promote or scale the Hyderabad EKS capacity and flip Route 53 per RB-01.
4. Verify end-to-end payment flow, webhooks, settlement and partner connectivity.
5. Run on Hyderabad for at least 60 minutes, then switch back.
6. Success: RTO within 5 minutes, zero data loss, reconciliation clean.

### 5.2 Full drill #2 (Month 6): fault-injected failover

1. Use AWS Fault Injection Service or an equivalent to disrupt connectivity from the application tier in Mumbai, or force the Route 53 health check to fail.
2. Let detection, the decision rule and the failover run as in a real event, with a managed Aurora failover (not switchover) to accept the lag-bound data loss.
3. Measure RPO from the last committed transaction on each side.
4. Run reconciliation against bank and NPCI references for the last 5 minutes before the fault.
5. Fail back after verification.

### 5.3 Full drill #3 (Month 9): failover under load

1. Generate synthetic traffic that ramps to about 1,200 TPS against a test merchant pool, in addition to real traffic if the window allows.
2. Run the failover as in drill #2.
3. Record Hyderabad CPU, connection counts, Aurora writer saturation, Kafka lag and P99.
4. Success: P99 under 300 ms and no throttling or capacity shortage; otherwise the capacity assumption in `docs/06-cost-analysis` is revisited.

### 5.4 Full drill #4 (Month 12): unannounced

1. Only the Drill Director, the IC role holder, COMP and the Safety Officer know the date. The window is chosen inside an approved two-week range.
2. The trigger is injected; the on-call team responds from the runbooks alone.
3. The Safety Officer can reveal the drill at any time if production safety needs it.
4. The failback is planned and run in the same window.
5. This drill also supplies the annual evidence for the incident response test.

## 6. Component drill detail

| Drill | Key steps | Pass criterion |
|---|---|---|
| AZ chaos (M1, M5) | Remove one AZ's nodes; observe HPA, node autoscaling, Aurora reader replacement | Success rate stays above 95% after scale-out; no manual cross-region failover needed. If it is needed, the RB-10 decision rule fires correctly |
| Kafka and outbox (M2, M8) | Degrade MSK; enable outbox bypass; replay from outbox and from the DR cluster | No lost audit event; settlement backlog cleared; replay is idempotent |
| Partner allow-list (M3) | Each partner bank connects to Hyderabad IPs and VPN over BGP | 100% of partners confirm; gaps tracked to closure before the full drill |
| DNS and partition (M4) | Manual health-check override; client switch timing at 10 s TTL; secondary DNS provider; simulated Mumbai-Hyderabad partition with no promotion | Client switch measured; no split-brain; no accidental promotion |
| Cost-optimised capacity (M6) | Run Hyderabad at 25% pre-provisioned compute and test scale to full | Time to full capacity fits the RTO. If not, the cost cut is not locked in |
| KMS and certificates (M7) | Rotate the CDE key; renew certificates in both regions; swap to the standby-CA certificate; run the client TLS matrix | No payment failure; all merchant client types connect |
| WAF switch (full-drill months) | Move the emergency rule group from Count to Block and back | Block takes effect in under the RB-07 target; no legitimate merchants blocked |
| Database corruption (M10) | PITR to a clean cluster, validate data, compare a checksum sample; test S3 restore | Restore completes within the RB-02 target; integrity checks pass |
| Chaos day (M11) | Inject cascading failure, run NPCI outage simulation and the ransomware tabletop | Circuit breakers and bypass rules work; rebuild plan meets its target; communication templates used |
| Sovereignty sweep (M12) | Run the full evidence set from `compliance-matrix.md` Section 8 | Every control evidenced; exceptions logged and closed |

## 7. Metrics tracked

Every drill reports these. The dashboard shows the latest value per drill type.

| Metric | Definition | Target |
|---|---|---|
| Time to detect | Fault start to first alert | Under 30 s |
| Time to decide | Alert to IC failover decision | Under 60 s |
| Time to first successful write | Fault start to first committed payment on the new primary | Under 4 min (P95 under 5 min) |
| Time to fully verified | Fault start to all verification steps passed | Under 6 min nominal; reported separately |
| Data-loss window (RPO) | Seconds of committed writes missing on the new primary | Under 60 s |
| Reconciliation result | Missing and duplicate transactions found | Zero unexplained |
| P99 latency after failover | At the tested load | Under 300 ms (180 ms normal) |
| Runbook accuracy | Steps that needed a change or were skipped | Under 5% of steps |
| Sovereignty check | Resources found outside Indian regions | Zero |
| Findings | Count, severity, closed on time | 90% closed within 30 days for high severity |

## 8. Findings and improvement loop

- Findings are rated High (a pass criterion failed or a safety issue), Medium (runbook wrong or slow) or Low (cosmetic).
- High findings are re-tested at the next drill or in a targeted re-run within 30 days.
- Runbooks are updated within 10 business days of any finding that changes a step.
- The drill results feed the quarterly cost re-forecast (`cost-summary.md`, review cadence) and the active-active upgrade triggers.
- After the first two full drills, rightsizing of the 50% standby compute is reviewed, as stated in the cost summary.

## 9. Effort and resourcing

These are **planning estimates**, not measured values; replace them with actuals after the first quarter.

| Item | Estimate |
|---|---|
| Component drill | About 2-3 person-days of preparation, 3-6 hours of execution with 4-6 people, 1 person-day report |
| Full drill | About 5 person-days of preparation, a 2-hour impact window (about 4 hours with preparation and stand-down) with 12-15 people, 2 person-days report |
| Annual total | Roughly 90-110 person-days, spread across 8 platform engineers plus part-time SEC, COMP, DBA and COMMS |

The load is the reason the plan keeps to one scheduled drill per month. With 8 platform engineers, adding more would reduce time for fixing findings, which is the point of the exercise. Active-active would roughly double the drill scope, as noted in the design comparison.

## 10. Automation

Scripts are in `scripts/`. All of them are **dry run by default** (they print the commands) and change anything only with `--execute` plus a typed confirmation. They have been syntax-checked and linted with ShellCheck, and the failover script was dry-run against stubbed AWS and kubectl commands. **None has been run against a real AWS account**, so rehearse them in staging first.

| Script | Purpose | Drill use |
|---|---|---|
| `scripts/dr-drill/pre-drill-checks.sh` | Replication lag, active alarms, nodes, capacity reservations, health checks, sovereignty baseline | T-1 hour go/no-go |
| `scripts/dr-drill/set-dns-ttl.sh` | Sets the `api.paysecure.in` TTL (10 s before drills, 30 s after) | T-24 hours and after |
| `scripts/dr-drill/run-switchover.sh` | Pre-checks, then planned switchover | Full drill #1 |
| `scripts/dr-drill/inject-fault.sh` | Starts or stops a fault: FIS experiment, or Mumbai health-check inversion (detection and DNS only) | Full drills #2 to #4 |
| `scripts/failover/failover-to-hyderabad.sh` | RB-01 mechanics, planned or unplanned mode | Full drills, real events (IC approval first) |
| `scripts/dr-drill/post-drill-reconcile.sh` | Sovereignty check, lag check, reconciliation job, drill metric | After every drill |
| `scripts/dr-drill/restore-normal.sh` | Un-invert health check, TTL back to 30 s | After every drill |
| `scripts/health-checks/replication-lag-check.sh`, `sovereignty-check.sh`, `tls-client-matrix.sh` | Read-only checks used above and by RB-09 | Continuous and drills |
| `scripts/health-checks/weekly-dr-readiness.sh` | The 12-check weekly run (Section 10a), 52 runs a year | Weekly |

**Not built yet:** the FIS experiment template itself (it needs a stop condition on the P1 payment-success alarm and agreement from the BCRB on what the experiment may touch), and the reconciliation CronJob that `post-drill-reconcile.sh` expects. The drill plan does not assume either exists.

## 10a. Weekly automated verification (52 checks a year)

Every Monday at 06:00 IST an automated readiness run executes (`scripts/health-checks/weekly-dr-readiness.sh`), 52 times a year. Each run contains the 12 checks below and fails as a whole if any check fails. Results are kept for 7 years as audit evidence and shown on the DR readiness dashboard.

| # | Check | Pass condition |
|---|---|---|
| 1 | Aurora global replication lag | Under 500 ms |
| 2 | DynamoDB replication latency, both tables | Under 1,000 ms |
| 3 | MSK Replicator lag | Under 10,000 messages |
| 4 | S3 replication failures | Zero in the last 7 days |
| 5 | Route 53 health checks | Mumbai healthy, Hyderabad healthy, not inverted |
| 6 | Hyderabad nodes ready | At least the baseline count |
| 7 | Capacity reservations | All active |
| 8 | KMS replica keys and Secrets Manager replicas | Enabled, in sync |
| 9 | TLS certificates | At least 30 days to expiry, chain valid in both regions |
| 10 | Data sovereignty | No resources outside ap-south-1 and ap-south-2 |
| 11 | Image signature policy and drift | Policy in Enforce; no drift between regions |
| 12 | Last backup restore test | Within 7 days and successful |

A failing run opens a P2 ticket the same day; three failures in a row go to the BCRB.

## 11. Calendar and governance

- The calendar is approved by the CTO and the BCRB each year and is changed only through the change process.
- Any missed drill is reported to the BCRB with a recovery date.
- Drill reports are kept for 7 years, in line with the evidence retention used in RB-06 and RB-11.
- Quarterly status goes to the BCRB: drills run, RTO and RPO achieved, open findings.
