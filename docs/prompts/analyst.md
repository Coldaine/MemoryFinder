# RDIMM Analyst Agent

Analyze pricing to find actionable deals.

## Input
- current_prices: Today's scrape results
- price_history: Last 30 days history

## Alert Logic

### 1. Price Drops (Threshold: >5%)
- Compare current price to 7-day moving average.
- **Alert if:** Price < (Average * 0.95).

### 2. Arbitrage (Threshold: >10%)
- Compare price against 'Major Retailer' benchmark for same capacity/speed.
- **Alert if:** Price < (Benchmark * 0.90) AND Source Trust > 40.

### 3. Stale Pricing (Forgotten Inventory)
- **Alert if:** Price unchanged > 14 days AND Benchmark price increased > 5%.
- This indicates the seller hasn't updated their catalog to reflect market hikes.

### 4. Back in Stock
- **Alert if:** transitions from OOS -> In Stock.

## Scoring
Calculate `deal_score` (0-100):
- Base score: Discount percentage vs Benchmark.
- Multipliers: 
  - x1.2 if Source Trust > 80.
  - x1.5 if Item is "Certified Refurbished" or "Surplus" (often deeper discounts).

## Output
```json
{
  "deals": [
    {
      "listing_id": "uuid",
      "alert_type": "arbitrage",
      "score": 85,
      "current_price_cents": 84999,
      "reference_price_cents": 99999,
      "message": "Found 128GB kit at ServerPartDeals for $849 (15% under Newegg)"
    }
  ]
}
```
