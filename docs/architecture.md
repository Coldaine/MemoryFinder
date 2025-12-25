# Threadripper 9000 RDIMM Price Monitor — Architecture

## Overview

A cron-triggered multi-agent system executing locally via the **Claude Code CLI**, utilizing **Z.ai GLM 4.7** as the intelligence engine. The system discovers, tracks, and alerts on pricing for high-capacity RDIMM kits (128GB, 256GB, 512GB quad-channel configurations) compatible with AMD Threadripper 9000 series processors (July 2025 release).

## Agent Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CRON (hourly)                                  │
│                                   │                                         │
│                                   ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    ORCHESTRATOR AGENT                                │   │
│  │                    (Claude Code CLI)                                 │   │
│  │                                                                      │   │
│  │  • Loads run state from PostgreSQL                                  │   │
│  │  • Decides which sub-agents to spawn based on state                 │   │
│  │  • Aggregates results                                               │   │
│  │  • Persists state back to PostgreSQL                                │   │
│  └──────────────┬──────────────┬──────────────┬──────────────┬─────────┘   │
│                 │              │              │              │              │
│        ┌────────┴───┐  ┌───────┴───┐  ┌──────┴─────┐  ┌─────┴──────┐      │
│        ▼            ▼  ▼           ▼  ▼            ▼  ▼            ▼      │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐        │
│  │ DISCOVERY│ │ SCRAPER  │ │ SCRAPER  │ │ ANALYST  │ │ NOTIFIER │        │
│  │  AGENT   │ │ AGENT 1  │ │ AGENT N  │ │  AGENT   │ │  AGENT   │        │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘        │
│       │            │            │            │            │               │
│       ▼            ▼            ▼            ▼            ▼               │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐         │
│  │ SerpAPI │  │Firecrawl│  │ Z.ai    │  │PostgreSQL│ │ Notif.  │         │
│  │ MCP     │  │ MCP     │  │Web Read │  │ (reads)  │ │ Channel │         │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘         │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Agent Responsibilities

| Agent | Spawned When | MCP Tools Used | Output |
|-------|--------------|----------------|--------|
| **Discovery** | Every 6 hours OR on-demand | **Z.ai Web Search Prime**, SerpAPI | New product URLs + initial prices |
| **Scraper** (1-N) | Every run, parallelized by source | **Z.ai Web Reader**, **Z.ai Vision**, Firecrawl | Structured price data per SKU |
| **Analyst** | After all scrapers complete | None (reads from DB) | Deal scores, anomaly flags |
| **Notifier** | When Analyst flags deals | None (writes to stdout) | Alerts via stdout (log scraping) |

### Communication Model

Agents do **not** communicate directly. All inter-agent communication flows through:

1. **PostgreSQL** — persistent state (price history, product catalog, run metadata)
2. **Run context file** — ephemeral state within a single cron invocation (JSON in `/tmp/rdimm-run-{timestamp}.json`)

The orchestrator spawns sub-agents as separate Claude Code CLI invocations using `claude --print` or subprocess calls, passing the run context file path as an argument.

## State & Memory Management

### Persistent State (PostgreSQL)

Lives across all runs. Source of truth for:

- Product catalog (known SKUs, URLs, metadata)
- Price history (every observation timestamped)
- Run metadata (last discovery time, error logs)
- Alert history (what's been sent, when)

### Ephemeral Run State (JSON file)

Created at the start of each cron invocation. Destroyed after run completes. Contains:

```json
{
  "run_id": "uuid",
  "started_at": "ISO8601",
  "phase": "discovery|scraping|analysis|notification|complete",
  "discovery_results": [],
  "scrape_queue": [],
  "scrape_results": [],
  "analysis_output": {},
  "errors": []
}
```

### State Flow Within a Run

```
1. Orchestrator starts
   └── Creates run context file
   └── Loads product catalog from PostgreSQL
   └── Checks: time since last discovery run?
   
2. If discovery needed:
   └── Spawns Discovery Agent
   └── Discovery writes new URLs to run context
   └── Orchestrator merges into scrape_queue
   
3. Scraping phase:
   └── Orchestrator partitions scrape_queue by retailer
   └── Spawns N Scraper Agents (parallel or sequential)
   └── Each Scraper writes to scrape_results in run context
   
4. Analysis phase:
   └── Orchestrator spawns Analyst Agent
   └── Analyst reads scrape_results + historical data from PostgreSQL
   └── Writes deal scores to analysis_output
   
5. Notification phase:
   └── If analysis_output contains actionable deals:
       └── Spawns Notifier Agent
       └── Notifier sends alerts, logs to PostgreSQL
       
6. Cleanup:
   └── Orchestrator persists scrape_results to PostgreSQL price_observations
   └── Updates product catalog with any new SKUs
   └── Deletes run context file
```

### Failure Handling

- If a run crashes mid-execution, the run context file remains in `/tmp/`
- Next cron invocation detects orphaned run context, logs warning, starts fresh
- Individual agent failures are caught by orchestrator, logged, run continues with partial data
