# Cost Analysis and DR Tier Comparison

Source workbook: `cost-model.xlsx` (sheets: Assumptions, Line Items, Tier Summary, ROI, Sensitivity, Optimisation). All figures below come from that workbook. Money is in crore INR per year (1 crore = 10 million INR).

## 1. Baseline and Method
PaySecure's current infrastructure spend is about **8 crore INR/year** (Company Profile). The brief gives the total but not the split by service, so the workbook uses an **assumed split** across 18 service categories (EKS compute 28%, Aurora 19% including storage, MSK 9%, observability 9%, and so on). This split is an input on the `Line Items` sheet and **must be replaced with real AWS Cost Explorer data** before the numbers are used for budgeting. The method is the same either way:

1. For each service, decide what share of the Mumbai cost is replicated in Hyderabad in each tier (the "DR factor").
2. Incremental DR cost = baseline cost of the service x DR factor.
3. Add DR-only items that have no Mumbai equivalent: inter-region data transfer, Shield Advanced and DR operations.
4. Multiplier = (baseline + incremental) / baseline, and check it against the brief's range for the tier.

Service categories modelled: EKS worker nodes, EKS control plane, Aurora instances, Aurora storage and I/O, DynamoDB, ElastiCache Redis, MSK Kafka, NAT Gateway, ALB and data transfer out, Transit Gateway and PrivateLink, S3, Route 53, KMS and Secrets Manager, WAF/GuardDuty/CloudTrail, CloudWatch, observability stack, PagerDuty and incident tooling, CI/CD and ECR (18 baseline categories), plus inter-region data transfer, Shield Advanced and DR operations (3 DR-only items). That is 21 line items, above the 15 required.

## 2. Tier Results
| Tier | Description | Incremental (cr/yr) | Total (cr/yr) | Multiplier | Brief range | RTO | RPO | Meets mandate? |
|---|---|---|---|---|---|---|---|---|
| Cold standby | Infrastructure as code only; backups copied to Hyderabad | 0.73 | 8.73 | **1.09x** | 1.05-1.1x | 4-24 h | hours to days | No |
| Warm standby | Core services at reduced capacity, databases replicating | 3.18 | 11.18 | **1.40x** | 1.3-1.5x | 15-60 min | minutes | No |
| **Hot standby** | Full data replication, compute 50% pre-provisioned | 4.78 | 12.78 | **1.60x** | 1.6-1.8x | 1-5 min (design 4 min) | about 1 s | **Yes** |
| Active-Active | Both regions serve traffic, each sized for 100% | 8.07 | 16.07 | **2.01x** | 1.8-2.2x | near zero for half the traffic | about 1 s | Yes |

Key observations:
- **Only Hot standby and Active-Active meet the RTO under 5 minutes and RPO under 1 minute mandate.** Cold and Warm are cheaper but non-compliant.
- **Warm standby almost fits the 1.4x board budget (11.18 vs 11.20 crore)**, which makes it tempting, but its 15-60 minute RTO is 3 to 12 times the mandate, so it would still expose PaySecure to fines and licence action.
- **Hot standby is the cheapest compliant tier**, 3.3 crore per year (about 20%) less than Active-Active before counting the extra engineers Active-Active needs.

## 3. Where the Hot Standby Money Goes (4.78 crore/yr)
| Item | Cost (cr/yr) | Share |
|---|---|---|
| EKS worker nodes (50% pre-provisioned) | 1.12 | 23% |
| Aurora instances (2 in Hyderabad) | 0.75 | 16% |
| MSK Kafka (3 brokers pre-provisioned) | 0.36 | 8% |
| Aurora storage and replicated I/O | 0.36 | 8% |
| Inter-region data transfer | 0.33 | 7% |
| Shield Advanced | 0.31 | 6% |
| DR operations | 0.30 | 6% |
| DynamoDB replica capacity | 0.22 | 5% |
| Redis secondary | 0.20 | 4% |
| All other services (WAF, S3, Transit Gateway, observability, CloudWatch and so on) | 0.83 | 17% |
| **Total** | **4.78** | 100% |

Compute and databases account for about half of the DR premium. Data transfer is modelled at 1.2 TB/day of replication traffic (Kafka about 0.6, Aurora about 0.35, DynamoDB about 0.1, S3 about 0.15 TB/day) at an assumed 0.086 USD per GB. Both numbers are inputs and should be verified in the AWS Pricing Calculator.

