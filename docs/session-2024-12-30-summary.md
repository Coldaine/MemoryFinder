# Session Summary: 2024-12-30

## Overview

This session focused on making the MemoryFinder (TR9-RPM) system functional by replacing mock implementations with real Claude CLI invocations, setting up a comprehensive MCP server suite, and testing the agent-based architecture through live experiments.

---

## What We Accomplished

### 1. Codebase Analysis

We performed a deep analysis of the existing codebase and identified:

**What was working:**
- Directory structure and orchestration flow
- MCP config file format (though orphaned)
- Agent prompt definitions
- SQLite schema initialization

**What was broken:**
- Claude invocations were completely mocked (`Start-Sleep` + fake JSON)
- Python scripts (`db_get_tasks.py`, `db_ingest.py`) returned hardcoded data
- Database reads/writes were TODO stubs
- `mcp.json` was orphaned (Claude Code uses `.mcp.json`, not `mcp.json`)
- No actual MCP servers were configured for the project

### 2. Real Claude CLI Invocations

**Branch:** `feat/real-claude-invocations` (merged via PR #1)

Replaced the mock `Run-ClaudeAgent` function in `orchestrator.ps1` with actual Claude CLI calls:

```powershell
# Before (mock)
Start-Sleep -Seconds 2
"{ "status": "success", "mock_data": true }" | Set-Content $OutputFile

# After (real)
$result = Get-Content -Raw $FullPromptPath | claude @claudeArgs 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Claude CLI failed with exit code $LASTEXITCODE"
}
$result | Set-Content $OutputFile -Encoding UTF8
```

**Key flags used:**
- `-p` - Non-interactive print mode
- `--output-format json` - Machine-readable output
- `--max-turns 10` - Limit iterations
- `--dangerously-skip-permissions` - Unattended execution

### 3. Test Mode Isolation

Added `-TestMode` flag to `orchestrator.ps1` that:
- Writes output to `tests/output/` instead of production paths
- Uses `tests/data/memoryfinder_test.db` instead of production database
- Sets `MEMORYFINDER_DB` environment variable for Python scripts

This ensures testing doesn't pollute production data.

### 4. Smoke Test Infrastructure

Created `tests/smoke-test.ps1` that:
- Checks prerequisites (claude CLI, Python)
- Initializes test database
- Runs orchestrator in test mode
- Validates output JSON
- Exits with non-zero code on failure (CI-friendly)

### 5. MCP Server Configuration

**Deleted:** `mcp.json` (orphaned, never used by Claude Code)

**Created/Updated:** `.mcp.json` with comprehensive MCP suite:

| Server | Package | Purpose | Status |
|--------|---------|---------|--------|
| postgres | `@modelcontextprotocol/server-postgres` | Database persistence | ⚠️ Connection issues |
| firecrawl | `firecrawl-mcp` | JS-heavy page scraping | ✅ Connected |
| tavily | `tavily-mcp` | AI-optimized search | ✅ Connected |
| brave-search | `@modelcontextprotocol/server-brave-search` | Web search (20M/mo) | ✅ Connected |
| exa | `exa-mcp-server` | Semantic search | ✅ Connected |

**Global (already configured):**
| Server | Package | Purpose | Status |
|--------|---------|---------|--------|
| zai-mcp-server | `@z_ai/mcp-server` | Vision, search, reader | ✅ Connected |

### 6. Bitwarden Secrets Manager Integration

Created `scripts/load-secrets.ps1` that loads API keys from BWS:

```powershell
. .\load-secrets.ps1  # Loads into current session

# Required secrets:
# - DATABASE_URL
# - FIRECRAWL_API_KEY
# - TAVILY_API_KEY
# - BRAVE_SEARCH_API_KEY
# - EXA_API_KEY

# Optional secrets:
# - SERP_API_KEY
# - Z_AI_API_KEY
# - PERPLEXITY_API_KEY
```

All secrets are stored in BWS under the "Search & Research" and "API Keys - Hot" projects. No secrets are committed to the repository.

### 7. Live Agent Experiments

Dispatched three parallel agents to test real-world functionality:

**Discovery Agent: ✅ SUCCESS**
- Used WebSearch to find 13 unconventional DDR5 RDIMM sources
- Found surplus dealers, liquidators, wholesale distributors
- Examples: ServerSupply, Big Data Supply, BuySellRAM, Techbuyer, HK Stellar

**Scraper Agent 1 (serverpartdeals.com): ❌ FAILED**
- Product URL returned 404 (page removed/moved)
- Site uses JavaScript for dynamic content
- WebFetch couldn't extract structured data

**Scraper Agent 2 (memory.net): ❌ FAILED**
- 403 Forbidden (anti-scraping protection)
- Part number mismatch in seed data (64GB vs 128GB claimed)

**Key Learnings:**
- Discovery via WebSearch works great
- Scraping needs fallbacks (Firecrawl for JS-heavy sites)
- Seed URLs in codebase are stale/incorrect
- Need graceful error handling for 404s and 403s

### 8. PR Review & Fixes

PR #1 received automated review comments from:
- qodo-free-for-open-source-projects (compliance checker)
- kiloconnect (code reviewer)
- GitHub Copilot (inline suggestions)

**Issues fixed:**
- Added `$LASTEXITCODE` check (PowerShell doesn't throw on non-zero exit from external commands)
- Made smoke test exit non-zero on failure
- Separated stderr from stdout to avoid corrupting JSON output

**Issues acknowledged but not fixed (intentional for local tool):**
- `--dangerously-skip-permissions` flag
- Error details in output files
- Unvalidated environment variable paths

---

## Current Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    orchestrator.ps1                         │
│                    (PowerShell)                             │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┐
        │             │             │
        ▼             ▼             ▼
┌───────────┐  ┌───────────┐  ┌───────────┐
│ Discovery │  │  Scraper  │  │  Analyst  │
│   Agent   │  │   Agent   │  │   Agent   │
└─────┬─────┘  └─────┬─────┘  └─────┬─────┘
      │              │              │
      └──────────────┼──────────────┘
                     │
                     ▼
        ┌────────────────────────┐
        │   Claude CLI (claude)  │
        │   with MCP servers:    │
        │   - firecrawl          │
        │   - tavily             │
        │   - brave-search       │
        │   - exa                │
        │   - zai-mcp-server     │
        │   - postgres           │
        └────────────────────────┘
```

**Note:** Python scripts (`db_get_tasks.py`, `db_ingest.py`) still exist but are essentially non-functional placeholders that return hardcoded data.

---

## Files Changed This Session

| File | Change |
|------|--------|
| `scripts/orchestrator.ps1` | Real Claude invocations, test mode, stderr fix |
| `scripts/db_common.py` | MEMORYFINDER_DB env var support |
| `scripts/load-secrets.ps1` | **New** - BWS secret loading |
| `tests/smoke-test.ps1` | **New** - Smoke test runner |
| `.mcp.json` | Comprehensive MCP suite |
| `.gitignore` | **New** - Ignore test/data output |
| `TODO.md` | **New** - Feature tracking |
| `mcp.json` | **Deleted** - Was orphaned |

---

## Git History

```
15f8e1e feat: Add comprehensive MCP suite with BWS secret loading
2e0706d feat: Real Claude invocations with test mode and MCP config
77230d8 feat: Implement TR9-RPM System Design
104050b Update architecture, add orchestrator scripts, and E2E tests
4655c3b Initial commit: Design docs, proposals, and GEMINI.md
```

---

## What's Still Dummy/Placeholder

### Python Scripts (not functional)

**`db_get_tasks.py`:**
- `get_discovery_tasks()` - Returns hardcoded search queries
- `get_scrape_tasks()` - Returns hardcoded seed URLs (which are now stale)
- `get_analysis_tasks()` - Returns empty observations array
- Never actually queries the database

**`db_ingest.py`:**
- `ingest_discovery()` - Just prints, `# TODO: INSERT INTO`
- `ingest_scrape()` - Just prints, `# TODO: INSERT INTO`
- `ingest_analysis()` - Just prints, `# TODO: INSERT INTO`
- Never actually writes to database

### Database

- SQLite schema exists but tables are empty
- Postgres MCP configured but connection failing (Prisma URL format issue)
- No actual data persistence happening

---

## Next Steps (Proposed Phases)

### Phase 1: Simplify Architecture

**Goal:** Remove unnecessary complexity

- [ ] Remove Python middleman scripts (or make them actually work)
- [ ] Consider rewriting orchestrator in bash for portability
- [ ] Use JSON files for state (simpler than DB for MVP)
- [ ] Single Claude call per phase with MCP database access

### Phase 2: Dual-Engine Support

**Goal:** Use z.ai (free) for development, Claude (paid) for production

- [ ] Add `--engine` flag (`claude` | `zai`)
- [ ] Verify same prompts work on both backends
- [ ] Document engine-specific quirks

### Phase 3: Robust Scraping

**Goal:** Handle real-world site diversity

- [ ] Try WebFetch first (fast, free)
- [ ] Fall back to Firecrawl MCP for JS-heavy sites
- [ ] Handle 404/403 gracefully
- [ ] Track URL health (oos_streak, last_verified)

### Phase 4: Database Persistence

**Goal:** Actual data storage

- [ ] Fix Postgres MCP connection (or switch to SQLite MCP)
- [ ] Implement schema with proper tables
- [ ] Replace hardcoded data with real DB queries
- [ ] Price history tracking

### Phase 5: Analysis & Alerting

**Goal:** Find deals automatically

- [ ] Price drop detection (vs 7-day baseline)
- [ ] Arbitrage detection (cross-retailer spread)
- [ ] Back-in-stock alerts
- [ ] Notification channels (email, Discord)

### Phase 6: Production Hardening

**Goal:** Hands-off operation

- [ ] Cron/Task Scheduler setup
- [ ] Logging to file
- [ ] Quota tracking
- [ ] Error alerting

---

## How to Run

### Load Secrets
```powershell
cd C:\Development\MemoryFinder\scripts
. .\load-secrets.ps1
```

### Verify MCP Servers
```powershell
claude mcp list
```

### Run Orchestrator (Test Mode)
```powershell
.\orchestrator.ps1 -TestMode -RunDiscovery
```

### Run Smoke Test
```powershell
cd C:\Development\MemoryFinder\tests
.\smoke-test.ps1
```

---

## Key Discoveries

1. **Claude's built-in WebSearch works great** for discovery - no external MCP needed for basic search.

2. **Scraping is harder** - many sites block bots or use JavaScript. Firecrawl MCP is essential for JS-heavy pages.

3. **The Python middleman is unnecessary** - Claude can read/write directly via MCP. The scripts exist as placeholders from an earlier "deterministic orchestration" design philosophy.

4. **Z.ai MCP server is comprehensive** - single `@z_ai/mcp-server` package bundles vision, search, and reader capabilities.

5. **BWS integration works well** - secrets load cleanly, no risk of committing API keys.

---

## References

- [Claude Code CLI Reference](https://docs.anthropic.com/claude/docs/claude-code)
- [@z_ai/mcp-server npm](https://www.npmjs.com/package/@z_ai/mcp-server)
- [Z.ai Vision MCP Docs](https://docs.z.ai/devpack/mcp/vision-mcp-server)
- [Firecrawl MCP](https://github.com/firecrawl/firecrawl-mcp-server)
- [@modelcontextprotocol/server-brave-search](https://www.npmjs.com/package/@modelcontextprotocol/server-brave-search)
- [MCP Omnisearch](https://github.com/spences10/mcp-omnisearch)
