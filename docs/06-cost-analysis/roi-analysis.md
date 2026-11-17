# ROI Analysis: DR Investment vs Downtime Losses

Source: `cost-model.xlsx` sheets `ROI` and `Sensitivity`. Figures are crore INR per year unless stated. All inputs are on the `Assumptions` sheet and can be changed.

## 1. What Is Compared
For each DR tier the model estimates **expected annual downtime**, converts it to **expected annual loss**, compares it with today's loss (7 hours of downtime, 99.92% uptime), and divides the loss avoided less the running cost by the running cost to get ROI.

**Downtime model.** Today's 7 hours is split into (a) 0.5 hours of downtime that DR cannot fix (application-level incidents, assumed to remain after the circuit-breaker, canary and rollback improvements in RB-02 and RB-12) and (b) 2 regional or infrastructure events per year averaging 3.25 hours each. With DR, each event lasts MIN(tier RTO, 3.25 hours) instead of 3.25 hours:

| Tier | RTO used | Downtime per event | Annual downtime | Uptime | Meets 99.99%? |
|---|---|---|---|---|---|
| No DR (today) | n/a | 3.25 h | 7.00 h | 99.920% | No |
| Cold | 8 h | 3.25 h (waiting for repair is faster than a cold rebuild) | 7.00 h | 99.920% | No |
| Warm | 30 min | 0.50 h | 1.50 h | 99.983% | No |
| Hot | 4 min | 0.067 h | 0.63 h (38 min) | 99.993% | **Yes** |
| Active-Active | 1.75 min weighted | 0.029 h | 0.56 h (34 min) | 99.994% | **Yes** |

The annual downtime budget for 99.99% is 52.6 minutes, so Hot standby leaves about 15 minutes of headroom for everything else. This is tight and depends on the 0.5-hour assumption for non-DR downtime. Cold standby shows **no benefit** because a 4-24 hour cold rebuild is slower than the typical outage it would be meant to replace.

## 2. Loss Components
Revenue per hour is 0.375 crore INR (37.5 lakh) = 500 crore x 1.8% / 24 (brief, section B6). Components:

| Component | How it is calculated | Brief reference |
|---|---|---|
| Direct revenue loss | downtime hours x 0.375 crore | Revenue per hour |
| Merchant compensation (SLA credits) | 25% of direct loss (assumption) | "merchant compensation (SLA credits)" |
| Regulatory fines | If uptime is below 99.99%: 60% probability x 1.25 crore (midpoint of 50 lakh to 2 crore for P1 incidents) | "regulatory fines (50 lakh to 2 crore for P1 incidents)" |
| Reputational / merchant churn | 1.0x the direct loss (assumption) | "reputational cost (merchant churn)" |
| Operational recovery | events x engineer-hours x 3,000 INR/hour. 500 hours per event without DR, 300 warm, 100 hot, 50 active-active (assumption) | "operational recovery cost (500+ engineer-hours at 3,000/hour)" |

## 3. Results
| Measure (cr/yr) | No DR | Cold | Warm | **Hot** | Active-Active |
|---|---|---|---|---|---|
| Direct revenue loss | 2.63 | 2.63 | 0.56 | 0.24 | 0.21 |
| SLA credits | 0.66 | 0.66 | 0.14 | 0.06 | 0.05 |
| Reputational / churn | 2.63 | 2.63 | 0.56 | 0.24 | 0.21 |
| Expected fines | 0.75 | 0.75 | 0.75 | 0.00 | 0.00 |
| Recovery effort | 0.30 | 0.30 | 0.18 | 0.06 | 0.03 |
| **Total expected loss** | **6.96** | 6.96 | 2.20 | **0.59** | 0.50 |
| **Loss avoided vs today** | - | 0.00 | 4.76 | **6.36** | 6.46 |
| Incremental infrastructure cost | - | 0.73 | 3.18 | **4.78** | 8.07 |
| Extra engineers (5 at 15 lakh each for Active-Active) | - | 0.00 | 0.00 | 0.00 | 0.75 |
| **Total incremental cost** | - | 0.73 | 3.18 | **4.78** | 8.82 |
| **Net annual benefit** | - | (0.73) | 1.58 | **1.59** | (2.36) |
| **ROI** | - | -100% | 50% | **33%** | -27% |
| Payback on running cost | - | never | 8.0 months | **9.0 months** | 16.4 months |

