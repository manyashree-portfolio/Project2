# Disaster Scenario Runbooks - Conventions

Twelve runbooks, one per mandatory scenario, all in the same ten-section order:
1 Scenario Identification, 2 Detection Mechanism, 3 Impact Assessment, 4 Immediate Response (0-2 min), 5 Diagnostic Steps (2-5 min), 6 Failover/Recovery Procedure, 7 Communication Protocol, 8 Verification and Validation, 9 Rollback Procedure, 10 Post-Incident Review.

| ID | Scenario | Category | Severity | File |
|---|---|---|---|---|
| RB-01 | Complete primary region failure | Infrastructure | P1 | RB-01-region-failure.md |
| RB-02 | Database corruption | Data | P1 | RB-02-database-corruption.md |
| RB-03 | DNS poisoning / DNS infrastructure failure | Security | P2 | RB-03-dns-poisoning.md |
| RB-04 | Kafka cluster failure | Infrastructure | P2 | RB-04-kafka-failure.md |
| RB-05 | Network partition between regions | Infrastructure | P1 | RB-05-network-partition.md |
| RB-06 | Cryptographic key compromise | Security | P1 | RB-06-key-compromise.md |
| RB-07 | DDoS attack on payment API | Security | P2 | RB-07-ddos-attack.md |
| RB-08 | Third-party payment network outage (NPCI/UPI) | External | P3 | RB-08-npci-outage.md |
| RB-09 | Certificate expiry / TLS failure | Infrastructure | P2 | RB-09-certificate-expiry.md |
| RB-10 | Data centre power failure (single AZ) | Infrastructure | P3 | RB-10-az-power-failure.md |
| RB-11 | Ransomware attack on infrastructure | Security | P1 | RB-11-ransomware.md |
| RB-12 | Cascading microservice failure | Application | P2 | RB-12-cascading-failure.md |

## Baseline numbers (identical in every runbook)
| Item | Value |
|---|---|
| Daily transactions / value | 3.2 million / 500 crore INR (average about 1,562 INR each) |
| Peak TPS / average TPS | 1,200 / about 37 over 24 h (about 250 in business hours) |
| Revenue per hour | about 37.5 lakh INR (about 62,500 INR per minute) |
| Transaction value per hour | about 20.83 crore INR (about 34.7 lakh INR per minute) |
| Merchants | 45,000 |
| P99 latency / NPCI ceiling | 180 ms / 300 ms |
| RPO / RTO targets | < 60 s / documented 4 min (mandate < 5 min) |

## Named resources used in commands
Replace `ACCOUNT` with the AWS account ID. Mumbai = `ap-south-1`, Hyderabad = `ap-south-2`.

| Resource | Mumbai | Hyderabad |
|---|---|---|
| Aurora global cluster | `paysecure-global` (global) | |
| Aurora cluster | `paysecure-primary` | `paysecure-secondary` |
| EKS cluster / kubectl context | `paysecure-primary` | `paysecure-dr` |
| EKS node group | `app-ng` | `app-ng` |
| ElastiCache global group | `paysecure-redis-global` | |
| ElastiCache replication group | `paysecure-redis-mum` | `paysecure-redis-hyd` |
| MSK cluster / replicator | `paysecure-prod` | `paysecure-dr`, replicator `paysecure-replicator` |
| DynamoDB tables | `paysecure-idempotency`, `paysecure-sessions` (Global Tables, replica in Hyderabad) | |
| Route 53 hosted zone | `Z1234567890` | |
| Route 53 health checks | `HC-MUM-CALCULATED`, `HC-HYD-LIVE` | |
| KMS multi-Region key alias | `alias/paysecure-cde` | replica key, same alias |
| Namespaces | `paysecure`, `paysecure-cde` | |

## Roles
| Role | Short name | Responsibility |
|---|---|---|
| Incident Commander | IC | Owns decisions, approves failover, runs the war room |
| Primary On-Call SRE | SRE-1 | Executes infrastructure steps |
| Secondary On-Call SRE | SRE-2 | Second pair of hands, runs verification |
| DBA on rotation | DBA | Aurora, DynamoDB, data integrity |
| Network Engineer | NET | Transit Gateway, VPN, DNS |
| Data/Streaming Engineer | DATA | Kafka, MSK Replicator, reconciliation |
| Security Lead | SEC | KMS, IAM, forensics, CERT-In |
| Communications Lead | COMMS | Merchant, partner, regulator notices |
| Compliance Officer | COMP | RBI, NPCI, PCI DSS notifications |

## Standard rules
1. Every step has a role, a time estimate and a verification. Times are based on documented AWS behaviour and the DR design timings.
2. A step that fails its verification is repeated once, then the Incident Commander is asked to take the decision-tree branch marked "if failed".
3. All times are IST. The incident timeline is recorded in the incident channel and in the PagerDuty incident.
4. Out-of-band communication (phone tree, SMS, pre-configured bridge) is used if Slack or email is unavailable.
5. No step uses "contact AWS support" as its only action. Support cases are opened in parallel, never as a substitute.

## Standard communication templates
Each runbook fills in these templates with scenario values.

**Internal engineering:** `Subject: [P{severity}] {scenario_name} - Incident #{incident_id}. Status: {Detected|Investigating|Mitigating|Resolved}. Impact: {description_of_impact}. Affected components: {list}. Current actions: {what_is_being_done}. ETA: {estimated_time}. IC: {name}. War room: {link_or_phone}.`

**Management:** `PaySecure incident {incident_id}: {scenario_name}. Customer impact: {impact}. Estimated revenue at risk: {amount} lakh INR/hour. Regulatory exposure: {yes_no}. Decision needed: {decision}. Next update at {time}.`

**Merchant:** `Subject: PaySecure Service Advisory - {date}. Dear Merchant Partner, we are currently experiencing {brief_description_of_impact}. Payment methods affected: {list}. Operational: {list}. Estimated restoration: {time}. Please retry failed payments using the same idempotency key. Updates every {frequency}. Support: {support_number}.`

**Regulator:** `To: {Regulator_Name}. From: PaySecure Gateway Private Limited (PPA licence: {number}). Subject: Mandatory Incident Report - {date}. Classification: {P1/P2/P3}. Time of detection: {timestamp_IST}. Nature: {description}. Impact: {quantified_impact}. Remediation: {actions_taken}. Status: {status}. Preliminary root cause: {if_known}. Estimated full resolution: {time}. Contact: {CISO_name}, {phone}, {email}.`
