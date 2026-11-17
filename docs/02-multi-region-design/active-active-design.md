# Active-Active Multi-Region Design - PaySecure Gateway

## 1. Purpose
This document specifies the **active-active** alternative to the active-passive design (`active-passive-design.md`). In this configuration both Mumbai (ap-south-1) and Hyderabad (ap-south-2) serve live production traffic at all times, so the loss of a region removes one traffic destination instead of requiring a full failover. The requirements are unchanged: 99.99% uptime, RPO < 1 minute, RTO < 5 minutes, all payment data stored in India, and P99 latency under the 300 ms NPCI ceiling (current P99 is 180 ms).

The central difficulty of active-active for a payment system is that two regions must never process the same money movement independently. The design therefore starts from the data problem and works outward.

## 2. Design Principle: Merchant-Sharded Active-Active
Fully symmetric multi-writer replication (any region writes any record) is not offered for Aurora PostgreSQL, and last-writer-wins conflict resolution is unsafe for balances, settlement batches and idempotency keys. The chosen design is instead **merchant-sharded ("home region") active-active**:

- Every merchant is assigned a **home region** at onboarding: Shard A (about 50% of merchants and volume) is homed in Mumbai, Shard B (the other 50%) is homed in Hyderabad. The assignment is a field in the merchant configuration, replicated to both regions.
- **All writes for a merchant happen only in its home region.** There is always exactly one writer per merchant, so there are no write-write conflicts, no double spending, and no need for conflict-resolution logic on financial data.
- **Both regions accept incoming traffic.** If a request lands in the non-home region, the receiving region's payment-api forwards it over the Transit Gateway to the home region (adding one inter-region round trip).
- **Each region is also the DR target for the other shard.** Shard A data is replicated to Hyderabad, and Shard B data to Mumbai, so each region holds a complete, current copy of all data.

This is a cell-based architecture: two cells, each authoritative for half of the merchants, each capable of taking over the other.

## 3. Traffic Routing
- **DNS:** Route 53 weighted routing (50/50) with health checks (10-second interval, 3 failures, so 30 seconds minimum detection) and a record TTL of 30 seconds. Latency-based routing was rejected because most clients are nearer Mumbai, which would leave Hyderabad under-used and untested, and would make Mumbai a de facto primary again.
- **Request flow, home region:** About half of all requests land in the merchant's home region and are processed locally with no added latency (P99 180 ms).
- **Request flow, non-home region:** The other half land in the other region. payment-api reads the merchant's `home_region` from the locally cached configuration, then forwards the request over Transit Gateway to the home region's payment-api. Added latency is one RTT (15-25 ms) plus about 5 ms of forwarding overhead, so worst-case P99 is about 180 + 25 + 5 = **210 ms**, which leaves 90 ms of headroom under 300 ms.
- **Idempotency:** The `Idempotency-Key` plus merchant ID is always checked and written in the home region, whichever region received the request. A retry from the same merchant that lands in the other region is forwarded to the same place, so the duplicate is detected.

## 4. Component Design
| Component | Active-active mechanism | Write rule | Lag | Notes |
|---|---|---|---|---|
| Aurora PostgreSQL | **Two Aurora Global Databases**: Cluster A (primary Mumbai, secondary Hyderabad) and Cluster B (primary Hyderabad, secondary Mumbai) | Shard A writes go to Cluster A in Mumbai; Shard B writes go to Cluster B in Hyderabad | < 1 s | Two independent global clusters, so each region has one writer and one read-only replica of the other shard. Cross-shard reads (for example the merchant portal) use the local replica |
| DynamoDB | Global Tables across both regions | Idempotency and session writes happen in the merchant's home region only (key = merchantId#idempotencyKey) | < 1 s | Because only one region ever writes a given key, last-writer-wins never has to resolve a real conflict. The replica gives a ready copy on failover |
| ElastiCache Redis | **Independent regional clusters** | Local reads and writes | None (no replication of counters) | Rate-limit counters are per region with half of each merchant's quota in each region. Merchant config cache is rebuilt from the database. Global Datastore is not used because it allows a writer in only one region |
| MSK Kafka | One MSK cluster per region plus **MSK Replicator in both directions** with region-prefixed topics (for example `mum.txn-events`, `hyd.txn-events`) | Services publish to their local cluster; topic names are prefixed to prevent replication loops | Seconds | Each region processes events for its own shard. The replicated topics let the other region take over without data loss |
| S3 | Bidirectional Cross-Region Replication | Distinct key prefixes per home region (`a/`, `b/`), so no object is written in both regions | Seconds (RTC 15 min SLA) | Versioning enabled on all buckets |
| KMS / Secrets Manager | Multi-Region keys and replicated secrets | Primary in Mumbai, replica in Hyderabad | Seconds | Same as the active-passive design |

