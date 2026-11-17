# WAF emergency rules (RB-07)

| File | Use |
|---|---|
| `waf-emergency-block.json` | Rate rule 100 requests per 5 minutes per source IP on `/v1/payments`, action **Block** (RB-07 step 10) |
| `waf-emergency-count.json` | Same rule, action **Count**: the staged state and the RB-07 rollback |
| `merchant-ips.json` | Merchant server IPs for the allow-list IP set (RB-07 step 11). **The addresses are documentation-range placeholders** |

Run the runbook commands from this folder, because they use relative `file://` paths:
```
cd configs/terraform/modules/security/waf-rules
aws wafv2 update-web-acl --name paysecure-waf --scope REGIONAL --id WEBACLID --lock-token TOKEN --cli-input-json file://waf-emergency-block.json --region ap-south-1
```

**Important:** `update-web-acl` replaces the whole rule list. These files contain only the emergency rules and the merchant allow-list. **Before use, merge them with the rules that already exist in the production web ACL** (`aws wafv2 get-web-acl`), or you will remove those protections. Replace `ACCOUNT` and `IPSETID` with real values. Not tested against a live web ACL.