## 4. Capacity and Reservation Strategy
- **Compute:** Hyderabad runs 12 of the 24 nodes pre-provisioned, using a Compute Savings Plan for the steady baseline and On-Demand Capacity Reservations for the failover increment (otherwise capacity may not be available during a regional event).
- **Databases and cache:** Reserved Instances for the Aurora and ElastiCache nodes that run continuously in both regions.
- **Spot:** only for non-critical workers (reconciliation, notification, audit) in the DR region.
- **Storage:** S3 lifecycle and Intelligent-Tiering for replicated backups and exports.
- **Rightsizing:** re-evaluate after the first two quarterly drills, because real drills show whether 50% standby compute is more or less than needed.

## 5. Response to BCRB Challenge 8 (External Auditor)
*"Your cost model shows a 1.7x increase. The board approved 1.4x. What can you cut while still achieving 99.99% uptime, and what are the risks of the cost-optimised version?"*

Model results: the recommended Hot standby is **1.60x** (12.78 crore) in the base case. The `Optimisation` sheet applies these levers:

| Lever | Saving (cr/yr) | Risk |
|---|---|---|
| Standby compute 50% to 25% | 0.56 | Slower scale-out on failover, adds 1-2 minutes to RTO unless capacity reservations and warm pools are used |
| Compute Savings Plan on remaining DR compute (20%) | 0.11 | Commitment risk |
| 15% of DR compute on Spot (60% discount) | 0.05 | Interruptions, so payment-critical pods stay On-Demand |
| Aurora DR instances 2 to 1 (second added on failover) | 0.37 | Promotion starts with one instance; write capacity must be proven in drills |
| Reserved Instances on DR Aurora and Redis (30%) | 0.17 | Commitment risk |
| S3 lifecycle on DR copies | 0.04 | Retrieval fees |
| DR observability and CloudWatch trimmed | 0.10 | Less history for forensics |
| **Total** | **1.41** | |

Result: incremental cost falls from 4.78 to **3.37 crore**, total **11.37 crore, or 1.42x**, which is still **0.17 crore above the 1.4x budget**. The answer to the auditor is therefore:
1. **Do not cut the data replication stack** (Aurora Global Database, DynamoDB Global Tables, Redis Global Datastore, MSK Replicator, S3 CRR). It is what delivers RPO under 1 minute and is the compliance requirement.
2. The levers above bring cost to about 1.42x without removing capabilities. Closing the last 0.17 crore requires either a 3-year commitment or enterprise discount (about 3-5% on the committed spend), or a board decision to approve 1.45x.
3. **Risks of the cost-optimised version:** RTO rises from about 2:45 to about 3:45-4:45 (still inside the 5-minute mandate but with little or no buffer), less capacity headroom at peak during a failover, less rehearsal data from thinner observability, and Spot interruptions in the standby region. These must be validated in the Month 3 and Month 6 drills before the cut is locked in.
4. **Do not choose Warm standby to hit the budget.** Its 11.18 crore total fits, but its 15-60 minute RTO fails the mandate.

## 6. Active-Active Cost Note
Active-Active costs 16.07 crore (2.01x) in infrastructure plus about 0.75 crore for five extra platform engineers, a total increment of 8.82 crore per year, which is why it is not recommended now (see `docs/02-multi-region-design/comparison-matrix.md`).

## 7. Cost Governance
- **Dashboards:** the Cost Tracking dashboard (daily spend by region, DR utilisation, reserved vs on-demand, projected monthly cost, anomaly alerts).
- **Tags:** Project, Environment, CostCenter, DR-Tier, ManagedBy on every resource.
- **Budgets:** AWS Budgets alert at 80% and 100% of the approved DR budget, with anomaly detection on data transfer.
- **Review cadence:** monthly review against the model, quarterly re-forecast after each full-failover drill.

## 8. Limitations
The service split of the 8 crore baseline, the replication volume and several prices are assumptions (flagged in blue on the `Assumptions` sheet). One-off implementation effort (migration, engineering time to build the DR region) is excluded. Pricing must be re-checked in the AWS Pricing Calculator for ap-south-1 and ap-south-2 before the figures are used in a budget request.