**Why two Aurora global clusters and not one.** Aurora PostgreSQL global databases have a single writing region. Running two global clusters with opposite primaries gives each region a real writer, gives each shard a cross-region replica for DR, and avoids multi-master features that are not available or not proven for this engine. Where write forwarding is available for a given engine version, it was deliberately not relied on: it adds the cross-region round trip to every write and is asynchronous, so it neither removes the latency cost nor makes RPO zero. Engine feature availability must be re-verified against current AWS documentation before implementation.

## 5. Behaviour Under Failure
### 5.1 Whole-region failure (for example Mumbai)
| Time | Event |
|---|---|
| 0:00 | Mumbai fails. Shard B merchants (homed in Hyderabad) are unaffected, as 50% of traffic continues normally |
| 0:30 | Route 53 health checks fail 3 times; Mumbai is removed from DNS |
| 0:45 | Automated decision: promote Hyderabad to be the writer for Shard A (Cluster A) |
| 0:45-2:15 | Aurora global failover of Cluster A to Hyderabad: 60-90 s |
| 2:15 | Hyderabad serves Shard A merchants. DynamoDB replica is already writable |
| 2:45 | DNS TTL (30 s) has expired for clients, so all traffic now reaches Hyderabad |
| 3:30 | Verification: synthetic transactions, error rate, Kafka consumer lag |

- **Shard B merchants (about 50%) see no outage.** Their writes continue in Hyderabad throughout.
- **Shard A merchants (about 50%) see about 2.5-3.5 minutes** of failed or timed-out requests, the same promotion cost as active-passive. Retries after promotion succeed because idempotency keys are replicated.
- **Capacity requirement:** Hyderabad must absorb 100% of the load, so both regions are provisioned at full production size (24 nodes each). This is the main cost driver of active-active.
- Expected annual downtime impact for one regional event: roughly 50% x 3.5 min = about 1.75 minutes of whole-platform-equivalent downtime, versus about 4 minutes for active-passive.

### 5.2 Network partition between regions (split-brain)
Each region continues to serve its own shard because writes are strictly region-local. Requests that need cross-region forwarding fail with a 503 and a retry hint. The decision rules:
1. **Do not promote either region** during a partition unless the Incident Commander confirms from an independent vantage point (an external probe plus a Singapore-hosted monitor) that the peer region is actually down. Promotion while the peer is alive would create two writers for one shard, which is split-brain.
2. If the partition lasts more than 5 minutes, Route 53 weights are shifted so that each region receives only requests for which it is the home region (using per-merchant hostnames for large merchants and request retries for the rest).
3. When connectivity returns, replication resumes automatically and lag drains. No merge of financial data is necessary because no record had two writers.

**Financial exposure comparison.** Average transaction value is about 1,562 INR (500 crore / 3.2 million). In an *uncontrolled* multi-writer design, a 3-minute (180 s) split-brain at average load (about 37 TPS) could duplicate up to about 6,700 transactions, roughly 1.0 crore INR; at peak load (1,200 TPS) up to 216,000 transactions, roughly 33.7 crore INR. In the merchant-sharded design the duplicate-processing exposure for a single merchant is effectively zero, because the home-region rule means two regions cannot independently process one merchant's payment. The residual risk is a request lost to the partition (not duplicated), which merchants retry with the same idempotency key.

### 5.3 Single-AZ failure
Identical to the single-region design: EKS reschedules pods, Aurora fails over inside the region (roughly 30-60 s), and MSK continues on remaining brokers. No cross-region action is needed, and since each region has 100% capacity, an AZ loss does not threaten capacity.

