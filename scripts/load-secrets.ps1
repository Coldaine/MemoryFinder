# Load secrets from Bitwarden Secrets Manager into environment variables
# Usage: . .\load-secrets.ps1   (note the dot-space for sourcing)
#
# Required secrets in BWS:
#   - DATABASE_URL
#   - FIRECRAWL_API_KEY
#   - TAVILY_API_KEY
#   - BRAVE_SEARCH_API_KEY
#   - EXA_API_KEY
#   - SERP_API_KEY (optional)
#   - Z_AI_API_KEY (optional, for z.ai backend)

$ErrorActionPreference = "Stop"

Write-Host "Loading secrets from Bitwarden Secrets Manager..." -ForegroundColor Cyan

# Required secrets for MCP servers
$requiredSecrets = @(
    "DATABASE_URL",
    "FIRECRAWL_API_KEY",
    "TAVILY_API_KEY",
    "BRAVE_SEARCH_API_KEY",
    "EXA_API_KEY"
)

# Optional secrets
$optionalSecrets = @(
    "SERP_API_KEY",
    "Z_AI_API_KEY",
    "PERPLEXITY_API_KEY"
)

# Fetch all secrets from BWS
try {
    $secrets = bws secret list 2>&1 | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to fetch secrets from BWS. Is it configured?" -ForegroundColor Red
    Write-Host "Run: bws config" -ForegroundColor Yellow
    exit 1
}

# Create a lookup table
$secretLookup = @{}
foreach ($secret in $secrets) {
    $secretLookup[$secret.key] = $secret.value
}

# Load required secrets
$missingSecrets = @()
foreach ($key in $requiredSecrets) {
    if ($secretLookup.ContainsKey($key)) {
        Set-Item -Path "Env:$key" -Value $secretLookup[$key]
        Write-Host "  [OK] $key" -ForegroundColor Green
    } else {
        $missingSecrets += $key
        Write-Host "  [MISSING] $key" -ForegroundColor Red
    }
}

# Load optional secrets
foreach ($key in $optionalSecrets) {
    if ($secretLookup.ContainsKey($key)) {
        Set-Item -Path "Env:$key" -Value $secretLookup[$key]
        Write-Host "  [OK] $key (optional)" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] $key (optional, not found)" -ForegroundColor Gray
    }
}

if ($missingSecrets.Count -gt 0) {
    Write-Host "`nERROR: Missing required secrets: $($missingSecrets -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "`nSecrets loaded successfully!" -ForegroundColor Cyan
Write-Host "MCP servers should now be able to connect." -ForegroundColor Gray
