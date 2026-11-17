# Comparison Matrix - Active-Passive vs Active-Active

Baseline (used in every document): 3.2M transactions/day, 500 crore INR/day (average ~1,562 INR per transaction), peak 1,200 TPS, average ~37 TPS over 24 h, P99 180 ms, 45,000 merchants, 8 crore INR/year infrastructure, 8 platform engineers, 99.92% current uptime, target 99.99% / RPO < 1 min / RTO < 5 min.

## 1. Quantified Comparison (10 dimensions)
| # | Dimension | Active-Passive (hot standby) | Active-Active (merchant-sharded) | Winner |
|---|---|---|---|---|
| 1 | **RTO** | Nominal about 2 min 45 s to first successful write (3 min 25 s fully verified); documented target 4 min; 100% of traffic affected for that period | Region failure: about 50% of merchants see no outage; the other 50% see about 3.5 min (Aurora promotion 60-90 s is still needed). Traffic-weighted impact about 1.75 min | Active-Active |
| 2 | **RPO** | About 1 s (Aurora/DynamoDB lag < 1 s); alert at 500 ms; hard limit 60 s | About 1 s per shard; same replication technology | Tie |
| 3 | **Cost** | About 1.6x = 12.8 crore INR/year (+4.8 crore) | About 2.0x = 16 crore INR/year (+8 crore) | Active-Passive (3.2 crore/year cheaper) |
| 4 | **Complexity** (1-10, 10 = hardest) | 5: one writer, standby management, failover automation | 9: sharding, request forwarding, bidirectional replication, two global DB clusters | Active-Passive |
| 5 | **Data consistency** | Strong (single writer); standby eventually consistent, lag about 1 s | Strong within a shard; cross-shard reads eventually consistent (about 1 s); no multi-writer conflicts by design | Active-Passive (simpler guarantee) |
| 6 | **Latency impact** | 0 ms added; P99 stays 180 ms | About 50% of requests +20-30 ms; worst-case P99 about 210 ms (headroom 90 ms under 300 ms) | Active-Passive |
| 7 | **Operational burden** | 8 engineers, 1-in-4 on-call; drill load of 4 full + 12 component drills per year | 12-14 engineers (+4-6), 1-in-6 on-call; drill scope doubled; about 2x monitoring and patching | Active-Passive |
| 8 | **Regulatory approval** | Simple narrative: one authoritative region, documented DR; fits RBI Master Direction and NPCI 5-minute failover | Needs extra evidence that two live regions cannot double-process; longer audit trail | Active-Passive |
| 9 | **Split-brain risk (CRO view)** | Single writer plus fencing; uncontrolled exposure is zero when procedure is followed | Zero duplicate exposure per merchant by design; the same 3-minute partition would otherwise expose about 1.0 crore INR at average load or 33.7 crore INR at peak | Tie |
| 10 | **Scalability to 1,500 crore INR/day (3x)** | Primary must scale 3x (to about 3,600 TPS peak); standby must also scale; single-writer Aurora is the first bottleneck | Load is split across two writers, so each region scales to about 1.5x of today's volume; clear path to adding a third cell | Active-Active |

**Score:** Active-Passive wins 6 dimensions (cost, complexity, consistency, latency, operations, regulatory). Active-Active wins 2 (RTO, scalability). RPO and split-brain risk are tied.

## 2. Availability Maths
Annual downtime budget at 99.99%: 525,600 min x 0.01% = **52.6 min**.

Assume one regional event per year (a deliberately pessimistic assumption, since AWS regions rarely fail entirely, but zonal events do occur: see Case Study 4).
| | Active-Passive | Active-Active |
|---|---|---|
| Downtime from the regional event | 4 min (RTO target) | About 1.75 min (50% x 3.5 min) |
| Remaining budget for deployments, application faults and partial failures | 48.6 min | 50.9 min |
| Achieved availability, regional event only | 99.9992% | 99.9997% |

Both designs meet the 99.99% target. The extra availability bought by active-active is about 2 minutes per regional event, which is **worth roughly 2 min x 37.5 lakh INR/hour / 60 = about 1.25 lakh INR of revenue** per event. The incremental cost is about 3.2 crore INR/year plus 4-6 engineers. At one event per year the premium is not justified by avoided revenue loss alone; it would be justified only by volume growth, partner demands or regulatory direction (see Section 4).