## 6. Idempotency and Ordering
- **Ordering:** Transactions for one merchant are always processed in one region, so per-merchant ordering is preserved. There is no global ordering across merchants, and none is required.
- **Idempotency key sharing:** The key lives in DynamoDB and is replicated to the other region within about 1 second. During failover, a retry arriving in the new home region finds the replicated key. Keys that were written inside the last second before the failure may be missing, which is handled by transaction reconciliation using the bank reference IDs.
- **Settlement:** Each region's settlement-engine settles only its own shard's transactions. A reconciliation job in both regions compares settlement batches against the replicated transaction ledgers every 15 minutes and flags mismatches.

## 7. Network Architecture
- Non-overlapping VPCs (10.0.0.0/16 and 10.1.0.0/16), three AZs each.
- Transit Gateway inter-region peering carries both replication and forwarded requests over the AWS backbone, encrypted, entirely within India.
- Forwarded requests are authenticated with Istio mTLS and a short-lived internal token, and each forwarded request carries the original trace ID so Jaeger shows a single trace across regions.
- Identical ALB + WAF rules in both regions from the same Terraform modules. Partner bank VPNs terminate in both regions.

## 8. Operational Impact
- **Two production regions** means two sets of on-call alerts, patching, capacity planning and certificate management. Monitoring volume roughly doubles (about 2,400 metrics and 350 alerts per region).
- **Deployments:** Every release goes to two live regions. Use a canary in one region first, then the other, with automated rollback.
- **Team size:** About 8 platform engineers can run the active-passive design with a 1-in-4 on-call rota. Active-active needs about 12-14 engineers (4-6 more) to keep a sustainable 1-in-6 rota, a 24x7 follow-the-sun handover for incidents, and time for drills and drift management.
- **Testing:** A failure of either region must be drilled, so the drill plan has to be doubled in scope.

## 9. Cost Estimate
Both regions run full-size compute and databases, because each must carry 100% of traffic when the other fails. Estimated infrastructure cost is about **2.0x** current spend, around **16 crore INR/year** (an increase of about 8 crore), plus 4-6 additional engineers. This sits within the 1.8-2.2x range for the active-active tier and exceeds both the 1.4x board-approved budget (11.2 crore) and the active-passive estimate (about 12.8 crore).

## 10. Regulatory Considerations
- **RBI Master Direction:** DR requirement (RTO < 4 hours, near-zero RPO) is satisfied by both designs.
- **NPCI:** Automated failover within 5 minutes is satisfied. The 99.95% uptime requirement is exceeded.
- **Data localisation:** Both regions are in India, so every replica is compliant. No cardholder data crosses a border.
- **Additional justification needed:** Regulators and the PCI DSS assessor will ask for evidence that two regions processing live transactions cannot create duplicate or inconsistent records. The home-region rule, idempotency design and reconciliation process give that evidence, but the narrative is longer and harder to audit than a single-writer design.

## 11. Strengths and Weaknesses
| Strengths | Weaknesses |
|---|---|
| About 50% of merchants see no outage in a regional failure | Same promotion time for the failed region's shard (about 3.5 min) |
| Both regions are continuously proven by real traffic, so the standby is never "cold" | About 2.0x infrastructure cost plus 4-6 more engineers |
| Spreads load, easing festival peaks (1,200 TPS peak split in two) | Cross-region forwarding adds 20-30 ms to about half of requests |
| Natural path to scale volume 3x | Highest operational complexity and audit burden |

## 12. When to Choose Active-Active
Active-active is recommended if (a) transaction volume triples (to about 1,500 crore INR/day), where a single active region approaches its scaling ceiling, (b) the regulator or a major bank partner requires sub-minute recovery for a majority of traffic, and (c) the platform team has grown to 12 or more engineers. Until those conditions hold, the active-passive design is the recommended starting point (see `comparison-matrix.md`). Because merchants already carry a `home_region` field in the data model, the active-passive system can be built "shard-ready", so migrating to active-active later is a configuration and capacity change rather than a redesign.
