# MemoryFinder TODO

Tracking remaining features and known issues for the TR9-RPM (Threadripper 9000 RDIMM Price Monitor) system.

## In Progress

- [x] Real Claude CLI invocations (replaced mock with `claude -p`)
- [x] Test mode with isolated output (`-TestMode` flag)
- [x] Smoke test script (`tests/smoke-test.ps1`)

## Database Layer

- [ ] Implement actual DB reads in `db_get_tasks.py` (currently hardcoded)
- [ ] Implement actual DB writes in `db_ingest.py` (currently TODO stubs)
- [ ] Decide: SQLite vs PostgreSQL (currently mixed - code uses SQLite, mcp.json has PostgreSQL)
- [ ] Create proper schema migrations
- [ ] Add OOS streak tracking per listing

## Agent System

- [ ] Wire up the 3 parallel verifiers (retail, surplus, marketplace) instead of single scraper
- [ ] Implement agent output validation against JSON schemas
- [ ] Add quota tracking (z.ai calls, firecrawl calls per run)
- [ ] Implement fallback logic (reader → vision → firecrawl)

## Discovery Phase

- [ ] Rotate search queries from database
- [ ] Track `last_discovery_at` to enforce 6-hour interval
- [ ] Implement forbidden domain filtering
- [ ] Cap candidates per run (100 max)

## Analysis & Alerting

- [ ] Implement 7-day price baseline calculation
- [ ] Price drop detection (>5% below baseline)
- [ ] Arbitrage detection (>10% cross-retailer spread)
- [ ] Stale pricing detection (unchanged >14 days)
- [ ] Back-in-stock alerts
- [ ] Deal scoring (0-100 confidence)
- [ ] Alert deduplication (don't re-alert within 24h)

## Scheduling & Operations

- [ ] Cron/Task Scheduler setup for hourly runs
- [ ] Logging to file (not just console)
- [ ] Run history in database
- [ ] Metrics dashboard or report

## MCP & Environment

- [ ] Validate MCP config actually works with z.ai services
- [ ] Document required environment variables
- [ ] Add env var validation at startup

## Testing

- [ ] E2E test: Golden Sample Arbitrage
- [ ] E2E test: Gamer Trap Filtering (reject UDIMMs)
- [ ] E2E test: Zombie Link Suppression (OOS backoff)
- [ ] E2E test: Budget Breaker Stress (quota limits)
- [ ] E2E test: Zero-Knowledge Discovery

## Nice to Have

- [ ] Parallel agent execution in PowerShell (Start-Job)
- [ ] Notification channels (email, Discord, etc.)
- [ ] Web UI for viewing deals
- [ ] Historical price charts

---

Last updated: 2024-12-30
