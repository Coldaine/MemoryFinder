# Threadripper 9000 RDIMM Price Monitor — Architecture

## Overview

A cron-triggered multi-agent system executing locally. The system discovers, tracks, and alerts on pricing for high-capacity RDIMM kits (128GB, 256GB, 512GB quad-channel configurations) compatible with AMD Threadripper 9000 series processors (July 2025 release).

**Core Philosophy:** "Deterministic Orchestration, probabilistic Intelligence."
- The **Orchestrator** (Python/Bash) manages state, database connections, and control flow.
- The **Agents** (Claude Code) are stateless workers that perform specific cognitive tasks (Search, Read, Analyze) and return structured JSON.

## Agent Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CRON (hourly)                                  │
│                                   │                                         │
│                                   ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    ORCHESTRATOR (Shell/Python)                      │    │
│  │                                                                     │    │
│  │  1. Setup: Gen Run ID, Connect DB, Check Quotas                     │    │
│  │  2. Job Gen: Create JSON tasks for Agents (e.g. "Scrape these 5")   │    │
│  │  3. Spawn: Run 'claude' processes in parallel                       │    │
│  │  4. Ingest: Parse JSON outputs, write to DB                         │    │
│  │  5. Alert: Check triggers, dispatch notifications                   │    │
│  └──────────────┬──────────────┬──────────────┬──────────────┬─────────┘    │
│                 │              │              │              │              │
│        ┌────────┴───┐  ┌───────┴───┐  ┌──────┴─────┐  ┌─────┴──────┐        │
│        ▼            ▼  ▼           ▼  ▼            ▼  ▼            ▼        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │
│  │ DISCOVERY│ │ SCRAPER  │ │ SCRAPER  │ │ ANALYST  │ │ NOTIFIER │          │
│  │  WORKER  │ │ WORKER A │ │ WORKER B │ │  WORKER  │ │  WORKER  │          │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘          │
│       │            │            │            │            │                 │
│       ▼            ▼            ▼            ▼            ▼                 │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐           │
│  │ SerpAPI │  │Firecrawl│  │ Z.ai    │  │  Pure   │  │ Stdout  │           │
│  │ MCP     │  │ MCP     │  │Web Read │  │  JSON   │  │ (Logs)  │           │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘           │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Agent Responsibilities (Stateless Workers)

| Agent | Input (JSON) | Tools | Output (JSON) |
|-------|--------------|-------|---------------|
| **Discovery** | Search terms, forbidden domains | **Z.ai Web Search**, SerpAPI | List of candidate URLs with metadata |
| **Scraper** | Batch of target URLs, product hints | **Z.ai Web Reader**, **Z.ai Vision**, Firecrawl | Structured price/stock data per URL |
| **Analyst** | Current observations + historical baseline | None (Pure Logic) | Deal confidence scores, "Arbitrage" flags |
| **Notifier** | Deal details | None | Formatted alert message strings |

### Communication Model

Agents do **not** communicate directly. They do **not** connect to the database.

1.  **Orchestrator -> Agent:** Input Context (JSON passed via `<context>` tag or prompt injection).
2.  **Agent -> Orchestrator:** Output Result (JSON block).

## State & Memory Management

### Persistent State (PostgreSQL)

Managed exclusively by the Orchestrator's Python helper scripts.

- **sources:** Tables of known domains and their trust scores.
- **products:** Canonical list of MPNs/SKUs we track.
- **listings:** Mapping of Products to Source URLs.
- **price_observations:** Time-series of price checks.

### Ephemeral Run State (FileSystem)

The Orchestrator uses a temporary directory `/tmp/tr9-run-{id}/` to manage the flow.

1.  `tasks/discovery_input.json`
2.  `results/discovery_output.json`
3.  `tasks/scraper_batch_a_input.json`
4.  `results/scraper_batch_a_output.json`

## Execution Flow

```
1. START (orchestrator.sh)
   └── Call `db_get_tasks.py` -> Returns JSON of "URLs to Scrape" and "Terms to Search"
   
2. DISCOVERY PHASE
   └── If discovery_needed:
       └── Run `claude -p prompts/discovery.md` with search terms
       └── Parse output, dedup against DB, save new URLs to DB

3. SCRAPING PHASE (Parallel)
   └── Partition URLs into Batch A, Batch B
   └── Spawn `claude -p prompts/scraper.md` for Batch A (background)
   └── Spawn `claude -p prompts/scraper.md` for Batch B (background)
   └── Wait for both.

4. ANALYSIS PHASE
   └── Run `db_ingest.py` to save Scraper results to PostgreSQL
   └── Run `db_get_analysis_context.py` to fetch recent prices vs baselines
   └── Run `claude -p prompts/analyst.md` with context
   
5. ALERT PHASE
   └── If high-confidence deals found:
       └── Log to stdout/email
       
6. END
```