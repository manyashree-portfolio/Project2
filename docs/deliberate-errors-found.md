# Deliberate Errors Found in the Project Brief

The project brief (Appendix E) contains deliberate errors and asks for each to be documented with: **(a)** what the error is, **(b)** where it appears, **(c)** the correct information with a reference source, and **(d)** the impact on the architecture if the error were propagated.

The brief does not say which statements are the planted ones. This file therefore lists **five primary findings**, the ones that could be checked against a public source or against another part of the brief itself and found wrong, followed by **additional discrepancies** with a confidence rating. Page numbers refer to the PDF of the brief. Sources were checked on 7 November 2026.

## Summary

| # | Error in the brief | Where (page) | Type | Confidence |
|---|---|---|---|---|
| 1 | Visa European outage dated **2019** | A1.1 (p3), contradicts Case Study 1 (p36) | Wrong date | High |
| 2 | HDFC Bank outage dated **December 2023**, lasting 48 hours, caused by a software upgrade | A1.1 (p3), Case Study 3 (p37), synthesis table (p38) | Wrong date and cause | High |
| 3 | Average TPS during business hours shown as **~250** | B6 simulation data table (p31) | Arithmetic | High |
| 4 | Regulatory fine ceiling given as **5 crore INR** | Executive Summary (p2), A1.2 table (p4); contradicts B1 (p24) and Deliverable 5 (p50) | Internal inconsistency | High |
| 5 | **"PCI DSS 72-hour notification"** | Scenario 6 (p35), complexity table (p39) | Wrong requirement | Medium-high |

## Finding 1 - Visa European outage: wrong year

- **(a) The error:** Section A1.1 refers to "the **2019** Visa European outage that affected millions of transactions for over 10 hours".
- **(b) Where:** A1.1, page 3. Case Study 1 on page 36 correctly says "June 2018".
- **(c) Correct information:** the outage began at 14:35 BST on **1 June 2018**, lasted about 10 hours, and 5.2 million transactions failed to process correctly out of about 51.2 million attempted. Visa explained in a letter to the UK Treasury Select Committee that a partial failure of a switch in its primary data centre stopped the backup switch from activating. Sources: Visa Europe CEO's letter to the Treasury Committee as reported by Finextra, The Register and Computer Weekly (June 2018).
- **(d) Impact if propagated:** a wrong date breaks traceability of the case study and undermines credibility with a Compliance Head or auditor who checks the reference. The lesson is also about a partial failure that defeated an automatic failover, which is why this design tests failover by fault injection and does not rely on graceful switchover alone (`docs/08-dr-drill-plan`).

## Finding 2 - HDFC Bank outage: wrong date and wrong cause

- **(a) The error:** the brief says HDFC Bank had a "48-hour internet banking outage" in **December 2023**, "caused by a complex interaction between a software upgrade and legacy infrastructure", and A1.1 says "the **2023** HDFC Bank internet banking outage that lasted 48 hours and drew RBI censure".
- **(b) Where:** A1.1 (p3), Case Study 3 (p37), the cross-case table (p38: "HDFC Bank 2023 ... 48 hours ... upgrade + legacy").
- **(c) Correct information:** the event that led to RBI action was the **21 November 2020** outage of HDFC Bank's internet banking and payment systems, caused by a **power failure in the primary data centre**. On **2 December 2020** the RBI ordered the bank to stop launches under its Digital 2.0 programme and to stop sourcing new credit card customers. The card ban was lifted in August 2021 and the digital restrictions in March 2022. The "two-day outage" belongs to December 2019 (a technical glitch), and a week-long mobile app outage to December 2018. Sources: HDFC Bank stock exchange filing of 3 December 2020 as reported by PTI and BOOM; Business Standard (22 January 2021); Outlook Business (12 March 2022).
- **(d) Impact if propagated:** the real root cause (primary data centre power failure with weak recovery) is a direct argument for this project's AZ and region designs (RB-10, RB-01). A software-upgrade story would send the reader to change management instead. A wrong year also makes the "RBI is acting against outages now" argument look more recent than it is.

