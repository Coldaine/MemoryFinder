# Orchestrator for Threadripper 9000 RDIMM Monitor
# Usage: ./orchestrator.ps1 [-RunDiscovery] [-TestMode]
#
# Flags:
#   -RunDiscovery  Run the discovery phase (default: skip, only scrape/analyze)
#   -TestMode      Use isolated test directories (tests/output/) instead of production paths

param (
    [switch]$RunDiscovery = $false,
    [switch]$TestMode = $false
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path ".."
$RunId = Get-Date -Format "yyyyMMdd-HHmmss"

# Set paths based on mode
if ($TestMode) {
    $TmpDir = Join-Path $Root "tests\output\tr9-run-$RunId"
    $DataDir = Join-Path $Root "tests\data"
    $env:MEMORYFINDER_DB = Join-Path $DataDir "memoryfinder_test.db"
    Write-Host "=== TEST MODE ===" -ForegroundColor Yellow
} else {
    $TmpDir = Join-Path $env:USERPROFILE ".gemini\tmp\tr9-run-$RunId"
    $DataDir = Join-Path $Root "data"
    $env:MEMORYFINDER_DB = Join-Path $DataDir "memoryfinder.db"
}
$PromptsDir = Join-Path $Root "docs\prompts"
$ScriptsDir = Join-Path $Root "scripts"

Write-Host "Starting Run $RunId"
Write-Host "Temp Dir: $TmpDir"
Write-Host "Data Dir: $DataDir"
Write-Host "Database: $env:MEMORYFINDER_DB"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null

# --- Helper Function to Run Claude ---
function Run-ClaudeAgent {
    param (
        [string]$AgentName,
        [string]$PromptFile,
        [string]$InputJsonFile,
        [string]$OutputFile,
        [int]$MaxTurns = 10
    )
    Write-Host "[$AgentName] Starting..."

    # Read Input Context
    $InputContent = Get-Content -Raw $InputJsonFile

    # Read Prompt Template
    $PromptContent = Get-Content -Raw $PromptFile

    # Combine context + task prompt
    $FullPrompt = "Context Data:`n$InputContent`n`nTask:`n$PromptContent"
    $FullPromptPath = Join-Path $TmpDir "$AgentName-full-prompt.md"
    $FullPrompt | Set-Content $FullPromptPath -Encoding UTF8

    Write-Host "[$AgentName] Executing Claude (max $MaxTurns turns)..."

    # Build Claude CLI arguments
    $claudeArgs = @(
        "-p"                                    # Non-interactive print mode
        "--output-format", "json"               # JSON output for parsing
        "--max-turns", $MaxTurns                # Limit iterations
        "--dangerously-skip-permissions"        # Unattended execution
    )

    # Add MCP config if it exists
    $mcpConfig = Join-Path $Root "mcp.json"
    if (Test-Path $mcpConfig) {
        $claudeArgs += @("--mcp-config", $mcpConfig)
    }

    try {
        # Read the prompt and pipe it to Claude
        $result = Get-Content -Raw $FullPromptPath | claude @claudeArgs 2>&1

        # PowerShell doesn't throw on non-zero exit from external commands
        if ($LASTEXITCODE -ne 0) {
            throw "Claude CLI failed with exit code $LASTEXITCODE. Output: $result"
        }

        # Write output to file
        $result | Set-Content $OutputFile -Encoding UTF8

        Write-Host "[$AgentName] Finished successfully."
    }
    catch {
        Write-Host "[$AgentName] ERROR: $_" -ForegroundColor Red
        # Write error info to output file for downstream handling
        @{
            status = "error"
            agent = $AgentName
            error = $_.ToString()
            timestamp = (Get-Date -Format "o")
        } | ConvertTo-Json | Set-Content $OutputFile -Encoding UTF8
    }
}

# --- Phase 1: Discovery ---
if ($RunDiscovery) {
    Write-Host "--- Phase 1: Discovery ---"
    # 1. Get Search Terms
    $DiscoveryInput = Join-Path $TmpDir "discovery_input.json"
    python "$ScriptsDir\db_get_tasks.py" --mode discovery --out $DiscoveryInput

    # 2. Run Agent
    $DiscoveryOutput = Join-Path $TmpDir "discovery_output.json"
    Run-ClaudeAgent -AgentName "Discovery" -PromptFile "$PromptsDir\discovery.md" -InputJsonFile $DiscoveryInput -OutputFile $DiscoveryOutput

    # 3. Ingest Results
    python "$ScriptsDir\db_ingest.py" --mode discovery --in $DiscoveryOutput
}

# --- Phase 2: Scraping ---
Write-Host "--- Phase 2: Scraping ---"
# 1. Get URLs to Scrape
$ScrapeInput = Join-Path $TmpDir "scrape_input.json"
python "$ScriptsDir\db_get_tasks.py" --mode scrape --out $ScrapeInput

# 2. Run Agents (Parallel in future - sequential for now)
$ScrapeOutput = Join-Path $TmpDir "scrape_output.json"
Run-ClaudeAgent -AgentName "Scraper" -PromptFile "$PromptsDir\scraper.md" -InputJsonFile $ScrapeInput -OutputFile $ScrapeOutput

# 3. Ingest Results
python "$ScriptsDir\db_ingest.py" --mode scrape --in $ScrapeOutput

# --- Phase 3: Analysis ---
Write-Host "--- Phase 3: Analysis ---"
$AnalysisInput = Join-Path $TmpDir "analysis_input.json"
python "$ScriptsDir\db_get_tasks.py" --mode analysis --out $AnalysisInput

$AnalysisOutput = Join-Path $TmpDir "analysis_output.json"
Run-ClaudeAgent -AgentName "Analyst" -PromptFile "$PromptsDir\analyst.md" -InputJsonFile $AnalysisInput -OutputFile $AnalysisOutput

python "$ScriptsDir\db_ingest.py" --mode analysis --in $AnalysisOutput

Write-Host "Run $RunId Complete."
