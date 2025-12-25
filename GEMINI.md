# GEMINI.md - Project Context & Rules

## 1. Runtime Environment
- **Alias**: `claudez`
- **Tool**: Claude Code CLI
- **Model**: **Z.ai GLM 4.7** (via API key replacement)
  - *Note: We are NOT using Anthropic's Claude models. All prompts effectively drive GLM 4.7.*
- **Parallelism**: Native (via `claudez` sub-agents).

## 2. MCP Configuration (Required Servers)
We must configure `mcp.json` to enable the following tools for GLM 4.7:

1.  **Z.ai Web Search Prime** (`web-search-prime`)
    - **Type**: Remote HTTP
    - **URL**: `https://api.z.ai/api/mcp/web_search_prime/mcp`
    - Role: Broad discovery (Tier 1 Funnel).
    - Quota: Max Plan (~4,000/month).
    - Docs: https://docs.z.ai/devpack/mcp/search-mcp-server
2.  **Z.ai Web Reader** (`web-reader`)
    - **Type**: Remote HTTP
    - **URL**: `https://api.z.ai/api/mcp/web_reader/mcp`
    - Role: Lightweight screening & verification.
    - Docs: https://docs.z.ai/devpack/mcp/reader-mcp-server
3.  **Z.ai Vision** (`zai-vision`)
    - **Type**: stdio (local npm package)
    - **Package**: `@z_ai/mcp-server`
    - **Env**: `Z_AI_API_KEY`, `Z_AI_MODE=ZAI`
    - Role: Edge case verification (image-based pricing).
    - Docs: https://docs.z.ai/devpack/mcp/vision-mcp-server
4.  **Firecrawl** (`firecrawl`)
    - **Type**: stdio (local npm package)
    - **Package**: `@mendable/firecrawl-mcp-server`
    - Role: Deep/Complex scraping fallback (JS-heavy pages).
5.  **PostgreSQL** (`postgres`)
    - **Type**: stdio (local npm package)
    - **Package**: `@modelcontextprotocol/server-postgres`
    - Role: State persistence, baselines, OOS tracking.


## 3. Architecture: Single Invocation + Native Subagents

**Core Concept:** Single hourly `claudez -p` invocation that orchestrates 3-4 parallel subagents.

### Invocation Pattern
```bash
claudez -p \
  --output-format json \
  --max-turns 12 \
  --mcp-config ./mcp.json \
  --append-system-prompt orchestrator-prompt.md
```

> [!WARNING]
> **Non-existent CLI flags**: The flags `--json-schema` and `--strict-mcp-config` do NOT exist in Claude Code CLI. Output validation must be done externally (e.g., Python script). Use `--mcp-debug` for troubleshooting MCP issues.



### Subagent Definitions
Stored in `.claude/agents/`:
- `discovery-screener.md` - Find candidate URLs
- `verifier-retail.md` - Verify retail sources
- `verifier-surplus.md` - Verify surplus/liquidation sources
- `verifier-marketplace.md` - Verify eBay/forum sources

### System Flow (Per Hourly Run)
1. **Planning**: Load state from PostgreSQL
2. **Wave 1 (Discovery)**: Dispatch `discovery-screener` (every 6h)
3. **Wave 2 (Verification)**: Dispatch 3 parallel verifiers
4. **Wave 3 (Analysis)**: Score deals, detect arbitrage
5. **Persistence**: Write observations, update OOS streaks, emit alerts

## 4. Database
- **Engine**: PostgreSQL
- **Schema**: `docs/schema.sql`
- **Key Tables**: `products`, `sources`, `product_listings`, `price_observations`, `targets`, `benchmarks`, `alert_history`, `quota_usage`

## 5. Key Constraints

### Wave Discipline
- Max 3-4 parallel subagents per wave
- Orchestrator has PostgreSQL MCP only (no web tools)
- All web operations delegated to subagents

### OOS Efficiency
- Skip URLs with `oos_streak_hours > 72` unless restock signal
- Track per-listing: `oos_streak_hours`, `last_in_stock_at`, `last_verified_price_at`

### Identity Confidence
- Require MPN or strong fingerprint before alerting
- Never alert on ambiguous "256GB DDR5" without details

### Quota Management
- Budget ~30-50 z.ai calls per hourly run
- Budget ~100-150 z.ai calls per 6-hour heavy discovery
- Track usage in `quota_usage` table
- Fallback to Firecrawl when approaching limits

## 6. Target Products

### Primary (4-DIMM quad-channel)
- **TR9-128Q**: 4×32GB DDR5 RDIMM
- **TR9-256Q**: 4×64GB DDR5 RDIMM
- **TR9-512Q**: 4×128GB DDR5 RDIMM

### Secondary (8-DIMM 2DPC, learn mode)
- **TR9-256-8D**: 8×32GB
- **TR9-512-8D**: 8×64GB

## 7. Success Criteria (Per Run)
- Discover 20-100 candidates (heavy hour)
- Verify 25-35 URLs
- Write 20-30 valid observations
- Flag 0-5 deals (high precision)
- Complete in <5 minutes

## 8. E2E Testing Targets (Acceptance Criteria)
To consider the system complete, it must pass the following tests (documented in `docs/dev/testing/e2e_tests.md`):
1. **Golden Sample Arbitrage:** Complete pipeline success for a valid deal.
2. **Gamer Trap Filtering:** Accurate rejection of incompatible (UDIMM) hardware.
3. **Zombie Link Suppression:** Effective OOS backoff logic.
4. **Budget Breaker Stress:** Strict enforcement of API call quotas.
5. **Zero-Knowledge Discovery:** Successful autonomous finding of new sources.
