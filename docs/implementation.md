# Implementation & Setup Guide

## Directory Structure

```
~/rdimm-monitor/
├── docs/                   # Documentation (Architecture, Schema, etc.)
├── prompts/                # Agent prompts (Orchestrator, Discovery, etc.)
├── scripts/
│   ├── run.sh              # Cron entry point
│   ├── init-db.sql         # Schema setup
│   └── spawn-agent.sh      # Helper to invoke sub-agents
├── config/
│   └── mcp.json            # MCP server config
└── tmp/                    # Run context files (ephemeral)
```

## Setup Steps

### 1. Database Initialization

```bash
# Create database
createdb rdimm_monitor

# Apply schema
psql -d rdimm_monitor < docs/schema.sql

# Seed initial sources
psql -d rdimm_monitor <<EOF
INSERT INTO sources (name, domain, source_type, scrape_method, trust_score) VALUES
  ('Newegg', 'newegg.com', 'major_retailer', 'firecrawl', 90),
  ('Amazon', 'amazon.com', 'major_retailer', 'firecrawl', 90),
  ('ServerPartDeals', 'serverpartdeals.com', 'surplus', 'zai_reader', 80),
  ('Memory.net', 'memory.net', 'reseller', 'zai_reader', 75),
  ('ITCreations', 'itcreations.com', 'surplus', 'zai_reader', 70),
  ('eBay', 'ebay.com', 'marketplace', 'serpapi', 50);
EOF
```

### 2. MCP Server Configuration

Ensure `~/.config/claude/mcp.json` includes the zai-* and third-party servers:

```json
{
  "mcpServers": {
    "zai-web-search-prime": {
        "command": "npx",
        "args": ["-y", "@zai/mcp-web-search-prime"]
    },
    "zai-web-reader": {
        "command": "npx",
        "args": ["-y", "@zai/mcp-web-reader"]
    },
    "zai-vision-understanding": {
        "command": "npx",
        "args": ["-y", "@zai/mcp-vision-understanding"]
    },
    "serpapi": {
      "url": "https://mcp.serpapi.com/mcp"
    },
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"]
    }
  }
}
```

### 3. Execution Scripts

#### `scripts/run.sh`

```bash
#!/bin/bash
set -e

# Note: Claude Code will read standard ~/.claude/mcp.json or project config
export DATABASE_URL="postgresql://user:pass@localhost:5432/rdimm_monitor"
export RUN_CONTEXT_PATH="/tmp/rdimm-run-$(date +%s).json"

# Secrets should be loaded from secure env, not hardcoded
# export SERPAPI_KEY=... 
# export FIRECRAWL_API_KEY=...

# Run orchestrator with Claude Code CLI (aliased to claude or zai-claude)
claude --print \
  --prompt-file ./prompts/orchestrator.md \
  --env DATABASE_URL="$DATABASE_URL" \
  --env RUN_CONTEXT_PATH="$RUN_CONTEXT_PATH"
```

#### `scripts/spawn-agent.sh`

```bash
#!/bin/bash
# Usage: spawn-agent.sh <agent-name> <input-json>

AGENT_NAME=$1
INPUT_JSON=$2

claude --print \
  --prompt-file "./prompts/${AGENT_NAME}.md" \
  --input "$INPUT_JSON"
```

### 4. Cron Job

```bash
# Add hourly job
0 * * * * /path/to/rdimm-monitor/scripts/run.sh >> /var/log/rdimm-monitor.log 2>&1
```