## Finding 3 - Average TPS: arithmetic error

- **(a) The error:** the simulation data table gives "Average TPS (business hours) **~250 TPS**, derived: 3.2M / 16 hrs / 3,600 s".
- **(b) Where:** Section B6, page 31.
- **(c) Correct information:** 3,200,000 / (16 x 3,600) = **55.6 TPS**. Averaged over 24 hours it is 3,200,000 / 86,400 = **37 TPS**. Peak is about 1,200 TPS, so peak is about 32 times the 24-hour average. A figure of 250 would need about 14.4 million transactions a day.
- **(d) Impact if propagated:** monitoring baselines, capacity planning and alert thresholds would be set 4.5 times too high, so a real traffic drop would not alarm. The same table says inconsistent figures bring a coherence penalty. This repository uses 37 TPS (24-hour average) and notes about 56 TPS for a 16-hour business day.

## Finding 4 - Regulatory fine ceiling: 5 crore versus 2 crore

- **(a) The error:** the brief states the penalty for non-compliance as "fines up to **5 crore INR**" (Executive Summary; A1.2 table, RBI Master Direction row) but "a fine of up to **2 crore INR**" in B1 and "50 lakh to **2 crore** for P1 incidents" in Deliverable 5.
- **(b) Where:** page 2 and page 4 (5 crore) versus page 24 and page 50 (2 crore).
- **(c) Correct information:** within the brief's own figures the ceiling is **2 crore INR**, and that is the figure used in the ROI model (midpoint 1.25 crore of the 50 lakh to 2 crore range). The brief does not name a legal provision for either number, so the reference source is the brief's own Part D and Part B. The statutory penalties for payment system operators sit in the Payment and Settlement Systems Act, 2007 and should be confirmed by Compliance before any figure is shown to a board.
- **(d) Impact if propagated:** the expected regulatory loss in the ROI model would be overstated by 2.5 times at the ceiling, which would make DR look more attractive than it is and give the auditor an easy challenge to every cost line.

## Finding 5 - "PCI DSS 72-hour notification"

- **(a) The error:** Scenario 6 says the runbook must address "**PCI DSS 72-hour notification**", and the complexity table lists "Yes (PCI DSS 72-hour, RBI)".
- **(b) Where:** Part C Scenario 6 (p35) and the complexity classification table (p39).
- **(c) Correct information:** PCI DSS v4.0 Requirement 12.10 requires an incident response plan with notification procedures but **sets no universal 72-hour deadline**. The 72-hour rule is in GDPR Article 33 (and in India it is not the PCI standard). Notification times for card incidents come from each card brand's rules through the acquirer: many require notice immediately or within 24 hours, and American Express's data security rules say immediately and no later than 72 hours after discovery. In India the deadlines that apply to a payment aggregator are CERT-In's 6 hours and the RBI's incident reporting timelines. Sources: PCI DSS v4.0 Req. 12.10; American Express Data Security Operating Policy (October 2020); CERT-In directions of 28 April 2022.
- **(d) Impact if propagated:** a runbook that treats 72 hours as the deadline would notify the acquirer and the card networks too late for brands that expect immediate notice, and would hide the shorter 6-hour CERT-In clock. RB-06 therefore starts the acquirer notification immediately and uses 72 hours only as the outer limit for the card brand that states it.

## Additional discrepancies

These are weaker or could not be fully verified. They are recorded so that nothing found is left out.

