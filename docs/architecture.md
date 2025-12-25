# Threadripper 9000 RDIMM Price Monitor — Architecture

## Overview

A cron-triggered multi-agent system executing locally. The system discovers, tracks, and alerts on pricing for high-capacity RDIMM kits (128GB, 256GB, 512GB quad-channel configurations) compatible with AMD Threadripper 9000 series processors (July 2025 release).

**Core Philosophy:** "Deterministic Orchestration, probabilistic Intelligence."
- The **Orchestrator** (Python/Bash) manages state, database connections, and control flow.
- The **Agents** (Claude Code) are stateless workers that perform specific cognitive tasks (Search, Read, Analyze) and return structured JSON.

## Agent Topology (Native Parallelism)



The system leverages the native multi-agent capabilities of the Claude Code CLI (`claudez`).



```

┌─────────────────────────────────────────────────────────────────────────────┐

│                              CRON (hourly)                                  │

│                                   │                                         │

│                                   ▼                                         │

│  ┌─────────────────────────────────────────────────────────────────────┐    │

│  │                    ORCHESTRATOR (claudez)                           │    │

│  │                                                                     │    │

│  │  1. Planning: Load state from PostgreSQL via MCP                    │    │

│  │  2. Dispatch: Parallel sub-agents (claudez -p)                      │    │

│  │  3. Aggregation: Collect JSON from sub-agents                       │    │

│  │  4. State Update: Write back to PostgreSQL                          │    │

│  └──────────────┬──────────────┬──────────────┬──────────────┬─────────┘    │

│                 │              │              │              │              │

│        ┌────────┴───┐  ┌───────┴───┐  ┌──────┴─────┐  ┌─────┴──────┐        │

│        ▼            ▼  ▼           ▼  ▼            ▼  ▼            ▼        │

│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │

│  │ DISCOVERY│ │ RETAIL   │ │ SURPLUS  │ │ ANALYST  │ │ NOTIFIER │          │

│  │  AGENT   │ │ VERIFIER │ │ VERIFIER │ │  AGENT   │ │  AGENT   │          │

│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘          │

```



### Execution Strategy

Instead of external shell-level backgrounding, the Orchestrator uses its internal capability to spawn sub-agents. 



**Example Workflow:**

1. Orchestrator calls `discovery-screener` to find new URLs.

2. Orchestrator receives JSON list of URLs.

3. Orchestrator spawns 3 parallel verifiers (`verifier-retail`, `verifier-surplus`, `verifier-marketplace`) to process the list.

4. Orchestrator aggregates all verified observations and saves to DB.
