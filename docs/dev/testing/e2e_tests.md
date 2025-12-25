# End-to-End (E2E) Acceptance Tests

These tests define the "Definition of Done" for the MemoryFinder project. They simulate real-world scenarios to ensure the system is accurate, efficient, and autonomous.

---

## 1. The "Golden Sample" Arbitrage Test
**Objective:** Verify the complete pipeline from URL input to Alert generation for a valid deal.

### Setup
*   **Target:** A specific surplus store page for a Samsung 128GB RDIMM.
*   **Mock State:** The page displays a price of **$350** (significantly below the $450 market baseline).
*   **Inventory State:** The page explicitly states "In Stock: 5".
*   **Database:** A baseline price of $450 is already recorded for this SKU.

### Execution
1.  Add the target URL to the `scrape_queue`.
2.  Run the full orchestration cycle: `Scrape -> Analyze -> Alert`.

### Success Criteria
1.  **Scraper:** `price_observations` table contains a new row with `price_cents=35000` and `in_stock=true`.
2.  **Analyst:** The analysis log/DB entry flags this observation with a `deal_confidence > 80`.
3.  **Notifier:** A formatted alert string is generated containing the URL, price, and calculated discount percentage.

---

## 2. The "Gamer Trap" Filtering Test
**Objective:** Prove the system successfully ignores incompatible hardware (UDIMMs).

### Setup
*   **Target:** A URL for a "Corsair Vengeance UDIMM 128GB Kit".
*   **Mock State:** Price is $200 (appearing as a "huge discount" if misidentified as RDIMM).
*   **Knowledge Base:** System is configured with "TR9-128Q" recipe requiring RDIMM/ECC.

### Execution
1.  Add the UDIMM URL to the `scrape_queue`.
2.  Run the Scraper and Analyst phases.

### Success Criteria
1.  **Scraper:** The agent extracts the data but flags `product_type` as `UDIMM` or `Non-ECC`.
2.  **Analyst:** The `deal_confidence` score is **0**.
3.  **Alerts:** **Zero alerts fired.** No invalid product is promoted to the alerts channel.

---

## 3. The "Zombie Link" Suppression Test (OOS Handling)
**Objective:** Verify the system stops wasting resources on dead links via exponential backoff.

### Setup
*   **Target:** A URL that returns "Out of Stock" or "Call for Availability".
*   **Database:** System is set to hourly runs.

### Execution
1.  Run the Orchestrator (Run 1).
2.  Wait for the next scheduled interval or force a second run (Run 2).

### Success Criteria
1.  **Run 1:** Records `in_stock=false` and increments `oos_streak` in the database.
2.  **Run 2:** The `db_get_tasks.py` script **does not return** this URL for scraping in the next cycle.
3.  **Verification:** Logs confirm the URL was skipped due to OOS status.

---

## 4. The "Budget Breaker" Stress Test
**Objective:** Ensure strict enforcement of API quotas to prevent billing spikes.

### Setup
*   **Configuration:** Set `MAX_API_CALLS_PER_RUN = 5`.
*   **Queue:** Seed the database with **20** URLs requiring scraping.

### Execution
1.  Run the Orchestrator.

### Success Criteria
1.  **Execution:** The orchestrator halts agent spawning exactly after 5 items are processed.
2.  **Queue Management:** The remaining 15 items remain in the queue for the next run.
3.  **Metrics:** The run summary explicitly notes "Quota limit reached; 15 items deferred."

---

## 5. The "Zero-Knowledge" Discovery Test
**Objective:** Prove the system can find new, valid sources autonomously.

### Setup
*   **Initial State:** Empty `sources` and `listings` tables.
*   **Seed Data:** Provide only a Manufacturer Part Number (MPN) for a known Threadripper 9000 RDIMM.

### Execution
1.  Run the Orchestrator with `-RunDiscovery` enabled.

### Success Criteria
1.  **Discovery:** The system identifies **at least 3 valid product URLs** from distinct, previously unknown domains.
2.  **Validation:** These URLs are successfully inserted into the `product_listings` table with the correct product mapping.
3.  **Quality:** The URLs point to actual buy-pages, not review articles or generic landing pages.
