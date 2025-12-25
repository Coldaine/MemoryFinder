# GEMINI.md - Project Context & Rules

## 1. Runtime Environment
- **Alias**: `claude z`
- **Tool**: Claude Code CLI
- **Model**: **Z.ai GLM 4.7** (via API key replacement)
  - *Note: We are NOT using Anthropic's Claude models. All prompts effectively drive GLM 4.7.*
- **Parallelism**: Native (via `claude z` sub-agents).

## 2. MCP Configuration (Required Servers)
We must configure `mcp.json` to enable the following tools for GLM 4.7:

1.  **Z.ai Web Search** (`@zai/web-search` or equivalent)
    - Role: Broad discovery (Tier 1 Funnel).
    - Quota: Max Plan (~4,000/month).
2.  **Z.ai Web Reader** (`@zai/web-reader`)
    - Role: Lightweight screening & verification.
3.  **Z.ai Vision** (`@zai/vision`)
    - Role: Edge case verification (images).
4.  **Firecrawl** (`@firecrawl/mcp`)
    - Role: Deep/Complex scraping fallback.
5.  **SerpAPI** (Optional/Secondary)
    - Role: Market snapshots.

## 3. Architecture
- **Type**: Multi-agent System with Native Parallelism.
- **Orchestrator**: A master prompt (run via `claude z`) that spawns sub-agents.
- **Database**: PostgreSQL (as defined in `docs/schema.sql`).