## 3. Cost Detail (indicative, refined in `docs/06-cost-analysis`)
| Item | Today | Active-Passive | Active-Active |
|---|---|---|---|
| Infrastructure spend | 8.0 crore | 12.8 crore | 16.0 crore |
| Multiple vs today | 1.0x | 1.6x | 2.0x |
| Increase | - | +4.8 crore | +8.0 crore |
| Additional engineers | - | 0 (automation) | +4-6 (about 0.5-0.9 crore at an assumed 12-15 lakh INR loaded cost each) |
| Board-approved budget (1.4x) | 11.2 crore | Over by 1.6 crore | Over by 4.8 crore |

Neither full design fits the 1.4x budget. The cost-reduction path for active-passive (compute at 25% pre-provisioned instead of 50%, spot instances for non-critical workers, Savings Plans, S3 Intelligent-Tiering) is analysed in the cost model and in the BCRB budget-pressure answer.

## 4. Decision Criteria and Triggers
| Question | If yes, prefer |
|---|---|
| Is RTO of about 4 minutes acceptable to the regulator and key partner banks? | Active-Passive |
| Is the platform team 8 engineers or fewer? | Active-Passive |
| Must the budget stay near 1.4x? | Active-Passive |
| Will volume reach 1,500 crore INR/day (3x) within about 2 years? | Plan Active-Active migration |
| Does any partner bank or regulator require sub-minute recovery for most traffic? | Active-Active |
| Is a 12+ engineer platform team funded? | Active-Active possible |

## 5. Final Recommendation
**Adopt active-passive hot standby (Mumbai primary, Hyderabad DR) now, and build it "shard-ready" for a later move to active-active.**

Business justification:
1. **Meets the mandate.** RTO 4 minutes (below 5), RPO about 1 second (below 60 s), 99.99% achievable, all data in India. Active-active gives only about 2 extra minutes of availability per regional event.
2. **Fits the organisation.** The 8-person platform team can sustain active-passive. Active-active needs 4-6 more engineers, and understaffing is the single biggest cause of failed DR in practice (drift, skipped drills, untested runbooks).
3. **Lower financial and compliance risk now.** Cost is 3.2 crore INR per year lower, and the single-writer model is easiest to explain to the RBI, NPCI and the PCI DSS assessor, and removes the risk of dual processing from day one.
4. **Keeps the option open.** Every merchant record carries a `home_region` field from the start (all set to Mumbai), request routing is abstracted behind payment-api, and both regions are sized and deployed by the same IaC. Moving to the merchant-sharded active-active design is then a phased change: enable the second Aurora global cluster, move 50% of merchants to Hyderabad as home, and switch Route 53 to 50/50 weights.
5. **Clear upgrade triggers.** Move to active-active when any of these happen: daily volume passes about 1,000 crore INR (2x), the platform team reaches 12 engineers, a regulator or major bank requires near-zero RTO for most traffic, or measured drill results show real-world RTO above 5 minutes.

## 6. BCRB Challenge Responses (all ten)

The brief lists ten questions the Business Continuity Review Board will ask. Each has a pre-emptive answer here, with the document that holds the full detail.