| # | Statement in the brief | Where | Problem | Confidence |
|---|---|---|---|---|
| 6 | "Case Study 4: AWS ap-south-1 Power Event (April 2021)", about 3 hours, "cross-region DR customers entirely unaffected" | p37 | No matching ap-south-1 event could be found in public AWS incident histories; the only Mumbai-region item found was an internet connectivity event on 24 December 2021. The paragraph is also **duplicated** word for word, and the cross-case table repeats the claim. Treat as unverified and do not cite it. | Medium |
| 7 | "RBI Master Direction on Payment Systems (2024): mandatory DR site with RTO < 4 hours for Tier-1 processors; fines up to 5 crore" | p4, p62 | No direction of that name or "Tier-1 processor" RTO figure could be found. Real, checkable instruments are the RBI 2018 storage circular, the 2024 cyber resilience directions for non-bank payment system operators, and the 2025 Payment Aggregator Directions. The 4-hour figure is carried through this repository as brief-sourced and unverified. | Medium |
| 8 | "RBI Data Localisation Circular (2018, updated 2023)" | p4 | The circular is dated 6 April 2018; RBI's FAQs were updated on 26 June 2019. No 2023 update was found. The 24-hour return rule is correct. | Low-medium |
| 9 | "SEBI Circular on Technology Risk Management ... DR drill at least twice annually" | p4, p17, p54, p57 | SEBI regulates securities markets, not payment aggregators. The drill frequency does not bind PaySecure. The design follows the brief's quarterly full and monthly component drills regardless. | Medium |
| 10 | Aurora Global Database "Eventual (async) or RPO=0 (sync forwarding)" | p10 | Aurora Global Database replicates asynchronously. Write forwarding sends writes from a secondary to the primary; it is not synchronous replication and does not give RPO=0. RPO can be managed (`rds.global_db_rpo`) but not set to zero. | Medium |
| 11 | Terraform sample A.2: `aws_rds_global_cluster.source_db_cluster_identifier = aws_rds_cluster.primary.arn` while `aws_rds_cluster.primary.global_cluster_identifier = aws_rds_global_cluster.paysecure.id` | p59 | Circular dependency: Terraform cannot plan it. It also passes `master_password` as a variable. This repository creates the global cluster first and attaches the primary, with a managed master password. | Medium |
| 12 | Kubernetes sample B.1 uses image `ecr.aws/paysecure/payment-api:latest` | p61 | `:latest` is not reproducible and defeats the signed-image policy; ECR hosts are `ACCOUNT.dkr.ecr.REGION.amazonaws.com`. | Low-medium |
| 13 | Active-passive cost "~1.3-1.6x" (A3.1) versus Hot standby "1.6-1.8x" and Warm "1.3-1.5x" (Deliverable 5) | p8, p49 | The ranges do not line up with the tier definitions. This repository reports tier multipliers inside the Deliverable 5 ranges. | Low |
| 14 | Day plan: "Day 4-6" active-passive and "Day 5-8" active-active | p43 | The day ranges overlap. | Low |
| 15 | Drill plan: "4 full-failover drills ... 12 component drills (monthly)" but the table lists 12 months with 4 full and 8 component drills | p50-51 | Counts do not match. The plan here schedules one scheduled component drill per month plus a full drill in the quarterly months. | Low |
| 16 | Appendix F.4 comment "Check consumer group lag in DR cluster" over a command that returns cluster state | p67 | The command does not show lag. | Low |
| 17 | Scenario 4: "ZooKeeper quorum loss" on MSK | p35 | MSK manages the metadata layer (ZooKeeper or KRaft depending on version) and does not expose quorum loss to the customer in this way. | Low |

## How this repository handles these points

- Uses 37 TPS (24-hour) and about 56 TPS (16-hour business day) as averages; peak 1,200 TPS.
- Uses the 2 crore ceiling (50 lakh to 2 crore, midpoint 1.25 crore) in the ROI model.
- Treats card-network notification as immediate, with 72 hours only as the outer limit for brands that say so; CERT-In 6 hours throughout.
- Marks the RBI 4-hour RTO figure and the NPCI circular numbers as brief-sourced and unverified in the compliance matrix.
- Does not cite the AWS April 2021 case study as evidence.
