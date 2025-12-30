# Smoke Test for MemoryFinder Orchestrator
# Usage: ./smoke-test.ps1
#
# Runs a minimal test to verify Claude invocation works correctly.
# All output goes to tests/output/ to avoid polluting production data.

param (
    [switch]$SkipDiscovery = $false
)

$ErrorActionPreference = "Stop"
$TestRoot = Split-Path -Parent $PSScriptRoot
$ScriptsDir = Join-Path $TestRoot "scripts"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MemoryFinder Smoke Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check prerequisites
Write-Host "[1/4] Checking prerequisites..." -ForegroundColor Yellow

# Check claude is available
try {
    $claudeVersion = claude --version 2>&1
    Write-Host "  Claude CLI: $claudeVersion" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: 'claude' command not found in PATH" -ForegroundColor Red
    Write-Host "  Install Claude Code CLI first: https://claude.ai/code" -ForegroundColor Red
    exit 1
}

# Check Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "  Python: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: 'python' not found in PATH" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/4] Initializing test database..." -ForegroundColor Yellow
Push-Location $ScriptsDir
try {
    # Create test data directory
    $testDataDir = Join-Path $TestRoot "tests\data"
    New-Item -ItemType Directory -Force -Path $testDataDir | Out-Null

    # Set test DB path via environment
    $env:MEMORYFINDER_DB = Join-Path $testDataDir "memoryfinder_test.db"

    python db_common.py
    Write-Host "  Test DB initialized at: $env:MEMORYFINDER_DB" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[3/4] Running orchestrator in test mode..." -ForegroundColor Yellow

$orchestratorArgs = @("-TestMode")
if (-not $SkipDiscovery) {
    $orchestratorArgs += "-RunDiscovery"
}

Push-Location $ScriptsDir
try {
    $startTime = Get-Date
    & ".\orchestrator.ps1" @orchestratorArgs
    $duration = (Get-Date) - $startTime
    Write-Host "  Completed in $($duration.TotalSeconds.ToString('F1')) seconds" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Orchestrator failed: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "[4/4] Checking output..." -ForegroundColor Yellow

$outputDir = Join-Path $TestRoot "tests\output"
$runDirs = Get-ChildItem -Path $outputDir -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($runDirs) {
    $latestRun = $runDirs.FullName
    Write-Host "  Latest run: $($runDirs.Name)" -ForegroundColor Green

    $outputFiles = Get-ChildItem -Path $latestRun -File
    Write-Host "  Output files:" -ForegroundColor Green
    foreach ($file in $outputFiles) {
        $sizeKB = [math]::Round($file.Length / 1024, 1)
        Write-Host "    - $($file.Name) (${sizeKB}KB)" -ForegroundColor Gray
    }

    # Quick validation of output JSON
    $scrapeOutput = Join-Path $latestRun "scrape_output.json"
    if (Test-Path $scrapeOutput) {
        try {
            $content = Get-Content -Raw $scrapeOutput | ConvertFrom-Json
            if ($content.status -eq "error") {
                Write-Host "  WARNING: Scrape returned error: $($content.error)" -ForegroundColor Yellow
            } else {
                Write-Host "  Scrape output is valid JSON" -ForegroundColor Green
            }
        } catch {
            Write-Host "  WARNING: Could not parse scrape_output.json" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  WARNING: No output directories found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Smoke Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Review output at: $outputDir" -ForegroundColor Gray