| # | Challenge (summary) | Answer | Full detail |
|---|---|---|---|
| 1 | CTO: a Mumbai transaction is in flight when the region fails. What happens to it? | The merchant gets a **timeout, never a false success**: success is returned only after the write is committed and the bank or NPCI reference is recorded. The merchant retries with the same idempotency key, and the key store (DynamoDB Global Tables, under 1 s lag) stops a second charge. An unknown-outcome transaction is resolved by checking the bank or NPCI status before anything is reprocessed, and by reconciliation within 1 hour. A customer debit without a recorded success is reversed automatically. | `replication-strategy.md` Section 9.4, `RB-01` |
| 2 | CTO: RTO is documented as 4 minutes but DNS TTL adds delay. Real RTO might be 8-10 minutes. | The design uses a **30 s TTL** on CNAME records (10 s for drills), not 60 s. Detection is 30 s, decision and promotion about 90 s, client cache up to 30 s: nominal about 2 min 45 s to the first write, 3 min 25 s fully verified, documented RTO 4 minutes. The long tail (connection pools, retries) is acknowledged and measured every drill; the success criterion is P95 under 5 minutes. | `dns-failover-design.md` Section 7 |
| 3 | CRO: split-brain for 3 minutes. Maximum exposure? | In an uncontrolled multi-writer design: about 6,700 duplicates (about 1.0 crore INR) at average load, up to 216,000 (about 33.7 crore INR) at peak. In the recommended design the exposure is **effectively zero** because there is a single writer, and in active-active a merchant-sharded home-region rule stops two regions processing one merchant. RB-05 gives the no-promotion rule and the merge and reconciliation procedure. | `active-active-design.md` Section 5.2, `RB-05` |
| 4 | CRO: evening batch settlement triples write IOPS. Does synchronous replication still work? | The design **does not use synchronous replication** for the database. Cross-region replication is asynchronous (Aurora Global Database, about 1 s lag), so write latency is unchanged and the 300 ms NPCI ceiling is safe at triple IOPS. The cost is a bounded RPO equal to the lag (alarm at 500 ms), under the 60 s mandate. | `replication-strategy.md` Sections 2 and 4 |
| 5 | Compliance: where is cardholder data, and does it ever cross a non-Indian path in failover? | Only in the CDE namespace and the Aurora CDE cluster in Mumbai and Hyderabad, KMS-encrypted (AES-256, TLS 1.3). Failover moves clients to Hyderabad; no data is copied to a new place and no non-Indian path exists. Proof: data-flow diagrams, the India-only SCP, and the post-failover sovereignty check. | `data-flow-diagrams.md`, `compliance-matrix.md` |
| 6 | Compliance: PCI assessor visits in Month 5; last drill Month 3, next Month 6. Evidence of DR testing in the last 90 days? | Month 3 to Month 5 is about 60 days, inside 90. The evidence is not only the Month 3 full drill: it includes the Month 4 DNS drill, the Month 5 EKS drill, and the **weekly automated readiness runs** (52 a year), all with signed reports. PCI DSS 12.10.2 (plan tested annually) is met by the four full drills. | `annual-drill-plan.md`, `drill-success-criteria.md` |
| 7 | VP Engineering: is active-active realistic for 8 platform engineers? | No. Eight can run **active-passive** with a 1-in-4 on-call rota. Active-active needs about 12-14 engineers (4-6 more) for a sustainable 1-in-6 rota and doubled drill scope. Upgrade trigger: the team reaches 12 engineers or volume passes about 1,000 crore INR/day. | Section 4 above, `active-active-design.md` |
| 8 | Auditor: 1.7x vs a 1.4x budget. What can you cut and what are the risks? | Hot standby is **1.60x** in the base case. The levers (compute 25% pre-provisioned, spot for non-critical nodes, Savings Plans, right-sizing, fewer DR instances) bring it to **1.42x, 0.17 crore over the 1.4x budget**. Risks: slower scale-out after failover, more spot interruption, thinner capacity. Warm standby fits the budget but misses the RTO and RPO mandate, so it is not an option. | `cost-summary.md` |
| 9 | Board Chair: top 3 risks and what would you do with unlimited budget? | (1) **Silent standby rot**: replication lag, drift or an unready DR region that nobody notices. Unlimited budget: continuous automated failover testing and a third Indian region. (2) **Operator error under stress** with a small team. Budget: more engineers, a decision engine, and 24x7 follow-the-sun. (3) **Correlated failure**: a bad release or a shared control plane (DNS, IAM, KMS) hitting both regions at once. Budget: staged rollouts with automatic rollback, independent DNS, and a multi-cloud tier. | `current-architecture.md` FMEA |
| 10 | Board Chair: volume triples to 1,500 crore INR/day. Redesign needed? | No fundamental redesign, but a planned step: peak about 3,600 TPS, so the **single Aurora writer is the first bottleneck**, then MSK throughput, Redis shards and Hyderabad capacity. Plan: scale vertically and add shards now; move to active-active (merchant-sharded) when volume passes about 1,000 crore INR/day. | Section 1, dimension 10; `active-active-design.md` |