## 4. Interpretation
1. **Hot standby pays back in about 9 months** on running cost (loss avoided 6.36 crore against 4.78 crore of cost, net benefit 1.59 crore per year, ROI 33%).
2. **Warm standby has a higher raw ROI (50%) but is not a valid option.** Its 30-minute RTO exceeds the 5-minute mandate, it still misses 99.99% (so the expected fine remains), and it does not satisfy NPCI's 5-minute automated failover requirement. A cheaper option that does not meet the regulatory mandate is not an option, it is a compliance failure with a lower price.
3. **Active-Active is not financially justified at this scale.** It avoids only 0.09 crore more loss than Hot standby (6.46 vs 6.36) but costs 4.04 crore more per year, giving a negative ROI of -27%.
4. **Cold standby is worthless as a mitigation** for regional outages, because its RTO is longer than the outages. It has a role only as a backup for ransomware and corruption recovery (RB-02, RB-11).

## 5. Sensitivity to Regional Event Frequency
The case depends on how often a regional or major infrastructure event occurs. Hot standby ROI vs events per year:

| Events per year | Baseline downtime | Hot downtime | Loss avoided | Net benefit | ROI |
|---|---|---|---|---|---|
| 0.5 | 2.13 h | 0.53 h | 2.15 | (2.62) | -55% |
| 1 | 3.75 h | 0.57 h | 3.56 | (1.22) | -26% |
| **2 (base)** | 7.00 h | 0.63 h | 6.36 | **1.59** | **33%** |
| 3 | 10.25 h | 0.70 h | 9.17 | 4.39 | 92% |

**Break-even is about 1.4 regional events per year.** Below that, the revenue-protection benefit alone does not cover the cost. This is a calculation based on the model's assumptions, and the brief's case studies suggest that single-AZ and regional events do occur (for example the April 2021 ap-south-1 power event). For most of the plausible range, the investment is justified by the mandate rather than by revenue protection alone.

## 6. Conservative Case
If reputational and churn costs are set to zero (they are the most subjective input), Hot standby's loss avoided falls to about 3.97 crore, giving a net benefit of about -0.80 crore and ROI of about -17%. In that case the justification rests entirely on regulatory compliance and licence protection, not on avoided revenue loss.

## 7. What the Model Does Not Price: Licence Risk
The brief states that non-compliance can lead to **licence suspension or revocation**, plus fines up to 5 crore INR. A suspension stops all revenue. At 9 crore INR of revenue per day (0.375 crore/hour x 24, from the brief's 1.8% take rate), one day of suspension costs about 9 crore, which exceeds the entire annual DR premium of 4.78 crore. The Hot standby premium of 4.78 crore equals about half a day of revenue (4.78 / 9). In other words, avoiding a single half-day licence suspension every year, or a full-day suspension every two years, pays for it. That is a very small probability of an event the regulator has already warned about. This is the main reason the investment is recommended regardless of the ROI percentage.

## 8. Insurance Analogy
DR is an insurance premium. For Hot standby, the annual premium is 4.78 crore against expected loss exposure today of about 6.96 crore per year (before any tail event such as licence action). A premium below the expected loss, with the insured loss reduced by about 91% (from 6.96 to 0.59 crore), is a reasonable purchase even before counting tail risk.

## 9. Assumptions That Drive the Result
| Assumption | Value | Effect if wrong |
|---|---|---|
| Regional/infra events per year | 2 | Break-even about 1.4; fewer events lowers ROI |
| Non-DR downtime | 0.5 h/yr | If higher (for example 1.0 h), Hot standby no longer meets 99.99% and fines return |
| Reputational multiple | 1.0x | At zero, Hot ROI is about -17% |
| Fine probability when non-compliant | 60% | Higher increases ROI of any compliant tier |
| Replication volume and price | 1.2 TB/day at 0.086 USD/GB | Data transfer is about 7% of Hot standby cost |

All of these are blue input cells in `cost-model.xlsx`. Update them with actual finance data before presenting to the Business Continuity Review Board.
