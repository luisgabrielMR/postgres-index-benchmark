$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ResultsDir = Join-Path $ProjectRoot "results"

Set-Location $ProjectRoot
New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Invoke-DockerComposeCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments
    )

    $output = & docker compose @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }

    return $output
}

function Invoke-SqlScript {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptPath
    )

    Invoke-DockerCompose -Arguments @(
        "exec", "-T", "postgres",
        "psql",
        "-U", "postgres",
        "-d", "index_benchmark",
        "-v", "ON_ERROR_STOP=1",
        "-f", $ScriptPath
    )
}

function Invoke-SqlScriptCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ScriptPath
    )

    Invoke-DockerComposeCapture -Arguments @(
        "exec", "-T", "postgres",
        "psql",
        "-U", "postgres",
        "-d", "index_benchmark",
        "-v", "ON_ERROR_STOP=1",
        "-f", $ScriptPath
    )
}

function Get-ExecutionTimeMs {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $match = Select-String -Path $Path -Pattern "Execution Time: ([0-9.]+) ms" | Select-Object -Last 1
    if ($null -eq $match) {
        return ""
    }

    return $match.Matches[0].Groups[1].Value
}

function Get-FirstRegexValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Pattern,

        [string] $DefaultValue = "0"
    )

    $match = Select-String -Path $Path -Pattern $Pattern | Select-Object -First 1
    if ($null -eq $match) {
        return $DefaultValue
    }

    return $match.Matches[0].Groups[1].Value
}

function Get-TopLevelSharedBufferMetric {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $MetricName
    )

    $match = Select-String -Path $Path -Pattern "Buffers: shared" | Select-Object -First 1
    if ($null -eq $match) {
        return "0"
    }

    $metric = [regex]::Match($match.Line, "$MetricName=([0-9]+)")
    if (-not $metric.Success) {
        return "0"
    }

    return $metric.Groups[1].Value
}

Write-Host "Starting PostgreSQL with Docker Compose..."
Invoke-DockerCompose -Arguments @("up", "-d")

Write-Host "Waiting for PostgreSQL to become available..."
$isReady = $false
for ($attempt = 1; $attempt -le 60; $attempt++) {
    & docker compose exec -T postgres pg_isready -U postgres -d index_benchmark *> $null
    if ($LASTEXITCODE -eq 0) {
        $isReady = $true
        break
    }

    Start-Sleep -Seconds 1
}

if (-not $isReady) {
    throw "PostgreSQL did not become available in time."
}

Write-Host "PostgreSQL is ready."

Write-Host "Creating schema..."
Invoke-SqlScript -ScriptPath "/sql/01_create_schema.sql"

Write-Host "Seeding fake data..."
Invoke-SqlScript -ScriptPath "/sql/02_seed_data.sql"

Write-Host "Running query before index..."
$beforeOutput = Invoke-SqlScriptCapture -ScriptPath "/sql/03_query_before_index.sql"
$beforePath = Join-Path $ResultsDir "before-index.txt"
$beforeOutput | Set-Content -Path $beforePath -Encoding UTF8

Write-Host "Creating index..."
Invoke-SqlScript -ScriptPath "/sql/04_create_index.sql"

Write-Host "Running query after index..."
$afterOutput = Invoke-SqlScriptCapture -ScriptPath "/sql/05_query_after_index.sql"
$afterPath = Join-Path $ResultsDir "after-index.txt"
$afterOutput | Set-Content -Path $afterPath -Encoding UTF8

$beforeMs = Get-ExecutionTimeMs -Path $beforePath
$afterMs = Get-ExecutionTimeMs -Path $afterPath
$summaryPath = Join-Path $ResultsDir "summary.csv"
@(
    "scenario,execution_time_ms",
    "before_index,$beforeMs",
    "after_index,$afterMs"
) | Set-Content -Path $summaryPath -Encoding UTF8

$beforeSharedHits = Get-TopLevelSharedBufferMetric -Path $beforePath -MetricName "hit"
$beforeSharedReads = Get-TopLevelSharedBufferMetric -Path $beforePath -MetricName "read"
$beforeRowsRemoved = Get-FirstRegexValue -Path $beforePath -Pattern "Rows Removed by Filter: ([0-9]+)"
$beforeSortMemoryKb = Get-FirstRegexValue -Path $beforePath -Pattern "Sort Method: .* Memory: ([0-9]+)kB"
$beforeWorkersLaunched = Get-FirstRegexValue -Path $beforePath -Pattern "Workers Launched: ([0-9]+)"

$afterSharedHits = Get-TopLevelSharedBufferMetric -Path $afterPath -MetricName "hit"
$afterSharedReads = Get-TopLevelSharedBufferMetric -Path $afterPath -MetricName "read"
$afterRowsRemoved = Get-FirstRegexValue -Path $afterPath -Pattern "Rows Removed by Filter: ([0-9]+)"
$afterSortMemoryKb = Get-FirstRegexValue -Path $afterPath -Pattern "Sort Method: .* Memory: ([0-9]+)kB"
$afterWorkersLaunched = Get-FirstRegexValue -Path $afterPath -Pattern "Workers Launched: ([0-9]+)"

$resourceSummaryPath = Join-Path $ResultsDir "resource-summary.csv"
@(
    "scenario,shared_hit_blocks,shared_read_blocks,rows_removed_by_filter,sort_memory_kb,workers_launched",
    "before_index,$beforeSharedHits,$beforeSharedReads,$beforeRowsRemoved,$beforeSortMemoryKb,$beforeWorkersLaunched",
    "after_index,$afterSharedHits,$afterSharedReads,$afterRowsRemoved,$afterSortMemoryKb,$afterWorkersLaunched"
) | Set-Content -Path $resourceSummaryPath -Encoding UTF8

Write-Host "Benchmark finished."
Write-Host "Results saved to:"
Write-Host "- $beforePath"
Write-Host "- $afterPath"
Write-Host "- $summaryPath"
Write-Host "- $resourceSummaryPath"
