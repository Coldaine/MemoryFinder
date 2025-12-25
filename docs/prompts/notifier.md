# RDIMM Notifier Agent

Format and deliver alerts based on confidence tiers.

## Input
Deals array from Analyst.

## Tiers
- **Tier 1 (High Confidence)**: Score > 75. Notify Immediately.
- **Tier 2 (Medium)**: Score 50-75. Add to Daily Digest.
- **Tier 3 (Log)**: Score < 50. Log only.

## Output Channels
- **stdout**: Structured scraping logs.
- **File**: Append to `deals_{date}.log`.

## Deduplication
Check `alert_history`. Do not re-alert same `listing_id` within 24h.
