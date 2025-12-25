# Orchestrator for Threadripper 9000 RDIMM Monitor
# Usage: ./orchestrator.ps1 [-RunDiscovery]

param (
    [switch]$RunDiscovery = $false
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path ".."
$RunId = Get-Date -Format "yyyyMMdd-HHmmss"
$TmpDir = Join-Path $env:USERPROFILE ".gemini\tmp\tr9-run-$RunId"
$PromptsDir = Join-Path $Root "docs\prompts"

Write-Host "Starting Run $RunId"
Write-Host "Temp Dir: $TmpDir"
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

# --- Helper Function to Run Claude ---
function Run-ClaudeAgent {
    param (
        [string]$AgentName,
        [string]$PromptFile,
        [string]$InputJsonFile,
        [string]$OutputFile
    )
    Write-Host "[$AgentName] Starting..."
    
    # Read Input Context
    $InputContent = Get-Content -Raw $InputJsonFile
    
    # Read Prompt Template
    $PromptContent = Get-Content -Raw $PromptFile
    
    # Combine (Simple Injection) - In real usage, might need more robust templating
    # We prepend the input context as a system message or user block
    $FullPrompt = "Context Data:`n$InputContent`n`nTask:`n$PromptContent"
    $FullPromptPath = Join-Path $TmpDir "$AgentName-full-prompt.md"
    $FullPrompt | Set-Content $FullPromptPath

    # Run Claude Code CLI (Mocking the call for now as 'claude' might not be in path or configured)
    # In production: claude --print --prompt-file $FullPromptPath > $OutputFile
    
    Write-Host "[$AgentName] Executing Claude..."
    # START MOCK
    Start-Sleep -Seconds 2
    "{ "status": "success", "mock_data": true }" | Set-Content $OutputFile
    # END MOCK
    
    Write-Host "[$AgentName] Finished."
}

# --- Phase 1: Discovery ---
if ($RunDiscovery) {
    Write-Host "--- Phase 1: Discovery ---"
    # 1. Get Search Terms (Mock Python Call)
    $DiscoveryInput = Join-Path $TmpDir "discovery_input.json"
    python scripts/db_get_tasks.py --mode discovery --out $DiscoveryInput
    
    # 2. Run Agent
    $DiscoveryOutput = Join-Path $TmpDir "discovery_output.json"
    Run-ClaudeAgent -AgentName "Discovery" -PromptFile "$PromptsDir\discovery.md" -InputJsonFile $DiscoveryInput -OutputFile $DiscoveryOutput
    
    # 3. Ingest Results
    python scripts/db_ingest.py --mode discovery --in $DiscoveryOutput
}

# --- Phase 2: Scraping ---
Write-Host "--- Phase 2: Scraping ---"
# 1. Get URLs to Scrape
$ScrapeInput = Join-Path $TmpDir "scrape_input.json"
python scripts/db_get_tasks.py --mode scrape --out $ScrapeInput

# 2. Run Agents (Parallel)
# For simplicity in this v1, we run sequential. 
# To do parallel in PS: Start-Job -ScriptBlock { ... }
$ScrapeOutput = Join-Path $TmpDir "scrape_output.json"
Run-ClaudeAgent -AgentName "Scraper" -PromptFile "$PromptsDir\scraper.md" -InputJsonFile $ScrapeInput -OutputFile $ScrapeOutput

# 3. Ingest Results
python scripts/db_ingest.py --mode scrape --in $ScrapeOutput

# --- Phase 3: Analysis ---
Write-Host "--- Phase 3: Analysis ---"
$AnalysisInput = Join-Path $TmpDir "analysis_input.json"
python scripts/db_get_tasks.py --mode analysis --out $AnalysisInput

$AnalysisOutput = Join-Path $TmpDir "analysis_output.json"
Run-ClaudeAgent -AgentName "Analyst" -PromptFile "$PromptsDir\analyst.md" -InputJsonFile $AnalysisInput -OutputFile $AnalysisOutput

python scripts/db_ingest.py --mode analysis --in $AnalysisOutput

Write-Host "Run $RunId Complete."
